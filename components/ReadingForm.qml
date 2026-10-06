import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Add / edit form for one reading. Created fresh by a Loader for every use,
// so initial values come from `reading` (null for a new reading). Return,
// Ctrl+Enter and Ctrl+S reach Panel.qml's key handler, which calls submit();
// the fields do not submit on `accepted` themselves, so a save never runs
// twice for one key press.
Item {
    id: form

    property var reading: null
    property string profileId: ''
    readonly property bool editing: reading !== null

    property int sys: reading ? reading.sys : 120
    property int dia: reading ? reading.dia : 80
    property int pulse: reading ? reading.pulse : 70
    property string feeling: reading ? reading.feeling : ''
    property string body: reading ? reading.body : ''
    property string arm: reading ? reading.arm : ''
    property string errorText: ''

    readonly property var initialAt: Model.splitAt(reading ? reading.at : Model.toAt(new Date()))
    readonly property string categoryKey: Model.categoryOf(sys, dia)
    readonly property var category: Model.category(categoryKey)
    readonly property real gap: Style.space(12)
    readonly property real third: (width - 2 * gap) / 3
    readonly property color muted: Util.alpha(Color.popups.text, 0.6)

    signal saved(var value)
    signal canceled()

    implicitHeight: column.implicitHeight

    function optionsFor(list) {
        var out = []
        for (var i = 0; i < list.length; i++)
            out.push({ value: list[i], label: list[i] === '' ? '—' : Model.plain(list[i], 40) })
        return out
    }

    // Text currently typed into a NumberField, even if not yet committed.
    function typedValue(numberField, fallback) {
        var input = numberField.field.contentItem
        var text = input && input.text !== undefined ? String(input.text).trim() : ''
        return text !== '' ? text : fallback
    }

    // ----------------------------------------------------------- keyboard
    //
    // Focus order: SYS, DIA, PULSE, Feeling, Body, Arm, Date, Time, Note,
    // Cancel, Save. It matches the item order, so Qt's own Tab chain (used
    // when a control handles Tab itself) walks the same sequence.

    // The focusable trigger inside a host Dropdown.
    function focusableIn(item) {
        var kids = item ? item.children : []
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].activeFocusOnTab) return kids[i]
            var inner = form.focusableIn(kids[i])
            if (inner) return inner
        }
        return null
    }

    function focusTargets() {
        return [sysField.field, diaField.field, pulseField.field,
            form.focusableIn(feelingDrop), form.focusableIn(bodyDrop), form.focusableIn(armDrop),
            dateField, timeField, noteField, cancelButton, saveButton]
    }

    function focusedIndex() {
        var targets = form.focusTargets()
        for (var i = 0; i < targets.length; i++)
            if (targets[i] && targets[i].activeFocus) return i
        return -1
    }

    function focusAt(index) {
        var target = form.focusTargets()[index]
        if (target) target.forceActiveFocus(Qt.TabFocusReason)
    }

    function focusFirst() { form.focusAt(0) }

    function focusNext(step) {
        var count = form.focusTargets().length
        var current = form.focusedIndex()
        var next = current < 0 ? (step > 0 ? 0 : count - 1) : (current + step + count) % count
        form.focusAt(next)
    }

    // The control that has keyboard focus, for the focus ring. Reading each
    // target's activeFocus here makes the binding follow focus changes.
    readonly property Item ringTarget: {
        var targets = form.focusTargets()
        for (var i = 0; i < targets.length; i++)
            if (targets[i] && targets[i].activeFocus) return targets[i]
        return null
    }

    // PageUp / PageDown on a number field: adjust by delta, clamped.
    // Returns false when no number field has focus.
    function stepFocused(delta) {
        var index = form.focusedIndex()
        var fields = [sysField, diaField, pulseField]
        var names = ['sys', 'dia', 'pulse']
        if (index < 0 || index > 2) return false
        var numberField = fields[index]
        var base = parseInt(form.typedValue(numberField, form[names[index]]), 10)
        if (!isFinite(base)) base = numberField.field.value
        var next = Math.max(numberField.from, Math.min(numberField.to, base + delta))
        form[names[index]] = next
        numberField.field.value = next
        var input = numberField.field.contentItem
        if (input && input.selectAll) input.selectAll()
        return true
    }

    // Typing replaces a number or date when a field is entered by keyboard.
    function selectOnFocus(input) {
        if (input && input.activeFocus && input.selectAll) input.selectAll()
    }

    Connections {
        target: sysField.field.contentItem
        function onActiveFocusChanged() { form.selectOnFocus(sysField.field.contentItem) }
    }
    Connections {
        target: diaField.field.contentItem
        function onActiveFocusChanged() { form.selectOnFocus(diaField.field.contentItem) }
    }
    Connections {
        target: pulseField.field.contentItem
        function onActiveFocusChanged() { form.selectOnFocus(pulseField.field.contentItem) }
    }

    function submit() {
        var at = Model.joinAt(dateField.text, timeField.text)
        if (!at) {
            form.errorText = 'Enter the date as YYYY-MM-DD and the time as HH:MM.'
            return
        }
        var result = Model.validateReading({
            id: form.reading ? form.reading.id : undefined,
            profileId: form.profileId,
            at: at,
            sys: form.typedValue(sysField, form.sys),
            dia: form.typedValue(diaField, form.dia),
            pulse: form.typedValue(pulseField, form.pulse),
            feeling: form.feeling,
            body: form.body,
            arm: form.arm,
            note: noteField.text
        })
        if (!result.ok) {
            form.errorText = result.errors.join(' ')
            return
        }
        form.errorText = ''
        form.saved(result.value)
    }

    Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Row {
            width: parent.width
            spacing: Style.space(8)
            PlainLabel {
                text: form.editing ? 'Edit reading' : 'New reading'
                color: form.muted
                font.pixelSize: Style.font.subtitle
                anchors.verticalCenter: parent.verticalCenter
            }
            PlainLabel {
                text: form.category.longLabel
                color: form.category.color
                font.pixelSize: Style.font.heading
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        CategoryBar {
            width: parent.width
            categoryKey: form.categoryKey
        }

        Row {
            spacing: form.gap
            NumberField {
                id: sysField
                label: 'SYS (mmHg)'
                fieldWidth: form.third
                from: Model.LIMITS.sys.min
                to: Model.LIMITS.sys.max
                value: form.sys
                foreground: Color.popups.text
                onModified: function (v) { form.sys = v }
            }
            NumberField {
                id: diaField
                label: 'DIA (mmHg)'
                fieldWidth: form.third
                from: Model.LIMITS.dia.min
                to: Model.LIMITS.dia.max
                value: form.dia
                foreground: Color.popups.text
                onModified: function (v) { form.dia = v }
            }
            NumberField {
                id: pulseField
                label: 'PULSE (BPM)'
                fieldWidth: form.third
                from: Model.LIMITS.pulse.min
                to: Model.LIMITS.pulse.max
                value: form.pulse
                foreground: Color.popups.text
                onModified: function (v) { form.pulse = v }
            }
        }

        Row {
            spacing: form.gap
            Dropdown {
                id: feelingDrop
                width: form.third
                label: 'Feeling'
                options: form.optionsFor(Model.FEELINGS)
                value: form.feeling
                onChanged: function (v) { form.feeling = v }
            }
            Dropdown {
                id: bodyDrop
                width: form.third
                label: 'Body'
                options: form.optionsFor(Model.BODIES)
                value: form.body
                onChanged: function (v) { form.body = v }
            }
            Dropdown {
                id: armDrop
                width: form.third
                label: 'Arm'
                options: form.optionsFor(Model.ARMS)
                value: form.arm
                onChanged: function (v) { form.arm = v }
            }
        }

        Row {
            spacing: form.gap
            Column {
                spacing: Style.spacing.labelGap
                PlainLabel { text: 'Date (YYYY-MM-DD)'; color: form.muted; font.pixelSize: Style.font.caption; font.bold: true }
                TextField {
                    id: dateField
                    width: form.third
                    text: form.initialAt.date
                    maximumLength: 10
                    placeholderText: 'YYYY-MM-DD'
                    foreground: Color.popups.text
                    validator: RegularExpressionValidator { regularExpression: /[0-9-]{0,10}/ }
                    onActiveFocusChanged: form.selectOnFocus(dateField)
                }
            }
            Column {
                spacing: Style.spacing.labelGap
                PlainLabel { text: 'Time (HH:MM)'; color: form.muted; font.pixelSize: Style.font.caption; font.bold: true }
                TextField {
                    id: timeField
                    width: form.third
                    text: form.initialAt.time
                    maximumLength: 5
                    placeholderText: 'HH:MM'
                    foreground: Color.popups.text
                    validator: RegularExpressionValidator { regularExpression: /[0-9:]{0,5}/ }
                    onActiveFocusChanged: form.selectOnFocus(timeField)
                }
            }
        }

        Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            PlainLabel { text: 'Note'; color: form.muted; font.pixelSize: Style.font.caption; font.bold: true }
            TextField {
                id: noteField
                width: parent.width
                text: form.reading ? form.reading.note : ''
                maximumLength: Model.LIMITS.noteMax
                placeholderText: 'Optional, up to ' + Model.LIMITS.noteMax + ' characters'
                foreground: Color.popups.text
            }
        }

        PlainLabel {
            width: parent.width
            visible: form.errorText !== ''
            text: form.errorText
            color: Color.urgent
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }

        Row {
            anchors.right: parent.right
            spacing: Style.space(8)
            Button {
                id: cancelButton
                text: 'Cancel'
                focusable: true
                bordered: true
                foreground: Color.popups.text
                onClicked: form.canceled()
            }
            Button {
                id: saveButton
                text: form.editing ? 'Save changes' : 'Save'
                focusable: true
                bordered: true
                selected: true
                foreground: Color.popups.text
                onClicked: form.submit()
            }
        }
    }

    // Accent ring around the focused control, so keyboard focus is always
    // visible whatever the theme's own focus styling is.
    Rectangle {
        id: focusRing
        readonly property real pad: 3
        readonly property point origin: form.ringTarget && form.width > 0
            ? form.ringTarget.mapToItem(form, 0, 0) : Qt.point(0, 0)
        visible: form.ringTarget !== null
        enabled: false
        z: 50
        x: origin.x - pad
        y: origin.y - pad
        width: form.ringTarget ? form.ringTarget.width + pad * 2 : 0
        height: form.ringTarget ? form.ringTarget.height + pad * 2 : 0
        radius: Style.cornerRadius + pad
        color: 'transparent'
        border.width: 2
        border.color: Color.accent
    }
}
