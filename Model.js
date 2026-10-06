// Model.js - Tensio domain model.
//
// Pure functions shared by the QML panel (import "Model.js" as Model) and the
// Node test-suite (require). No Qt, DOM or file access lives here; every
// function takes plain data and returns plain data.
//
// Conventions:
//   - A reading timestamp `at` is a local ISO-8601 string without timezone,
//     minute precision: YYYY-MM-DDTHH:MM.
//   - Ids are `p_` (profile) or `r_` (reading) followed by 12 hex characters.
//   - validateReading() is forgiving (coerces and clamps interactive input);
//     validateState() is strict (rejects, never truncates) because the state
//     file is an untrusted input to the shared shell process.

var SCHEMA_VERSION = 1

var LIMITS = {
    sys: { min: 50, max: 250 },
    dia: { min: 30, max: 150 },
    pulse: { min: 30, max: 220 },
    nameMax: 40,
    noteMax: 200,
    profiles: 20,
    readings: 20000,
    plainMax: 200,
    errorsMax: 20
}

var FEELINGS = ['', 'Good', 'Normal', 'Tired', 'Stressed', 'Unwell']
var BODIES = ['', 'Sitting', 'Standing', 'Lying']
var ARMS = ['', 'Left Arm', 'Right Arm']
var RANGES = ['7d', '30d', 'all']

var CATEGORIES = [
    { key: 'low', label: 'Low', longLabel: 'Low', color: '#3b82f6', description: 'Sys<90 Or Dia<60' },
    { key: 'normal', label: 'Normal', longLabel: 'Normal', color: '#22c55e', description: 'Sys 90–119 And Dia 60–79' },
    { key: 'elevated', label: 'Elevated', longLabel: 'Elevated', color: '#eab308', description: 'Sys 120–129 And Dia<80' },
    { key: 'stage1', label: 'Stage 1', longLabel: 'Stage 1 Hypertension', color: '#f97316', description: 'Sys 130–139 Or Dia 80–89' },
    { key: 'stage2', label: 'Stage 2', longLabel: 'Stage 2 Hypertension', color: '#ef4444', description: 'Sys≥140 Or Dia≥90' },
    { key: 'severe', label: 'Severe', longLabel: 'Severe Hypertension', color: '#be123c', description: 'Sys>180 And/Or Dia>120' }
]

var SEVERE_WARNING = 'Hypertensive emergency: if a reading is this high and you have symptoms '
    + '(chest pain, shortness of breath, back pain, numbness, weakness, change in vision '
    + 'or difficulty speaking), call emergency services.'

// Profile avatar colours; the first new profile is purple like the iOS app.
var PALETTE = ['#a855f7', '#3b82f6', '#22c55e', '#f97316', '#ec4899', '#14b8a6', '#eab308', '#6366f1']

var MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
var WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

var AT_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/
var PROFILE_ID_RE = /^p_[0-9a-f]{12}$/
var READING_ID_RE = /^r_[0-9a-f]{12}$/
var COLOR_RE = /^#[0-9a-fA-F]{6}$/
// Markup, C0/C1 controls and Unicode bidi overrides; removed before text
// reaches a host-owned sink that cannot be pinned to PlainText.
var UNSAFE_RE = /[<>&\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g
// Controls and bidi overrides only; stored free text keeps < > & because
// every plugin-owned Text sink renders PlainText.
var CONTROL_RE = /[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g
var CSV_FORMULA_RE = /^[=+\-@\t\r]/

// ---------------------------------------------------------------- categories

function categoryOf(sys, dia) {
    var s = Number(sys)
    var d = Number(dia)
    if (s > 180 || d > 120) return 'severe'
    if (s >= 140 || d >= 90) return 'stage2'
    if (s >= 130 || d >= 80) return 'stage1'
    if (s >= 120) return 'elevated'
    if (s < 90 || d < 60) return 'low'
    return 'normal'
}

function category(key) {
    for (var i = 0; i < CATEGORIES.length; i++) {
        if (CATEGORIES[i].key === key) return CATEGORIES[i]
    }
    return CATEGORIES[1]
}

// --------------------------------------------------------------------- dates

function pad2(n) {
    return (n < 10 ? '0' : '') + n
}

function parseAt(at) {
    if (typeof at !== 'string') return null
    var m = AT_RE.exec(at)
    if (!m) return null
    var y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]), h = Number(m[4]), mi = Number(m[5])
    if (y < 1970 || y > 9999 || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null
    var date = new Date(y, mo - 1, d, h, mi, 0, 0)
    // Reject overflowed dates such as February 30 (hours may shift on DST days).
    if (date.getFullYear() !== y || date.getMonth() !== mo - 1 || date.getDate() !== d) return null
    return date
}

function toAt(date) {
    return date.getFullYear() + '-' + pad2(date.getMonth() + 1) + '-' + pad2(date.getDate())
        + 'T' + pad2(date.getHours()) + ':' + pad2(date.getMinutes())
}

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0)
}

function addDays(date, n) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + n, 0, 0, 0, 0)
}

// Start of the selected range; 7 days means today plus the previous six.
function rangeStart(rangeKey, now) {
    var base = startOfDay(now || new Date())
    if (rangeKey === '7d') return addDays(base, -6)
    if (rangeKey === '30d') return addDays(base, -29)
    return null
}

function dayKey(at) {
    return at.slice(0, 10)
}

// ------------------------------------------------------------------ queries

function filterReadings(readings, profileId, rangeKey, now) {
    var start = rangeStart(rangeKey, now)
    var startMs = start ? start.getTime() : null
    var keyed = []
    for (var i = 0; i < (readings || []).length; i++) {
        var r = readings[i]
        if (!r || r.profileId !== profileId) continue
        var t = parseAt(r.at)
        if (!t) continue
        var ms = t.getTime()
        if (startMs !== null && ms < startMs) continue
        keyed.push({ ms: ms, r: r })
    }
    keyed.sort(function (a, b) {
        if (a.ms !== b.ms) return a.ms - b.ms
        return a.r.id < b.r.id ? -1 : (a.r.id > b.r.id ? 1 : 0)
    })
    var out = []
    for (var j = 0; j < keyed.length; j++) out.push(keyed[j].r)
    return out
}

function averages(readings) {
    var n = (readings || []).length
    if (n === 0) return { sys: null, dia: null, pulse: null, count: 0 }
    var sys = 0, dia = 0, pulse = 0
    for (var i = 0; i < n; i++) {
        sys += Number(readings[i].sys)
        dia += Number(readings[i].dia)
        pulse += Number(readings[i].pulse)
    }
    return { sys: Math.round(sys / n), dia: Math.round(dia / n), pulse: Math.round(pulse / n), count: n }
}

function distribution(readings) {
    var counts = {}
    var i
    for (i = 0; i < CATEGORIES.length; i++) counts[CATEGORIES[i].key] = 0
    var total = (readings || []).length
    for (i = 0; i < total; i++) counts[categoryOf(readings[i].sys, readings[i].dia)] += 1
    var out = []
    for (i = 0; i < CATEGORIES.length; i++) {
        var c = CATEGORIES[i]
        var count = counts[c.key]
        out.push({ key: c.key, label: c.label, color: c.color, count: count, pct: total ? Math.round(count * 100 / total) : 0 })
    }
    return out
}

function dayLabel(key, now) {
    var today = startOfDay(now || new Date())
    if (key === toAt(today).slice(0, 10)) return 'Today'
    if (key === toAt(addDays(today, -1)).slice(0, 10)) return 'Yesterday'
    var d = parseAt(key + 'T00:00')
    if (!d) return key
    return WEEKDAYS[d.getDay()] + ', ' + MONTHS[d.getMonth()] + ' ' + d.getDate()
}

// Groups readings by calendar day, most recent day first, readings within a
// day most recent first.
function groupByDay(readings, now) {
    var keyed = []
    for (var i = 0; i < (readings || []).length; i++) {
        var t = parseAt(readings[i].at)
        if (t) keyed.push({ ms: t.getTime(), r: readings[i] })
    }
    keyed.sort(function (a, b) { return b.ms - a.ms })
    var groups = []
    var current = null
    for (var j = 0; j < keyed.length; j++) {
        var key = dayKey(keyed[j].r.at)
        if (!current || current.key !== key) {
            current = { key: key, label: dayLabel(key, now), readings: [] }
            groups.push(current)
        }
        current.readings.push(keyed[j].r)
    }
    return groups
}

// --------------------------------------------------------------- formatting

function formatTime(at) {
    var d = parseAt(at)
    if (!d) return ''
    var h = d.getHours()
    var h12 = h % 12
    if (h12 === 0) h12 = 12
    return h12 + ':' + pad2(d.getMinutes()) + ' ' + (h < 12 ? 'AM' : 'PM')
}

function formatDate(at) {
    var d = parseAt(at)
    if (!d) return ''
    return MONTHS[d.getMonth()] + ' ' + d.getDate() + ', ' + d.getFullYear()
}

function formatShortDate(at) {
    var d = parseAt(at)
    if (!d) return ''
    return MONTHS[d.getMonth()] + ' ' + d.getDate()
}

function formatDateTime(at) {
    var date = formatDate(at)
    return date ? date + ' at ' + formatTime(at) : ''
}

// -------------------------------------------------------------- validation

function randomHex(length) {
    var out = ''
    for (var i = 0; i < length; i++) out += Math.floor(Math.random() * 16).toString(16)
    return out
}

function newId(prefix) {
    return prefix + '_' + randomHex(12)
}

// Accepts a number or a numeric string; returns an integer within [min, max] or null.
function coerceInt(value, min, max) {
    if (typeof value === 'string') value = value.trim()
    if (value === '' || value === null || value === undefined || typeof value === 'boolean') return null
    var n = Number(value)
    if (!isFinite(n) || Math.floor(n) !== n) return null
    if (n < min || n > max) return null
    return n
}

// Strict variant for stored state: the value must already be an integer number.
function strictInt(value, min, max) {
    if (typeof value !== 'number' || !isFinite(value) || Math.floor(value) !== value) return null
    if (value < min || value > max) return null
    return value
}

function pickOption(value, options) {
    var v = (value === null || value === undefined) ? '' : String(value).trim()
    return options.indexOf(v) >= 0 ? v : null
}

function cleanText(value) {
    if (value === null || value === undefined) return ''
    return String(value).replace(CONTROL_RE, '').trim()
}

function validateReading(obj) {
    var src = (obj && typeof obj === 'object') ? obj : {}
    var errors = []

    var sys = coerceInt(src.sys, LIMITS.sys.min, LIMITS.sys.max)
    if (sys === null) errors.push('Systolic must be a whole number between ' + LIMITS.sys.min + ' and ' + LIMITS.sys.max + '.')
    var dia = coerceInt(src.dia, LIMITS.dia.min, LIMITS.dia.max)
    if (dia === null) errors.push('Diastolic must be a whole number between ' + LIMITS.dia.min + ' and ' + LIMITS.dia.max + '.')
    var pulse = coerceInt(src.pulse, LIMITS.pulse.min, LIMITS.pulse.max)
    if (pulse === null) errors.push('Pulse must be a whole number between ' + LIMITS.pulse.min + ' and ' + LIMITS.pulse.max + '.')

    var at = typeof src.at === 'string' ? src.at.trim() : ''
    if (!parseAt(at)) errors.push('Date and time must be a valid YYYY-MM-DDTHH:MM value.')

    var profileId = (typeof src.profileId === 'string' && PROFILE_ID_RE.test(src.profileId)) ? src.profileId : null
    if (!profileId) errors.push('Reading must belong to a profile.')

    var id = (typeof src.id === 'string' && READING_ID_RE.test(src.id)) ? src.id : newId('r')

    var feeling = pickOption(src.feeling, FEELINGS)
    if (feeling === null) errors.push('Feeling must be one of the listed options.')
    var body = pickOption(src.body, BODIES)
    if (body === null) errors.push('Body position must be one of the listed options.')
    var arm = pickOption(src.arm, ARMS)
    if (arm === null) errors.push('Arm must be one of the listed options.')

    var note = cleanText(src.note).slice(0, LIMITS.noteMax)

    return {
        ok: errors.length === 0,
        errors: errors,
        value: {
            id: id, profileId: profileId, at: at, sys: sys, dia: dia, pulse: pulse,
            feeling: feeling || '', body: body || '', arm: arm || '', note: note
        }
    }
}

function validateProfileName(name) {
    var errors = []
    var value = typeof name === 'string' ? cleanText(name) : ''
    if (typeof name !== 'string') errors.push('Profile name must be text.')
    else if (value.length === 0) errors.push('Profile name cannot be empty.')
    else if (value.length > LIMITS.nameMax) errors.push('Profile name must be at most ' + LIMITS.nameMax + ' characters.')
    return { ok: errors.length === 0, errors: errors, value: value }
}

function emptyState() {
    return { version: SCHEMA_VERSION, activeProfile: null, profiles: [], readings: [] }
}

function isPlainObject(v) {
    return v !== null && typeof v === 'object' && !Array.isArray(v)
}

function validProfile(p, seenIds, errors, index) {
    var where = 'profiles[' + index + ']'
    if (!isPlainObject(p)) { errors.push(where + ' is not an object.'); return null }
    if (typeof p.id !== 'string' || !PROFILE_ID_RE.test(p.id)) { errors.push(where + ' has an invalid id.'); return null }
    if (seenIds[p.id]) { errors.push(where + ' repeats id ' + p.id + '.'); return null }
    if (typeof p.name !== 'string' || p.name.length === 0 || p.name.length > LIMITS.nameMax
        || p.name.trim().length === 0 || CONTROL_RE.test(p.name)) {
        CONTROL_RE.lastIndex = 0
        errors.push(where + ' has an invalid name.')
        return null
    }
    CONTROL_RE.lastIndex = 0
    if (typeof p.color !== 'string' || !COLOR_RE.test(p.color)) { errors.push(where + ' has an invalid color.'); return null }
    if (!parseAt(p.createdAt)) { errors.push(where + ' has an invalid createdAt.'); return null }
    seenIds[p.id] = true
    return { id: p.id, name: p.name, color: p.color.toLowerCase(), createdAt: p.createdAt }
}

function validStoredReading(r, profileIds, seenIds, errors, index) {
    var where = 'readings[' + index + ']'
    if (!isPlainObject(r)) { errors.push(where + ' is not an object.'); return null }
    if (typeof r.id !== 'string' || !READING_ID_RE.test(r.id)) { errors.push(where + ' has an invalid id.'); return null }
    if (seenIds[r.id]) { errors.push(where + ' repeats id ' + r.id + '.'); return null }
    if (typeof r.profileId !== 'string' || !profileIds[r.profileId]) { errors.push(where + ' references an unknown profile.'); return null }
    if (!parseAt(r.at)) { errors.push(where + ' has an invalid timestamp.'); return null }
    var sys = strictInt(r.sys, LIMITS.sys.min, LIMITS.sys.max)
    var dia = strictInt(r.dia, LIMITS.dia.min, LIMITS.dia.max)
    var pulse = strictInt(r.pulse, LIMITS.pulse.min, LIMITS.pulse.max)
    if (sys === null || dia === null || pulse === null) { errors.push(where + ' has values out of bounds.'); return null }
    var feeling = (r.feeling === undefined) ? '' : r.feeling
    var body = (r.body === undefined) ? '' : r.body
    var arm = (r.arm === undefined) ? '' : r.arm
    if (FEELINGS.indexOf(feeling) < 0 || BODIES.indexOf(body) < 0 || ARMS.indexOf(arm) < 0) {
        errors.push(where + ' has an unknown option value.')
        return null
    }
    var note = (r.note === undefined) ? '' : r.note
    if (typeof note !== 'string' || note.length > LIMITS.noteMax || CONTROL_RE.test(note)) {
        CONTROL_RE.lastIndex = 0
        errors.push(where + ' has an invalid note.')
        return null
    }
    CONTROL_RE.lastIndex = 0
    seenIds[r.id] = true
    return { id: r.id, profileId: r.profileId, at: r.at, sys: sys, dia: dia, pulse: pulse, feeling: feeling, body: body, arm: arm, note: note }
}

// Validates a loaded state document. Unknown keys are dropped; anything else
// that does not fit the schema makes the whole document invalid.
function validateState(obj) {
    var errors = []
    if (!isPlainObject(obj)) return { ok: false, state: null, errors: ['State is not an object.'] }
    if (obj.version !== SCHEMA_VERSION) errors.push('Unsupported state version.')
    if (!Array.isArray(obj.profiles)) errors.push('profiles must be an array.')
    else if (obj.profiles.length > LIMITS.profiles) errors.push('Too many profiles (max ' + LIMITS.profiles + ').')
    if (!Array.isArray(obj.readings)) errors.push('readings must be an array.')
    else if (obj.readings.length > LIMITS.readings) errors.push('Too many readings (max ' + LIMITS.readings + ').')
    if (errors.length) return { ok: false, state: null, errors: errors }

    var profiles = []
    var profileIds = {}
    var i
    for (i = 0; i < obj.profiles.length && errors.length < LIMITS.errorsMax; i++) {
        var p = validProfile(obj.profiles[i], profileIds, errors, i)
        if (p) profiles.push(p)
    }
    var readings = []
    var readingIds = {}
    for (i = 0; i < obj.readings.length && errors.length < LIMITS.errorsMax; i++) {
        var r = validStoredReading(obj.readings[i], profileIds, readingIds, errors, i)
        if (r) readings.push(r)
    }
    var active = obj.activeProfile
    if (active !== null && active !== undefined && (typeof active !== 'string' || !profileIds[active])) {
        errors.push('activeProfile references an unknown profile.')
    }
    if (errors.length) return { ok: false, state: null, errors: errors }
    return {
        ok: true,
        errors: [],
        state: { version: SCHEMA_VERSION, activeProfile: active || null, profiles: profiles, readings: readings }
    }
}

// ------------------------------------------------------------------- sinks

// Text destined for a host-owned sink (tooltips, dialogs, section headers):
// no markup characters, no controls, no bidi overrides, bounded length.
function plain(s, max) {
    var str = (s === null || s === undefined) ? '' : String(s)
    str = str.replace(UNSAFE_RE, '')
    var cap = (typeof max === 'number' && max > 0) ? max : LIMITS.plainMax
    return str.length > cap ? str.slice(0, cap) : str
}

var CSV_HEADER = ['Date', 'Time', 'Systolic (mmHg)', 'Diastolic (mmHg)', 'Pulse (bpm)', 'Category', 'Feeling', 'Body', 'Arm', 'Note']

// Spreadsheets evaluate cells that start with = + - @; prefix them with a quote.
function csvCell(value) {
    var s = (value === null || value === undefined) ? '' : String(value)
    return CSV_FORMULA_RE.test(s) ? "'" + s : s
}

function csvRows(readings) {
    var rows = [CSV_HEADER.slice()]
    for (var i = 0; i < (readings || []).length; i++) {
        var r = readings[i]
        rows.push([
            formatDate(r.at), formatTime(r.at), r.sys, r.dia, r.pulse,
            category(categoryOf(r.sys, r.dia)).label,
            csvCell(r.feeling), csvCell(r.body), csvCell(r.arm), csvCell(r.note)
        ])
    }
    return rows
}

// ------------------------------------------------------------------- charts

// Points in time order plus one label per distinct calendar day (start of day).
function chartSeries(readings) {
    var points = []
    var labels = []
    var lastDay = null
    for (var i = 0; i < (readings || []).length; i++) {
        var r = readings[i]
        var d = parseAt(r.at)
        if (!d) continue
        points.push({ t: d.getTime(), sys: Number(r.sys), dia: Number(r.dia), pulse: Number(r.pulse) })
        var key = dayKey(r.at)
        if (key !== lastDay) {
            labels.push({ t: startOfDay(d).getTime(), label: formatShortDate(r.at) })
            lastDay = key
        }
    }
    return { points: points, labels: labels }
}

// Keeps at most `max` evenly spaced labels, always including the first.
function thinLabels(labels, max) {
    var n = (labels || []).length
    if (n <= max) return (labels || []).slice()
    var step = Math.ceil(n / max)
    var out = []
    for (var i = 0; i < n; i += step) out.push(labels[i])
    return out
}

function initialColor(index) {
    var i = Math.abs(Math.floor(Number(index) || 0)) % PALETTE.length
    return PALETTE[i]
}

function profileInitial(name) {
    var s = typeof name === 'string' ? name.trim() : ''
    return s.length ? s.charAt(0).toUpperCase() : '?'
}

// ---------------------------------------------------------------- UI helpers

// Most recent reading of one profile, or null.
function lastReading(readings, profileId) {
    var best = null
    var bestMs = -Infinity
    for (var i = 0; i < (readings || []).length; i++) {
        var r = readings[i]
        if (!r || r.profileId !== profileId) continue
        var t = parseAt(r.at)
        if (!t) continue
        if (t.getTime() >= bestMs) {
            best = r
            bestMs = t.getTime()
        }
    }
    return best
}

// "129/83", or '' when there is no reading.
function readingLine(r) {
    return r ? r.sys + '/' + r.dia : ''
}

// Evenly spaced subset of at most `max` items, keeping the first and last so
// a chart always spans the full range. Bounds the work a Canvas repaint does.
function downsample(items, max) {
    var list = items || []
    var n = list.length
    var cap = Math.max(1, Math.floor(Number(max) || 1))
    if (n <= cap) return list.slice()
    if (cap === 1) return [list[n - 1]]
    var out = []
    var step = (n - 1) / (cap - 1)
    var last = -1
    for (var i = 0; i < cap; i++) {
        var idx = Math.round(i * step)
        if (idx > last) {
            out.push(list[idx])
            last = idx
        }
    }
    return out
}

// Splits a stored timestamp into the form's date and time fields.
function splitAt(at) {
    if (!parseAt(at)) return { date: '', time: '' }
    return { date: at.slice(0, 10), time: at.slice(11, 16) }
}

// Joins form fields (YYYY-MM-DD, H:MM or HH:MM) into a timestamp, or null.
function joinAt(date, time) {
    if (typeof date !== 'string' || typeof time !== 'string') return null
    var d = date.trim()
    var t = time.trim()
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return null
    var m = /^(\d{1,2}):(\d{2})$/.exec(t)
    if (!m) return null
    var at = d + 'T' + pad2(Number(m[1])) + ':' + m[2]
    return parseAt(at) ? at : null
}

var EXPORT_PATH_MAX = 4096
var EXPORT_PATH_RE = /^\/[^\u0000-\u001f\u007f]*\/Tensio\/Tensio-[^\/\u0000-\u001f\u007f]*\.(pdf|csv)$/

// True only for an absolute path shaped like the helper's export output:
// <documents>/Tensio/Tensio-<slug>-<stamp>[-n].pdf|csv, no controls, no
// relative segments. Guards the path before it reaches xdg-open.
function isExportPath(path) {
    if (typeof path !== 'string' || path.length > EXPORT_PATH_MAX) return false
    if (!EXPORT_PATH_RE.test(path)) return false
    var parts = path.split('/')
    for (var i = 1; i < parts.length; i++) {
        if (parts[i] === '' || parts[i] === '.' || parts[i] === '..') return false
    }
    return true
}

// Directory holding a validated export, or '' when the path is not one.
function exportFolder(path) {
    if (!isExportPath(path)) return ''
    return path.slice(0, path.lastIndexOf('/'))
}

// ------------------------------------------------------------ keyboard
//
// keyAction() maps one key press to an action name for the panel. It is a
// pure table so the keymap is unit-tested; Panel.qml computes the context
// (the topmost open layer), normalizes the Qt event and dispatches the
// returned action. '' means "not handled": the event then stays with the
// focused control (SpinBox arrows, dropdown popups, text editing).
//
// context:     records | analysis | report | profileMenu | form | info |
//              help | confirm | nameEditor | onboarding
// key:         normalized key name ('Left', 'Return', 'Escape', 'Tab', ...)
//              or '' for a printable key, which is then read from `text`
// modifiers:   { ctrl, shift, alt }
// textFocused: a text input has focus; only Escape, Tab / Shift+Tab,
//              Return / Enter, Ctrl+Enter, Ctrl+S (and PageUp / PageDown in
//              the reading form) are mapped, so typing is never stolen.

var PAGE_CONTEXTS = ['records', 'analysis', 'report']

var PAGE_TEXT = {
    '1': 'tab1', '2': 'tab2', '3': 'tab3',
    'n': 'newReading', '+': 'newReading',
    'p': 'profileMenu', '[': 'profilePrev', ']': 'profileNext',
    'i': 'info', '?': 'help'
}
var PAGE_KEYS = { 'Left': 'tabPrev', 'Right': 'tabNext' }
var RANGE_TEXT = { 'w': 'range7d', 'm': 'range30d', 'a': 'rangeAll' }
var SCROLL_TEXT = { 'j': 'scrollDown', 'k': 'scrollUp' }
var SCROLL_KEYS = { 'Down': 'scrollDown', 'Up': 'scrollUp', 'PageDown': 'pageDown', 'PageUp': 'pageUp' }

var CONTEXT_TEXT = {
    records: { 'j': 'selectNext', 'k': 'selectPrev', 'g': 'selectFirst', 'G': 'selectLast', 'e': 'editSelected', 'x': 'deleteSelected' },
    analysis: SCROLL_TEXT,
    report: { 'e': 'exportPdf', 'c': 'exportCsv', 'o': 'openExport', 'f': 'openFolder' },
    info: { 'j': 'scrollDown', 'k': 'scrollUp', 'i': 'info', '?': 'help' },
    help: { 'j': 'scrollDown', 'k': 'scrollUp', '?': 'help' },
    profileMenu: { 'j': 'menuNext', 'k': 'menuPrev', 'a': 'profileAdd', 'r': 'profileRename', 'd': 'profileDelete', 'p': 'profileMenu' },
    confirm: { 'y': 'confirmYes', 'n': 'confirmNo' }
}
var CONTEXT_KEYS = {
    records: {
        'Down': 'selectNext', 'Up': 'selectPrev', 'Home': 'selectFirst', 'End': 'selectLast',
        'PageUp': 'selectPageUp', 'PageDown': 'selectPageDown',
        'Return': 'editSelected', 'Enter': 'editSelected', 'Delete': 'deleteSelected'
    },
    analysis: SCROLL_KEYS,
    info: SCROLL_KEYS,
    help: SCROLL_KEYS,
    profileMenu: { 'Down': 'menuNext', 'Up': 'menuPrev', 'Return': 'menuActivate', 'Enter': 'menuActivate' },
    form: { 'Return': 'formSave', 'Enter': 'formSave', 'PageUp': 'formPageUp', 'PageDown': 'formPageDown' },
    confirm: {
        'Return': 'confirmActivate', 'Enter': 'confirmActivate',
        'Left': 'confirmToggle', 'Right': 'confirmToggle', 'Tab': 'confirmToggle', 'Backtab': 'confirmToggle'
    },
    nameEditor: { 'Return': 'nameSave', 'Enter': 'nameSave' },
    onboarding: { 'Return': 'onboardingSave', 'Enter': 'onboardingSave' }
}
var SAVE_ACTIONS = { form: 'formSave', nameEditor: 'nameSave', onboarding: 'onboardingSave' }

function lookup(table, name) {
    return table && Object.prototype.hasOwnProperty.call(table, name) ? table[name] : ''
}

function keyAction(context, key, text, modifiers, textFocused) {
    var ctx = typeof context === 'string' ? context : ''
    var k = typeof key === 'string' ? key : ''
    var t = typeof text === 'string' && text.length === 1 ? text : ''
    var mods = modifiers && typeof modifiers === 'object' ? modifiers : {}
    var focused = textFocused === true

    if (k === 'Escape') return ctx === 'confirm' ? 'confirmNo' : 'escape'

    // Save chords work from any field of an editor.
    var save = lookup(SAVE_ACTIONS, ctx)
    if (mods.ctrl && !mods.alt) {
        if (save !== '' && (k === 'Return' || k === 'Enter' || (k === '' && (t === 's' || t === 'S')))) return save
        return ''
    }
    if (mods.alt || mods.ctrl) return ''

    if (k === 'Tab' || k === 'Backtab') {
        if (ctx === 'form') return k === 'Backtab' || mods.shift ? 'formPrev' : 'formNext'
        if (ctx === 'confirm') return 'confirmToggle'
        return ''
    }

    if (focused) {
        if (k === 'Return' || k === 'Enter') return save
        if (ctx === 'form' && (k === 'PageUp' || k === 'PageDown')) return lookup(CONTEXT_KEYS.form, k)
        return ''
    }

    if (k !== '') {
        var byKey = lookup(CONTEXT_KEYS[ctx], k)
        if (byKey !== '') return byKey
        return PAGE_CONTEXTS.indexOf(ctx) >= 0 ? lookup(PAGE_KEYS, k) : ''
    }
    if (t === '') return ''

    var byText = lookup(CONTEXT_TEXT[ctx], t)
    if (byText !== '') return byText
    if (PAGE_CONTEXTS.indexOf(ctx) < 0) return ''
    if (ctx !== 'records') {
        var range = lookup(RANGE_TEXT, t)
        if (range !== '') return range
    }
    return lookup(PAGE_TEXT, t)
}

// Human-readable keymap, shared by the in-panel help overlay and the
// README (tests/test_model.cjs checks that every row appears there). Keys
// are space-separated tokens; '/' and 'or' are separators.
var SHORTCUTS = [
    { group: 'Global', keys: '1 2 3 or Left / Right', action: 'Switch between Records, Analysis and Reports' },
    { group: 'Global', keys: 'n or +', action: 'New reading' },
    { group: 'Global', keys: 'p', action: 'Open the profile menu' },
    { group: 'Global', keys: '[ / ]', action: 'Previous / next profile' },
    { group: 'Global', keys: 'i', action: 'Category information' },
    { group: 'Global', keys: '?', action: 'Show or hide this shortcut list' },
    { group: 'Global', keys: 'w / m / a', action: 'Range 7 days / 30 days / all (Analysis and Reports)' },
    { group: 'Global', keys: 'Esc', action: 'Close the topmost layer, otherwise the panel' },
    { group: 'Records', keys: 'j / k or Down / Up', action: 'Select the next / previous reading' },
    { group: 'Records', keys: 'g / G or Home / End', action: 'Select the first / last reading' },
    { group: 'Records', keys: 'PageUp / PageDown', action: 'Move the selection by a page' },
    { group: 'Records', keys: 'Enter or e', action: 'Edit the selected reading' },
    { group: 'Records', keys: 'x or Delete', action: 'Delete the selected reading (asks first)' },
    { group: 'Analysis, info and help', keys: 'j / k or Down / Up', action: 'Scroll' },
    { group: 'Analysis, info and help', keys: 'PageUp / PageDown', action: 'Scroll by a page' },
    { group: 'Reports', keys: 'e', action: 'Export PDF' },
    { group: 'Reports', keys: 'c', action: 'Export CSV' },
    { group: 'Reports', keys: 'o', action: 'Open the last export' },
    { group: 'Reports', keys: 'f', action: 'Open the folder of the last export' },
    { group: 'Profile menu', keys: 'j / k or Down / Up', action: 'Move through the menu' },
    { group: 'Profile menu', keys: 'Enter', action: 'Select the highlighted profile or action' },
    { group: 'Profile menu', keys: 'a / r / d', action: 'Add / rename / delete profile' },
    { group: 'Profile menu', keys: 'p or Esc', action: 'Close the menu' },
    { group: 'Reading form', keys: 'Tab / Shift+Tab', action: 'Next / previous field' },
    { group: 'Reading form', keys: 'Up / Down or PageUp / PageDown', action: 'Adjust SYS, DIA or pulse by 1 / 10' },
    { group: 'Reading form', keys: 'Space or Enter', action: 'Open a dropdown or press the focused button' },
    { group: 'Reading form', keys: 'Ctrl+Enter or Ctrl+S', action: 'Save from any field' },
    { group: 'Reading form', keys: 'Esc', action: 'Cancel' },
    { group: 'Dialogs', keys: 'Enter or y', action: 'Confirm (Left / Right picks the button Enter presses)' },
    { group: 'Dialogs', keys: 'Esc or n', action: 'Cancel a confirmation' },
    { group: 'Dialogs', keys: 'Enter / Esc', action: 'Save / cancel a profile name' }
]

function shortcutHelp() {
    var out = []
    for (var i = 0; i < SHORTCUTS.length; i++)
        out.push({ group: SHORTCUTS[i].group, keys: SHORTCUTS[i].keys, action: SHORTCUTS[i].action })
    return out
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        SCHEMA_VERSION: SCHEMA_VERSION, LIMITS: LIMITS, FEELINGS: FEELINGS, BODIES: BODIES, ARMS: ARMS, RANGES: RANGES,
        CATEGORIES: CATEGORIES, SEVERE_WARNING: SEVERE_WARNING, PALETTE: PALETTE, CSV_HEADER: CSV_HEADER,
        categoryOf: categoryOf, category: category,
        parseAt: parseAt, toAt: toAt, startOfDay: startOfDay, addDays: addDays, rangeStart: rangeStart,
        filterReadings: filterReadings, averages: averages, distribution: distribution, groupByDay: groupByDay,
        formatTime: formatTime, formatDate: formatDate, formatShortDate: formatShortDate, formatDateTime: formatDateTime,
        newId: newId, validateReading: validateReading, validateProfileName: validateProfileName,
        emptyState: emptyState, validateState: validateState,
        plain: plain, csvRows: csvRows, chartSeries: chartSeries, thinLabels: thinLabels,
        initialColor: initialColor, profileInitial: profileInitial,
        lastReading: lastReading, readingLine: readingLine, downsample: downsample,
        splitAt: splitAt, joinAt: joinAt, isExportPath: isExportPath, exportFolder: exportFolder,
        keyAction: keyAction, SHORTCUTS: SHORTCUTS, shortcutHelp: shortcutHelp
    }
}
