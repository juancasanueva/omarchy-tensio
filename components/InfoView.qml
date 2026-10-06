import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Category reference: colour, label and range for each category, the
// emergency warning, the source note and the medical disclaimer.
Item {
    id: info

    signal closeRequested()

    readonly property color muted: Util.alpha(Color.popups.text, 0.6)

    // Keyboard scrolling (j / k, Up / Down, PageUp / PageDown).
    function scrollBy(dy) {
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + dy))
    }
    function scrollStep(direction) { scrollBy(direction * Style.space(48)) }
    function scrollPage(direction) { scrollBy(direction * Math.max(Style.space(48), flick.height * 0.9)) }

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
            spacing: Style.space(10)

            Item {
                width: parent.width
                height: backButton.implicitHeight
                PlainLabel {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: 'Blood pressure categories'
                    font.pixelSize: Style.font.heading
                    font.bold: true
                }
                Button {
                    id: backButton
                    anchors.right: parent.right
                    text: 'Done'
                    bordered: true
                    foreground: Color.popups.text
                    onClicked: info.closeRequested()
                }
            }

            Card {
                width: parent.width
                height: categories.implicitHeight + Style.space(20)

                Column {
                    id: categories
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    spacing: Style.space(8)

                    Repeater {
                        model: Model.CATEGORIES
                        delegate: Row {
                            required property var modelData
                            spacing: Style.space(10)
                            Rectangle {
                                width: Style.space(12)
                                height: width
                                radius: width / 2
                                color: modelData.color
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            PlainLabel {
                                width: Style.space(190)
                                text: modelData.longLabel
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            PlainLabel {
                                text: modelData.description
                                color: info.muted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: warning.implicitHeight + Style.space(20)
                radius: Math.max(8, Style.cornerRadius)
                color: Util.alpha(Model.category('severe').color, 0.18)
                border.width: 1
                border.color: Model.category('severe').color

                PlainLabel {
                    id: warning
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    text: Model.SEVERE_WARNING
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }

            PlainLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                text: 'Categories follow the American Heart Association (AHA) table, plus a Low band below 90/60.'
                color: info.muted
            }

            PlainLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                text: 'Tensio does not measure blood pressure and is not a medical device. Always check with your doctor before making medical decisions.'
                color: info.muted
                font.italic: true
            }
        }
    }

    // Sibling of the flickable so it can sit at the page edge.
    QQC.ScrollBar {
        id: vbar
        anchors.top: info.top
        anchors.bottom: info.bottom
        anchors.right: info.right
        policy: QQC.ScrollBar.AsNeeded
    }
}
