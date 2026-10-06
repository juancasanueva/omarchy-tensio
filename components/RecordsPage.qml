import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Readings of the active profile grouped by day, newest first. The list is
// capped at maxRows readings so the delegate count stays bounded.
Item {
    id: page

    property var readings: []
    property int maxRows: 200
    property bool canEdit: true

    signal addRequested()
    signal editRequested(var reading)
    signal deleteRequested(var reading)

    // Flat model of day headers and reading rows, at most maxRows readings.
    readonly property var entries: {
        var groups = Model.groupByDay(page.readings, new Date())
        var out = []
        var rows = 0
        for (var g = 0; g < groups.length && rows < page.maxRows; g++) {
            out.push({ header: true, label: groups[g].label, reading: null })
            for (var i = 0; i < groups[g].readings.length && rows < page.maxRows; i++) {
                out.push({ header: false, label: '', reading: groups[g].readings[i] })
                rows += 1
            }
        }
        return out
    }
    readonly property bool truncated: page.readings.length > page.maxRows

    PlainLabel {
        anchors.centerIn: parent
        visible: page.readings.length === 0
        width: parent.width - Style.space(40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        text: 'No readings yet. Use + to add the first one.'
        color: Util.alpha(Color.popups.text, 0.6)
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.rightMargin: Style.space(10)
        clip: true
        spacing: Style.space(6)
        boundsBehavior: Flickable.StopAtBounds
        model: page.entries
        visible: page.readings.length > 0
        QQC.ScrollBar.vertical: vbar

        footer: Item {
            width: list.width
            height: page.truncated ? Style.space(70) : Style.space(60)
            PlainLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(8)
                visible: page.truncated
                text: 'Showing the ' + page.maxRows + ' most recent of ' + page.readings.length + ' readings. Export a CSV for the full log.'
                color: Util.alpha(Color.popups.text, 0.6)
                font.pixelSize: Style.font.caption
            }
        }

        delegate: Item {
            id: entry
            required property var modelData
            width: list.width
            height: modelData.header ? dayLabel.implicitHeight + Style.space(8) : rowCard.implicitHeight

            PlainLabel {
                id: dayLabel
                visible: entry.modelData.header
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(2)
                text: entry.modelData.label
                font.pixelSize: Style.font.subtitle
                font.bold: true
            }

            ReadingRow {
                id: rowCard
                visible: !entry.modelData.header
                width: parent.width
                reading: entry.modelData.reading
                onEditRequested: if (page.canEdit) page.editRequested(entry.modelData.reading)
                onDeleteRequested: if (page.canEdit) page.deleteRequested(entry.modelData.reading)
            }
        }
    }

    // Sibling of the flickable so it can sit at the page edge.
    QQC.ScrollBar {
        id: vbar
        anchors.top: page.top
        anchors.bottom: page.bottom
        anchors.right: page.right
        policy: QQC.ScrollBar.AsNeeded
    }

    // Floating add button.
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(14)
        width: Style.space(44)
        height: width
        radius: width / 2
        visible: page.canEdit
        color: addArea.containsMouse ? Qt.lighter(Color.accent, 1.15) : Color.accent

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: '+'
            color: Color.popups.background
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.bold: true
        }

        MouseArea {
            id: addArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.addRequested()
        }
    }
}
