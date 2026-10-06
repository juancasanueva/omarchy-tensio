import QtQuick
import qs.Commons
import "../Model.js" as Model

// Drop-down card listing the profiles (check on the active one) followed by
// Add, Rename and Delete actions. The list is bounded by Model.LIMITS.profiles.
Card {
    id: menu

    property var profiles: []
    property string activeId: ''
    property string activeName: ''
    property bool canEdit: true

    signal profileSelected(string id)
    signal addRequested()
    signal renameRequested()
    signal deleteRequested()

    readonly property var shownProfiles: (profiles || []).slice(0, Model.LIMITS.profiles)
    // Keyboard cursor: profile rows first, then Add, Rename, Delete.
    property int cursorIndex: -1
    readonly property int actionBase: shownProfiles.length
    readonly property int rowCount: shownProfiles.length + (activeId !== '' ? 3 : 1)

    color: Color.popups.background
    border.color: Util.alpha(Color.popups.text, 0.2)
    implicitWidth: Style.space(260)
    implicitHeight: menuColumn.implicitHeight + Style.space(12)

    // Swallow clicks that land between rows.
    MouseArea { anchors.fill: parent }

    component MenuRow: Rectangle {
        id: menuRow
        property string label: ''
        property string mark: ''
        property color textColor: Color.popups.text
        property bool enabledRow: true
        property bool highlighted: false
        signal activated()
        width: menuColumn.width
        height: Style.space(30)
        radius: Style.space(6)
        color: (rowArea.containsMouse && enabledRow) || highlighted ? Util.alpha(Color.popups.text, 0.08) : 'transparent'
        border.width: highlighted ? 1 : 0
        border.color: Color.accent
        opacity: enabledRow ? 1 : 0.45

        Text {
            textFormat: Text.PlainText
            id: markText
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            text: menuRow.mark
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
        Text {
            textFormat: Text.PlainText
            anchors.left: markText.right
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: menuRow.label
            color: menuRow.textColor
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: menuRow.enabledRow ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (menuRow.enabledRow) menuRow.activated()
        }
    }

    Column {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(6)
        spacing: Style.space(2)

        Repeater {
            model: menu.shownProfiles
            delegate: MenuRow {
                required property var modelData
                required property int index
                highlighted: menu.cursorIndex === index
                label: modelData.name
                mark: modelData.id === menu.activeId ? '✓' : ''
                onActivated: menu.profileSelected(modelData.id)
            }
        }

        Rectangle {
            visible: menu.shownProfiles.length > 0
            width: parent.width
            height: 1
            color: Util.alpha(Color.popups.text, 0.12)
        }

        MenuRow {
            label: 'Add profile'
            mark: '+'
            highlighted: menu.cursorIndex === menu.actionBase
            enabledRow: menu.canEdit && menu.shownProfiles.length < Model.LIMITS.profiles
            onActivated: menu.addRequested()
        }
        MenuRow {
            visible: menu.activeId !== ''
            label: 'Rename ' + menu.activeName
            highlighted: menu.cursorIndex === menu.actionBase + 1
            enabledRow: menu.canEdit
            onActivated: menu.renameRequested()
        }
        MenuRow {
            visible: menu.activeId !== ''
            label: 'Delete ' + menu.activeName
            highlighted: menu.cursorIndex === menu.actionBase + 2
            textColor: Color.urgent
            enabledRow: menu.canEdit
            onActivated: menu.deleteRequested()
        }
    }
}
