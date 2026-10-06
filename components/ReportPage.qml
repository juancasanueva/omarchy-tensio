import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Summary of the selected range and PDF / CSV export through the helper.
// The page only displays results; Panel.qml runs the helper and validates
// the returned path before it is offered to Open / Open folder.
Item {
    id: page

    property var profile: null
    property var readings: []
    property string rangeKey: '7d'
    property bool busy: false
    property string exportPath: ''
    property string exportError: ''
    property bool canExport: true

    signal rangeSelected(string key)
    signal exportRequested(string format)
    signal openRequested(string path)
    signal openFolderRequested(string path)

    readonly property var avg: Model.averages(readings)
    readonly property color muted: Util.alpha(Color.popups.text, 0.6)
    readonly property string rangeTitle: rangeKey === '7d' ? 'Last 7 days' : (rangeKey === '30d' ? 'Last 30 days' : 'All readings')
    readonly property string span: readings.length
        ? Model.formatDate(readings[0].at) + ' – ' + Model.formatDate(readings[readings.length - 1].at)
        : '—'

    Column {
        width: parent.width
        spacing: Style.space(12)

        RangeSelector {
            anchors.horizontalCenter: parent.horizontalCenter
            rangeKey: page.rangeKey
            onRangeSelected: function (key) { page.rangeSelected(key) }
        }

        Card {
            width: parent.width
            height: summary.implicitHeight + Style.space(24)

            Column {
                id: summary
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(6)

                PlainLabel { text: 'Report summary'; font.pixelSize: Style.font.subtitle; font.bold: true }

                Grid {
                    columns: 2
                    columnSpacing: Style.space(16)
                    rowSpacing: Style.space(4)

                    PlainLabel { text: 'Profile'; color: page.muted }
                    PlainLabel { text: page.profile ? page.profile.name : '—'; width: summary.width - Style.space(120) }
                    PlainLabel { text: 'Range'; color: page.muted }
                    PlainLabel { text: page.rangeTitle }
                    PlainLabel { text: 'Dates'; color: page.muted }
                    PlainLabel { text: page.span }
                    PlainLabel { text: 'Readings'; color: page.muted }
                    PlainLabel { text: String(page.readings.length) }
                    PlainLabel { text: 'Averages'; color: page.muted }
                    PlainLabel {
                        text: page.avg.count ? page.avg.sys + '/' + page.avg.dia + ' mmHg · ♥ ' + page.avg.pulse + ' bpm' : '—'
                        color: page.avg.count ? Model.category(Model.categoryOf(page.avg.sys, page.avg.dia)).color : Color.popups.text
                    }
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(10)
            Button {
                text: 'Export PDF'
                bordered: true
                foreground: Color.popups.text
                opacity: page.busy || !page.canExport ? 0.5 : 1
                onClicked: if (!page.busy && page.canExport) page.exportRequested('pdf')
            }
            Button {
                text: 'Export CSV'
                bordered: true
                foreground: Color.popups.text
                opacity: page.busy || !page.canExport ? 0.5 : 1
                onClicked: if (!page.busy && page.canExport) page.exportRequested('csv')
            }
        }

        PlainLabel {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: page.busy
            text: 'Exporting…'
            color: page.muted
        }

        Card {
            width: parent.width
            visible: !page.busy && page.exportPath !== ''
            height: savedColumn.implicitHeight + Style.space(24)

            Column {
                id: savedColumn
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(8)

                PlainLabel { text: 'Saved to'; color: page.muted; font.pixelSize: Style.font.caption }
                PlainLabel {
                    width: parent.width
                    text: page.exportPath
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideNone
                    maximumLineCount: 3
                }
                Row {
                    spacing: Style.space(8)
                    Button {
                        text: 'Open'
                        bordered: true
                        foreground: Color.popups.text
                        onClicked: page.openRequested(page.exportPath)
                    }
                    Button {
                        text: 'Open folder'
                        bordered: true
                        foreground: Color.popups.text
                        onClicked: page.openFolderRequested(page.exportPath)
                    }
                }
            }
        }

        PlainLabel {
            width: parent.width
            visible: !page.busy && page.exportError !== ''
            text: page.exportError
            color: Color.urgent
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            maximumLineCount: 4
        }

        PlainLabel {
            width: parent.width
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            text: 'Reports are saved in the Tensio folder of your Documents directory.'
            color: page.muted
            font.pixelSize: Style.font.caption
        }
    }
}
