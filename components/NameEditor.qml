import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Inline profile-name editor: label, text field, Save and Cancel.
Item {
    id: editor

    property string title: 'Profile name'
    property string initialText: ''
    property string confirmText: 'Save'
    property bool showCancel: true
    property string errorText: ''

    signal submitted(string name)
    signal canceled()

    implicitHeight: column.implicitHeight

    function focusField() { field.forceActiveFocus() }
    function reset(text) {
        field.text = text || ''
        editor.errorText = ''
    }

    function submit() {
        var result = Model.validateProfileName(field.text)
        if (!result.ok) {
            editor.errorText = result.errors.join(' ')
            return
        }
        editor.errorText = ''
        editor.submitted(result.value)
    }

    Column {
        id: column
        width: parent.width
        spacing: Style.space(6)

        PlainLabel {
            text: editor.title
            color: Util.alpha(Color.popups.text, 0.6)
            font.pixelSize: Style.font.caption
            font.bold: true
        }

        Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
                id: field
                width: parent.width - saveButton.width - (cancelButton.visible ? cancelButton.width + parent.spacing : 0) - parent.spacing
                text: editor.initialText
                maximumLength: Model.LIMITS.nameMax
                placeholderText: 'Name'
                foreground: Color.popups.text
                onAccepted: editor.submit()
            }
            Button {
                id: cancelButton
                visible: editor.showCancel
                text: 'Cancel'
                bordered: true
                foreground: Color.popups.text
                anchors.verticalCenter: field.verticalCenter
                onClicked: editor.canceled()
            }
            Button {
                id: saveButton
                text: editor.confirmText
                bordered: true
                selected: true
                foreground: Color.popups.text
                anchors.verticalCenter: field.verticalCenter
                onClicked: editor.submit()
            }
        }

        PlainLabel {
            width: parent.width
            visible: editor.errorText !== ''
            text: editor.errorText
            color: Color.urgent
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
    }
}
