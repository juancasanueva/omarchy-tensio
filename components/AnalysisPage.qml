import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import "../Model.js" as Model

// Line chart, averages and category distribution for the selected range.
Item {
    id: page

    property var readings: []
    property string rangeKey: '7d'
    signal rangeSelected(string key)

    readonly property var filtered: page.readings
    readonly property var series: Model.chartSeries(filtered)
    readonly property var points: Model.downsample(series.points, 400)
    readonly property var labels: Model.thinLabels(series.labels, Math.max(2, Math.floor(chartCard.width / Style.space(70))))
    readonly property var avg: Model.averages(filtered)
    readonly property var dist: Model.distribution(filtered)
    readonly property color muted: Util.alpha(Color.popups.text, 0.6)

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.rightMargin: Style.space(10)
        contentWidth: width
        contentHeight: content.implicitHeight + Style.space(12)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        QQC.ScrollBar.vertical: vbar

        Column {
            id: content
            width: flick.width
            spacing: Style.space(12)

            RangeSelector {
                anchors.horizontalCenter: parent.horizontalCenter
                rangeKey: page.rangeKey
                onRangeSelected: function (key) { page.rangeSelected(key) }
            }

            PlainLabel {
                width: parent.width
                visible: page.filtered.length === 0
                horizontalAlignment: Text.AlignHCenter
                topPadding: Style.space(40)
                text: 'No readings in this range.'
                color: page.muted
            }

            Card {
                id: chartCard
                width: parent.width
                visible: page.filtered.length > 0
                height: chartColumn.implicitHeight + Style.space(24)

                Column {
                    id: chartColumn
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(8)

                    Row {
                        spacing: Style.space(14)
                        Repeater {
                            model: [
                                { label: 'SYS', color: '#3b82f6' },
                                { label: 'DIA', color: '#22c55e' },
                                { label: 'PULSE', color: '#ef4444' }
                            ]
                            delegate: Row {
                                required property var modelData
                                spacing: Style.space(5)
                                Rectangle {
                                    width: Style.space(8)
                                    height: width
                                    radius: width / 2
                                    color: modelData.color
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                PlainLabel { text: modelData.label; color: page.muted; font.pixelSize: Style.font.caption }
                            }
                        }
                    }

                    LineChart {
                        width: parent.width
                        height: Style.space(200)
                        points: page.points
                        labels: page.labels
                    }
                }
            }

            Card {
                width: parent.width
                visible: page.filtered.length > 0
                height: avgColumn.implicitHeight + Style.space(24)

                Column {
                    id: avgColumn
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(8)

                    Row {
                        spacing: Style.space(10)
                        PlainLabel { text: 'Averages'; font.pixelSize: Style.font.subtitle; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                        CategoryBadge {
                            anchors.verticalCenter: parent.verticalCenter
                            categoryKey: page.avg.count ? Model.categoryOf(page.avg.sys, page.avg.dia) : 'normal'
                        }
                    }

                    Row {
                        spacing: Style.space(28)
                        Column {
                            PlainLabel { text: 'Avg SYS'; color: page.muted; font.pixelSize: Style.font.caption }
                            PlainLabel {
                                text: page.avg.count ? String(page.avg.sys) : '—'
                                color: page.avg.count ? Model.category(Model.categoryOf(page.avg.sys, page.avg.dia)).color : Color.popups.text
                                font.pixelSize: Style.font.display
                                font.bold: true
                            }
                        }
                        Column {
                            PlainLabel { text: 'Avg DIA'; color: page.muted; font.pixelSize: Style.font.caption }
                            PlainLabel { text: page.avg.count ? String(page.avg.dia) : '—'; font.pixelSize: Style.font.display; font.bold: true }
                        }
                        Column {
                            PlainLabel { text: '♥ Avg BPM'; color: page.muted; font.pixelSize: Style.font.caption }
                            PlainLabel { text: page.avg.count ? String(page.avg.pulse) : '—'; font.pixelSize: Style.font.display; font.bold: true }
                        }
                    }

                    PlainLabel {
                        text: 'Based on ' + page.avg.count + (page.avg.count === 1 ? ' reading' : ' readings')
                        color: page.muted
                        font.pixelSize: Style.font.bodySmall
                    }
                }
            }

            Card {
                width: parent.width
                visible: page.filtered.length > 0
                height: distColumn.implicitHeight + Style.space(24)

                Column {
                    id: distColumn
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(8)

                    PlainLabel { text: 'Distribution'; font.pixelSize: Style.font.subtitle; font.bold: true }

                    DistributionChart {
                        width: parent.width
                        height: Style.space(150)
                        items: page.dist
                    }
                }
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
}
