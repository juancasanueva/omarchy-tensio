import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

// Tensio bar widget: a heart with the active profile's last reading in the
// bar, and a keyboard panel with Records, Analysis and Report pages.
//
// All persistence goes through bin/tensio_store.py, invoked as an argv
// array with an isolated interpreter (-I -S) and bounded output. The state
// returned by `load` is validated again here (Model.validateState); when it
// cannot be read or validated, the panel shows an error and refuses to save,
// so a state it could not read is never overwritten.
Panel {
    id: root
    moduleName: 'io.github.juancasanueva.tensio'
    ipcTarget: 'io.github.juancasanueva.tensio'
    manageIpc: true
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // ------------------------------------------------------------ helper

    readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl('.')).replace(/^file:\/\//, '')).replace(/\/$/, '')
    readonly property string helper: pluginDir + '/bin/tensio_store.py'
    readonly property var helperArgv: ['/usr/bin/python3', '-I', '-S', root.helper]
    readonly property int loadMaxBytes: 4 * 1024 * 1024 + 64 * 1024
    readonly property int smallMaxBytes: 64 * 1024

    // ------------------------------------------------------------- state

    property var store: Model.emptyState()
    property bool loaded: false
    property bool loading: false
    property bool loadFailed: false
    property string loadError: ''
    property string saveError: ''
    property int mutationGen: 0
    property int loadStartGen: 0
    property bool reloadAfterSave: false

    // Saving is allowed only after a successful load of the current state.
    readonly property bool canSave: loaded && !loadFailed

    readonly property var profiles: store.profiles || []
    readonly property bool hasProfiles: profiles.length > 0
    readonly property string activeId: {
        var list = root.profiles
        for (var i = 0; i < list.length; i++)
            if (list[i].id === root.store.activeProfile) return list[i].id
        return list.length ? list[0].id : ''
    }
    readonly property var activeProfile: {
        var list = root.profiles
        for (var i = 0; i < list.length; i++)
            if (list[i].id === root.activeId) return list[i]
        return null
    }
    readonly property var profileReadings: Model.filterReadings(store.readings, activeId, 'all')
    readonly property var lastReading: Model.lastReading(store.readings, activeId)
    readonly property string lastCategoryKey: lastReading ? Model.categoryOf(lastReading.sys, lastReading.dia) : ''

    // --------------------------------------------------------------- UI

    property int tab: 0
    property string view: 'pages'          // pages | form | info
    property var editingReading: null
    property bool menuOpen: false
    property string nameMode: ''           // '' | add | rename
    property string rangeKey: '7d'
    property var pendingConfirm: null
    property bool exporting: false
    property string exportPath: ''
    property string exportError: ''

    readonly property var tabs: ['Records', 'Analysis', 'Report']
    // Re-evaluated whenever the panel opens so "7 days" follows the clock.
    property real rangeClock: Date.now()
    readonly property var rangeReadings: Model.filterReadings(store.readings, activeId, rangeKey, new Date(rangeClock))

    readonly property string tooltip: {
        if (!root.activeProfile) return 'Tensio'
        var r = root.lastReading
        if (!r) return 'Tensio · ' + root.activeProfile.name + ' · No readings yet'
        return 'Tensio · ' + root.activeProfile.name + ' · ' + Model.readingLine(r) + ' mmHg · ♥ ' + r.pulse
            + ' · ' + Model.category(root.lastCategoryKey).label + ' · ' + Model.formatDateTime(r.at)
    }

    // ------------------------------------------------------- store calls

    function firstLine(text, fallback) {
        var line = String(text || '').split('\n')[0].trim()
        if (line.length > 300) line = line.slice(0, 300)
        return line !== '' ? line : fallback
    }

    function reload() {
        root.rangeClock = Date.now()
        if (saveProc.busy) {
            // Read after the pending write lands, never alongside it.
            root.reloadAfterSave = true
            return
        }
        if (loadProc.busy) return
        root.loading = true
        root.loadStartGen = root.mutationGen
        loadProc.run(root.helperArgv.concat(['load']))
    }

    function onLoadFinished(code, out, err) {
        root.loading = false
        // A change made while the read was in flight wins over the read.
        if (root.loadStartGen !== root.mutationGen) return
        if (code !== 0) {
            root.loadFailed = true
            root.loadError = root.firstLine(err, 'The state helper failed.')
            return
        }
        var parsed
        try {
            parsed = JSON.parse(out)
        } catch (e) {
            root.loadFailed = true
            root.loadError = 'The state helper returned invalid JSON.'
            return
        }
        var result = Model.validateState(parsed)
        if (!result.ok) {
            root.loadFailed = true
            root.loadError = root.firstLine(result.errors[0], 'Saved data failed validation.')
            return
        }
        root.store = result.state
        root.loaded = true
        root.loadFailed = false
        root.loadError = ''
    }

    function cloneStore() {
        return JSON.parse(JSON.stringify(root.store))
    }

    // Validates, applies in memory, then persists. Returns false when the
    // change was refused.
    function commit(next) {
        if (!root.canSave) {
            root.saveError = 'Saving is disabled because the saved data could not be read.'
            return false
        }
        var result = Model.validateState(next)
        if (!result.ok) {
            root.saveError = root.firstLine(result.errors[0], 'The change was rejected.')
            return false
        }
        root.store = result.state
        root.mutationGen += 1
        root.saveError = ''
        saveProc.run(root.helperArgv.concat(['save']), JSON.stringify(result.state))
        return true
    }

    function onSaveFinished(code, out, err) {
        if (code !== 0) {
            root.saveError = 'Could not save: ' + root.firstLine(err, 'the state helper failed.')
            // Show what is really on disk, unless a newer save is already queued.
            Qt.callLater(function () { if (!saveProc.busy) root.reload() })
            return
        }
        if (root.reloadAfterSave && !saveProc.busy) {
            root.reloadAfterSave = false
            root.reload()
        }
    }

    // ---------------------------------------------------------- profiles

    function uniqueId(prefix, taken) {
        for (var attempt = 0; attempt < 20; attempt++) {
            var id = Model.newId(prefix)
            if (!taken(id)) return id
        }
        return ''
    }

    function addProfile(name) {
        if (root.profiles.length >= Model.LIMITS.profiles) {
            root.saveError = 'At most ' + Model.LIMITS.profiles + ' profiles are supported.'
            return false
        }
        var next = root.cloneStore()
        var id = root.uniqueId('p', function (candidate) {
            return next.profiles.some(function (p) { return p.id === candidate })
        })
        if (id === '') return false
        next.profiles.push({ id: id, name: name, color: Model.initialColor(next.profiles.length), createdAt: Model.toAt(new Date()) })
        next.activeProfile = id
        return root.commit(next)
    }

    function renameProfile(name) {
        if (!root.activeId) return false
        var next = root.cloneStore()
        for (var i = 0; i < next.profiles.length; i++)
            if (next.profiles[i].id === root.activeId) next.profiles[i].name = name
        return root.commit(next)
    }

    function deleteProfile(id) {
        var next = root.cloneStore()
        next.profiles = next.profiles.filter(function (p) { return p.id !== id })
        next.readings = next.readings.filter(function (r) { return r.profileId !== id })
        if (next.activeProfile === id || !next.profiles.some(function (p) { return p.id === next.activeProfile }))
            next.activeProfile = next.profiles.length ? next.profiles[0].id : null
        return root.commit(next)
    }

    function selectProfile(id) {
        root.menuOpen = false
        if (id === root.activeId) return
        var next = root.cloneStore()
        next.activeProfile = id
        root.exportPath = ''
        root.exportError = ''
        root.commit(next)
    }

    // ---------------------------------------------------------- readings

    function saveReading(value) {
        var next = root.cloneStore()
        var replaced = false
        for (var i = 0; i < next.readings.length; i++) {
            if (next.readings[i].id === value.id) {
                next.readings[i] = value
                replaced = true
            }
        }
        if (!replaced) {
            if (next.readings.length >= Model.LIMITS.readings) {
                root.saveError = 'At most ' + Model.LIMITS.readings + ' readings are supported.'
                return false
            }
            if (next.readings.some(function (r) { return r.id === value.id })) return false
            next.readings.push(value)
        }
        return root.commit(next)
    }

    function deleteReading(id) {
        var next = root.cloneStore()
        next.readings = next.readings.filter(function (r) { return r.id !== id })
        return root.commit(next)
    }

    // ------------------------------------------------------------ export

    function runExport(format) {
        if (root.exporting || !root.activeId || (format !== 'pdf' && format !== 'csv')) return
        if (['7d', '30d', 'all'].indexOf(root.rangeKey) < 0) return
        root.exportPath = ''
        root.exportError = ''
        root.exporting = true
        // Values are allowlisted (profile id regex, closed range set); the
        // helper's parser takes them at fixed positions.
        var started = exportProc.run(root.helperArgv.concat(['export', format, '--profile', root.activeId, '--range', root.rangeKey]))
        if (!started) root.exporting = false
    }

    function onExportFinished(code, out, err) {
        root.exporting = false
        if (code !== 0) {
            root.exportError = 'Export failed: ' + root.firstLine(err, 'the helper reported an error.')
            return
        }
        var parsed = null
        try {
            parsed = JSON.parse(out)
        } catch (e) {
            parsed = null
        }
        var path = parsed && typeof parsed.path === 'string' ? parsed.path : ''
        if (!Model.isExportPath(path)) {
            root.exportError = 'Export failed: the helper returned an unexpected path.'
            return
        }
        root.exportPath = path
    }

    // Only the path the helper just reported, re-validated, is ever opened.
    function openExport(path) {
        if (path !== root.exportPath || !Model.isExportPath(path)) return
        Quickshell.execDetached(['/usr/bin/xdg-open', path])
    }

    function openExportFolder(path) {
        if (path !== root.exportPath) return
        var folder = Model.exportFolder(path)
        if (folder === '') return
        Quickshell.execDetached(['/usr/bin/xdg-open', folder])
    }

    // ------------------------------------------------------- navigation

    function openForm(reading) {
        if (!root.canSave || !root.activeId) return
        root.menuOpen = false
        root.editingReading = reading || null
        root.view = 'form'
    }

    function closeForm() {
        root.view = 'pages'
        root.editingReading = null
        body.forceActiveFocus()
    }

    function startNameEdit(mode) {
        root.menuOpen = false
        if (!root.canSave) return
        root.nameMode = mode
        nameEditor.reset(mode === 'rename' && root.activeProfile ? root.activeProfile.name : '')
        Qt.callLater(nameEditor.focusField)
    }

    function endNameEdit() {
        root.nameMode = ''
        body.forceActiveFocus()
    }

    function askConfirm(kind, id, message, confirmText) {
        root.menuOpen = false
        root.pendingConfirm = { kind: kind, id: id }
        confirm.message = Model.plain(message, 180)
        confirm.confirmText = confirmText
        confirm.selectedIndex = 0
        confirm.opened = true
    }

    function confirmDeleteReading(reading) {
        if (!reading || !root.canSave) return
        root.askConfirm('reading', reading.id,
            'Delete the reading ' + Model.readingLine(reading) + ' from ' + Model.formatDateTime(reading.at) + '?', 'Delete')
    }

    function confirmDeleteProfile() {
        if (!root.activeProfile || !root.canSave) return
        var count = root.profileReadings.length
        root.askConfirm('profile', root.activeId,
            'Delete profile ' + root.activeProfile.name + ' and its ' + count + (count === 1 ? ' reading' : ' readings') + '? This cannot be undone.', 'Delete')
    }

    function resolveConfirm(accepted) {
        var pending = root.pendingConfirm
        confirm.opened = false
        root.pendingConfirm = null
        body.forceActiveFocus()
        if (!accepted || !pending) return
        if (pending.kind === 'reading') root.deleteReading(pending.id)
        else if (pending.kind === 'profile') root.deleteProfile(pending.id)
    }

    function handleEscape() {
        if (root.menuOpen) root.menuOpen = false
        else if (root.view === 'form') root.closeForm()
        else if (root.view === 'info') root.view = 'pages'
        else if (root.nameMode !== '') root.endNameEdit()
        else root.close()
    }

    onOpenedChanged: {
        if (opened) {
            root.reload()
        } else {
            root.menuOpen = false
            if (confirm.opened) root.resolveConfirm(false)
        }
    }

    Component.onCompleted: root.reload()

    // --------------------------------------------------------- processes

    BoundedProcess {
        id: loadProc
        maxBytes: root.loadMaxBytes
        timeoutMs: 10000
        onFinished: function (code, out, err) { root.onLoadFinished(code, out, err) }
    }

    BoundedProcess {
        id: saveProc
        maxBytes: root.smallMaxBytes
        timeoutMs: 10000
        onFinished: function (code, out, err) { root.onSaveFinished(code, out, err) }
    }

    BoundedProcess {
        id: exportProc
        maxBytes: root.smallMaxBytes
        timeoutMs: 30000
        queueWhenBusy: false
        onFinished: function (code, out, err) { root.onExportFinished(code, out, err) }
    }

    // ------------------------------------------------------------ bar

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        fixedWidth: vertical ? -1 : barRow.implicitWidth + Style.space(14)
        tooltipText: Model.plain(root.tooltip, 160)
        onPressed: function (b) { root.toggle() }

        Row {
            id: barRow
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: '♥'
                color: root.lastReading ? Model.category(root.lastCategoryKey).color : root.barForeground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
            }
            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                visible: !button.vertical && root.lastReading !== null
                text: Model.readingLine(root.lastReading)
                color: root.lastReading ? Model.category(root.lastCategoryKey).color : root.barForeground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
            }
        }
    }

    // ---------------------------------------------------------- panel

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: body
        contentWidth: panel.fittedContentWidth(640)
        contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, 820)

        Item {
            id: body
            anchors.fill: parent
            focus: true
            clip: true

            readonly property color fg: Color.popups.text
            readonly property color muted: Util.alpha(Color.popups.text, 0.6)
            // Height left for the page area once the header, banners and tab
            // bar are laid out, capped so the card fits on small screens.
            readonly property real chromeHeight: header.implicitHeight + (nameEditor.visible ? nameEditor.implicitHeight + mainColumn.spacing : 0)
                + (banner.visible ? banner.implicitHeight + mainColumn.spacing : 0)
                + tabBar.height + mainColumn.spacing * 3 + separator.height
            readonly property real available: panel.availableCardHeight > 0 ? Math.min(820, panel.availableCardHeight) - panel.verticalContentInset : 820
            readonly property real pageHeight: Math.max(Style.space(220), Math.min(Style.space(520), available - chromeHeight))

            Keys.onPressed: function (event) {
                if (confirm.opened) {
                    if (confirm.handleKey(event)) event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Escape) {
                    root.handleEscape()
                    event.accepted = true
                    return
                }
                if (root.view !== 'pages' || root.nameMode !== '' || root.menuOpen || !root.hasProfiles) return
                if (event.key === Qt.Key_Left) {
                    root.tab = Math.max(0, root.tab - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.tab = Math.min(root.tabs.length - 1, root.tab + 1)
                    event.accepted = true
                }
            }

            Column {
                id: mainColumn
                width: parent.width
                spacing: Style.space(10)

                ProfileHeader {
                    id: header
                    width: parent.width
                    profile: root.activeProfile
                    lastReading: root.lastReading
                    menuOpen: root.menuOpen
                    onMenuRequested: if (root.loaded) root.menuOpen = !root.menuOpen
                    onInfoRequested: {
                        root.menuOpen = false
                        root.view = root.view === 'info' ? 'pages' : 'info'
                    }
                }

                NameEditor {
                    id: nameEditor
                    width: parent.width
                    visible: root.nameMode !== ''
                    title: root.nameMode === 'rename' ? 'Rename profile' : 'New profile name'
                    onSubmitted: function (name) {
                        var ok = root.nameMode === 'rename' ? root.renameProfile(name) : root.addProfile(name)
                        if (ok) root.endNameEdit()
                    }
                    onCanceled: root.endNameEdit()
                }

                Rectangle {
                    id: banner
                    width: parent.width
                    readonly property string message: root.loadFailed
                        ? 'Could not read your saved readings: ' + root.loadError + ' Saving is disabled so nothing is overwritten.'
                        : root.saveError
                    visible: message !== ''
                    implicitHeight: bannerRow.implicitHeight + Style.space(16)
                    radius: Math.max(6, Style.cornerRadius)
                    color: Util.alpha(Color.urgent, 0.16)
                    border.width: 1
                    border.color: Util.alpha(Color.urgent, 0.6)

                    Row {
                        id: bannerRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(8)
                        spacing: Style.space(8)

                        PlainLabel {
                            width: parent.width - retryButton.width - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: banner.message
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            maximumLineCount: 4
                        }
                        Button {
                            id: retryButton
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.loadFailed ? 'Retry' : 'Dismiss'
                            bordered: true
                            foreground: Color.popups.text
                            onClicked: {
                                if (root.loadFailed) root.reload()
                                else root.saveError = ''
                            }
                        }
                    }
                }

                PanelSeparator {
                    id: separator
                    foreground: Color.popups.text
                }

                Item {
                    id: contentArea
                    width: parent.width
                    height: body.pageHeight

                    PlainLabel {
                        anchors.centerIn: parent
                        visible: !root.loaded && !root.loadFailed
                        text: 'Loading…'
                        color: body.muted
                    }

                    // First run: ask for the first profile name.
                    Card {
                        id: onboarding
                        visible: root.loaded && !root.loadFailed && !root.hasProfiles && root.view === 'pages'
                        anchors.centerIn: parent
                        width: Math.min(parent.width, Style.space(420))
                        height: onboardingColumn.implicitHeight + Style.space(32)

                        Column {
                            id: onboardingColumn
                            anchors.fill: parent
                            anchors.margins: Style.space(16)
                            spacing: Style.space(10)

                            PlainLabel { text: 'Welcome to Tensio'; font.pixelSize: Style.font.heading; font.bold: true }
                            PlainLabel {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                text: 'Create a profile for the person whose blood pressure you want to log. You can add more profiles later.'
                                color: body.muted
                            }
                            NameEditor {
                                id: onboardingEditor
                                width: parent.width
                                title: 'Profile name'
                                confirmText: 'Create profile'
                                showCancel: false
                                onSubmitted: function (name) {
                                    if (root.addProfile(name)) onboardingEditor.reset('')
                                }
                            }
                        }
                    }

                    RecordsPage {
                        anchors.fill: parent
                        visible: root.hasProfiles && root.view === 'pages' && root.tab === 0
                        readings: root.profileReadings
                        canEdit: root.canSave
                        onAddRequested: root.openForm(null)
                        onEditRequested: function (reading) { root.openForm(reading) }
                        onDeleteRequested: function (reading) { root.confirmDeleteReading(reading) }
                    }

                    AnalysisPage {
                        anchors.fill: parent
                        visible: root.hasProfiles && root.view === 'pages' && root.tab === 1
                        readings: root.rangeReadings
                        rangeKey: root.rangeKey
                        onRangeSelected: function (key) { root.rangeKey = key }
                    }

                    ReportPage {
                        anchors.fill: parent
                        visible: root.hasProfiles && root.view === 'pages' && root.tab === 2
                        profile: root.activeProfile
                        readings: root.rangeReadings
                        rangeKey: root.rangeKey
                        busy: root.exporting
                        canExport: root.loaded && !root.loadFailed
                        exportPath: root.exportPath
                        exportError: root.exportError
                        onRangeSelected: function (key) {
                            root.rangeKey = key
                            root.exportPath = ''
                            root.exportError = ''
                        }
                        onExportRequested: function (format) { root.runExport(format) }
                        onOpenRequested: function (path) { root.openExport(path) }
                        onOpenFolderRequested: function (path) { root.openExportFolder(path) }
                    }

                    InfoView {
                        anchors.fill: parent
                        visible: root.view === 'info'
                        onCloseRequested: root.view = 'pages'
                    }

                    // The form is created fresh for each add / edit so every
                    // field starts from the reading (or the defaults).
                    Flickable {
                        id: formFlick
                        anchors.fill: parent
                        visible: root.view === 'form'
                        contentWidth: width
                        contentHeight: formLoader.item ? formLoader.item.implicitHeight + Style.space(8) : 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Loader {
                            id: formLoader
                            width: formFlick.width
                            active: root.view === 'form'
                            sourceComponent: readingFormComponent
                        }
                    }

                    Component {
                        id: readingFormComponent
                        ReadingForm {
                            width: formFlick.width
                            reading: root.editingReading
                            profileId: root.activeId
                            onCanceled: root.closeForm()
                            onSaved: function (value) {
                                if (root.saveReading(value)) root.closeForm()
                            }
                        }
                    }
                }

                // Tab bar.
                Row {
                    id: tabBar
                    width: parent.width
                    visible: root.hasProfiles
                    opacity: root.view === 'pages' ? 1 : 0.4
                    height: Style.space(38)

                    Repeater {
                        model: root.tabs
                        delegate: Item {
                            id: tabItem
                            required property string modelData
                            required property int index
                            readonly property bool selected: root.tab === index
                            width: tabBar.width / root.tabs.length
                            height: tabBar.height

                            Rectangle {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.6
                                height: Style.space(2)
                                radius: height / 2
                                color: tabItem.selected ? Color.accent : 'transparent'
                            }
                            PlainLabel {
                                anchors.centerIn: parent
                                text: tabItem.modelData
                                color: tabItem.selected ? Color.accent : body.muted
                                font.bold: tabItem.selected
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.menuOpen = false
                                    if (root.view === 'info') root.view = 'pages'
                                    if (root.view === 'pages') root.tab = tabItem.index
                                }
                            }
                        }
                    }
                }
            }

            // Click-away layer and profile menu, above the page content.
            MouseArea {
                anchors.fill: parent
                visible: root.menuOpen
                z: 10
                onClicked: root.menuOpen = false
            }

            ProfileMenu {
                z: 11
                visible: root.menuOpen
                x: Style.space(50)
                y: header.y + header.height + Style.space(4)
                width: Math.min(body.width - x, Style.space(280))
                profiles: root.profiles
                activeId: root.activeId
                activeName: root.activeProfile ? root.activeProfile.name : ''
                canEdit: root.canSave
                onProfileSelected: function (id) { root.selectProfile(id) }
                onAddRequested: root.startNameEdit('add')
                onRenameRequested: root.startNameEdit('rename')
                onDeleteRequested: root.confirmDeleteProfile()
            }

            ConfirmDialog {
                id: confirm
                anchors.fill: parent
                z: 20
                cancelText: 'Cancel'
                background: Color.popups.background
                foreground: Color.popups.text
                onConfirmed: root.resolveConfirm(true)
                onCanceled: root.resolveConfirm(false)
            }
        }
    }
}
