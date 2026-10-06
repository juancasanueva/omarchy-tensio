import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Add / edit form for one reading. Created fresh by a Loader for every use,
// so initial values come from `reading` (null for a new reading).
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
                width: form.third
                label: 'Feeling'
                options: form.optionsFor(Model.FEELINGS)
                value: form.feeling
                onChanged: function (v) { form.feeling = v }
            }
            Dropdown {
                width: form.third
                label: 'Body'
                options: form.optionsFor(Model.BODIES)
                value: form.body
                onChanged: function (v) { form.body = v }
            }
            Dropdown {
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
                    onAccepted: form.submit()
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
                    onAccepted: form.submit()
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
                onAccepted: form.submit()
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
                text: 'Cancel'
                bordered: true
                foreground: Color.popups.text
                onClicked: form.canceled()
            }
            Button {
                text: form.editing ? 'Save changes' : 'Save'
                bordered: true
                selected: true
                foreground: Color.popups.text
                onClicked: form.submit()
            }
        }
    }
}
