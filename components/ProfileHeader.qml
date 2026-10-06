import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Avatar, profile name with a menu chevron, last reading, and the button
// that opens the category information view.
Item {
    id: header

    property var profile: null
    property var lastReading: null
    property bool menuOpen: false

    signal menuRequested()
    signal infoRequested()

    readonly property color muted: Util.alpha(Color.popups.text, 0.6)

    implicitHeight: Math.max(avatar.height, nameColumn.implicitHeight)

    Rectangle {
        id: avatar
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        height: width
        radius: width / 2
        color: header.profile ? header.profile.color : Color.accent

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: header.profile ? Model.profileInitial(header.profile.name) : '?'
            color: '#ffffff'
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
        }
    }

    Column {
        id: nameColumn
        anchors.left: avatar.right
        anchors.leftMargin: Style.space(10)
        anchors.right: infoButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Rectangle {
            width: nameRow.implicitWidth + Style.space(10)
            height: nameRow.implicitHeight + Style.space(4)
            radius: Style.space(6)
            color: nameArea.containsMouse || header.menuOpen ? Util.alpha(Color.popups.text, 0.08) : 'transparent'

            Row {
                id: nameRow
                anchors.verticalCenter: parent.verticalCenter
                x: Style.space(5)
                spacing: Style.space(6)
                PlainLabel {
                    text: header.profile ? header.profile.name : 'Tensio'
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    width: Math.min(implicitWidth, nameColumn.width - Style.space(40))
                }
                PlainLabel {
                    text: '▾'
                    color: header.muted
                    font.pixelSize: Style.font.heading
                }
            }

            MouseArea {
                id: nameArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: header.menuRequested()
            }
        }

        PlainLabel {
            x: Style.space(5)
            text: header.lastReading ? 'Last: ' + Model.readingLine(header.lastReading) + ' mmHg' : 'No readings yet'
            color: header.muted
            font.pixelSize: Style.font.bodySmall
        }
    }

    Button {
        id: infoButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: 'ⓘ'
        fontSize: Style.font.heading
        foreground: Color.popups.text
        tooltipText: 'Blood pressure categories'
        onClicked: header.infoRequested()
    }
}
