import QtQuick
import Quickshell
import Quickshell.Io

// Runs one argv command at a time with bounded output and a deadline.
//
//   - stdout and stderr are read as raw chunks (SplitParser with an empty
//     marker, so no line is buffered before it can be counted). Each stream
//     has its own UTF-8 byte budget; going over it stops the process
//     (SIGTERM, then SIGKILL) and reports a failure instead of truncating.
//   - a wall-clock deadline (timeoutMs) stops the process the same way.
//   - stdin is optional: run(argv, input) writes `input` once the process
//     has started, then closes the channel.
//   - single-flight: a run requested while one is active is queued; only
//     the latest queued request is kept (latest wins), the rest are dropped.
//   - the environment is cleared and rebuilt from a short allowlist, so
//     LD_PRELOAD, PYTHON* and friends never reach the helper.
//   - a running process is killed when the component is destroyed.
//
// finished(code, out, err) fires exactly once per run. A process that was
// stopped for overflow or timeout, or that could not be started at all,
// reports code -1 and an explanatory err. A queued run is started before
// finished fires, so `busy` (and `hasPending` before that) already reflects
// it inside a finished handler.
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property int maxBytes: 64 * 1024
    property int maxErrBytes: 4096
    property int timeoutMs: 10000
    property bool queueWhenBusy: true
    // True from start until finished has been emitted, including a start
    // that never reached the running state.
    readonly property bool busy: _active
    readonly property bool hasPending: _pending !== null

    signal finished(int code, string out, string err)

    property var _pending: null
    property string _input: ''
    property bool _hasInput: false
    property string _out: ''
    property string _err: ''
    property int _outBytes: 0
    property int _errBytes: 0
    property string _failure: ''
    property bool _active: false
    property bool _started: false
    property int _runId: 0

    // Environment handed to the helper: HOME and the XDG locations it reads,
    // a fixed PATH and a UTF-8 locale. Unset variables are left out.
    function childEnvironment() {
        var env = { PATH: '/usr/bin', LANG: 'C.UTF-8' }
        var names = ['HOME', 'XDG_STATE_HOME', 'XDG_DOCUMENTS_DIR', 'XDG_CONFIG_HOME']
        for (var i = 0; i < names.length; i++) {
            var value = Quickshell.env(names[i])
            if (value !== undefined && value !== null && String(value) !== '') env[names[i]] = String(value)
        }
        return env
    }

    // UTF-8 length of a QString chunk without allocating a byte array.
    function utf8Length(s) {
        var n = 0
        for (var i = 0; i < s.length; i++) {
            var c = s.charCodeAt(i)
            if (c < 0x80) n += 1
            else if (c < 0x800) n += 2
            else if (c >= 0xd800 && c <= 0xdbff) { n += 4; i += 1 }
            else n += 3
        }
        return n
    }

    // Starts argv (an array of strings). Returns false when the request was
    // refused (busy and queueing disabled, or an invalid argv).
    function run(argv, input) {
        if (!Array.isArray(argv) || argv.length === 0) return false
        var hasInput = input !== undefined && input !== null
        if (root.busy) {
            if (!root.queueWhenBusy) return false
            root._pending = { argv: argv.slice(), input: hasInput ? String(input) : null }
            return true
        }
        root._start(argv, hasInput ? String(input) : null)
        return true
    }

    function _start(argv, input) {
        root._out = ''
        root._err = ''
        root._outBytes = 0
        root._errBytes = 0
        root._failure = ''
        root._hasInput = input !== null
        root._input = input !== null ? input : ''
        root._active = true
        root._started = false
        root._runId += 1
        proc.environment = root.childEnvironment()
        proc.stdinEnabled = root._hasInput
        proc.command = argv
        deadline.restart()
        proc.running = true
    }

    function _stop(reason) {
        if (root._failure === '') root._failure = reason
        deadline.stop()
        if (proc.running) {
            proc.signal(15)
            killTimer.restart()
        } else {
            // Never started (or already gone): no exited signal will come.
            root._report(-1, root._runId)
        }
    }

    function _onStdout(chunk) {
        if (root._failure !== '') return
        root._outBytes += root.utf8Length(chunk)
        if (root._outBytes > root.maxBytes) {
            root._out = ''
            root._stop('Helper output exceeded ' + root.maxBytes + ' bytes.')
            return
        }
        root._out += chunk
    }

    function _onStderr(chunk) {
        if (root._failure !== '') return
        root._errBytes += root.utf8Length(chunk)
        if (root._errBytes > root.maxErrBytes) {
            root._err = ''
            root._stop('Helper error output exceeded ' + root.maxErrBytes + ' bytes.')
            return
        }
        root._err += chunk
    }

    function _onExited(code, status) {
        // A crash (exitStatus != NormalExit) is a failure even with code 0.
        if (status !== 0 && root._failure === '') root._failure = 'Helper stopped unexpectedly.'
        deadline.stop()
        killTimer.stop()
        // Let any chunk still queued on the event loop arrive before reporting.
        Qt.callLater(root._report, code, root._runId)
    }

    // A start that did not reach the running state (missing interpreter,
    // exec failure) emits no exited signal; report it here instead.
    function _onRunningChanged() {
        if (proc.running) {
            root._started = true
        } else if (root._active && !root._started) {
            if (root._failure === '') root._failure = 'Helper could not be started.'
            deadline.stop()
            Qt.callLater(root._report, -1, root._runId)
        }
    }

    // Reports run `runId` once; stale or repeated calls are ignored.
    function _report(code, runId) {
        if (!root._active || runId !== root._runId) return
        root._active = false
        deadline.stop()
        killTimer.stop()
        var failed = root._failure !== ''
        var out = failed ? '' : root._out
        var err = failed ? root._failure : root._err
        var result = failed ? -1 : code
        root._out = ''
        root._err = ''
        root._input = ''
        // Start the queued run first so handlers of finished see it as busy.
        if (root._pending) {
            var next = root._pending
            root._pending = null
            root._start(next.argv, next.input)
        }
        root.finished(result, out, err)
    }

    Process {
        id: proc
        clearEnvironment: true
        stdout: SplitParser {
            splitMarker: ''
            onRead: function (data) { root._onStdout(data) }
        }
        stderr: SplitParser {
            splitMarker: ''
            onRead: function (data) { root._onStderr(data) }
        }
        onStarted: {
            if (root._hasInput) {
                proc.write(root._input)
                root._input = ''
                // Setting stdinEnabled to false closes the channel (EOF).
                proc.stdinEnabled = false
            }
        }
        onRunningChanged: root._onRunningChanged()
        onExited: function (exitCode, exitStatus) { root._onExited(exitCode, exitStatus) }
    }

    Timer {
        id: deadline
        interval: Math.max(250, root.timeoutMs)
        repeat: false
        onTriggered: root._stop('Helper did not finish within ' + Math.round(root.timeoutMs / 1000) + ' seconds.')
    }

    Timer {
        id: killTimer
        interval: 2000
        repeat: false
        onTriggered: if (proc.running) proc.signal(9)
    }

    Component.onDestruction: {
        root._pending = null
        deadline.stop()
        if (proc.running) proc.signal(9)
    }
}
