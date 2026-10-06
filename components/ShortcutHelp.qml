import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Keyboard shortcut overlay, toggled with `?`. Lists Model.shortcutHelp()
// grouped in table order; the README documents the same rows.
Rectangle {
    id: help

    signal closeRequested()

    readonly property color muted: Util.alpha(Color.popups.text, 0.6)
    // [{ name, rows: [{ keys, action }] }] in first-seen group order.
    readonly property var groups: {
        var out = []
        var rows = Model.shortcutHelp()
        for (var i = 0; i < rows.length; i++) {
            if (!out.length || out[out.length - 1].name !== rows[i].group)
                out.push({ name: rows[i].group, rows: [] })
            out[out.length - 1].rows.push({ keys: rows[i].keys, action: rows[i].action })
        }
        return out
    }

    function scrollBy(dy) {
        var maxY = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + dy))
    }
    function scrollStep(direction) { scrollBy(direction * Style.space(48)) }
    function scrollPage(direction) { scrollBy(direction * Math.max(Style.space(48), flick.height * 0.9)) }
    function resetScroll() { flick.contentY = 0 }

    color: Color.popups.background

    // Swallow clicks so the page underneath stays inert.
    MouseArea { anchors.fill: parent }

    Item {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: doneButton.implicitHeight

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            PlainLabel {
                text: 'Keyboard shortcuts'
                font.pixelSize: Style.font.heading
                font.bold: true
            }
            PlainLabel {
                text: 'Press Esc or ? to close'
                color: help.muted
                font.pixelSize: Style.font.caption
            }
        }
        Button {
            id: doneButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: 'Done'
            bordered: true
            foreground: Color.popups.text
            onClicked: help.closeRequested()
        }
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleBar.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.space(10)
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

            Repeater {
                model: help.groups
                delegate: Card {
                    id: groupCard
                    required property var modelData
                    width: content.width
                    height: groupColumn.implicitHeight + Style.space(20)

                    Column {
                        id: groupColumn
                        anchors.fill: parent
                        anchors.margins: Style.space(10)
                        spacing: Style.space(6)

                        PlainLabel {
                            text: groupCard.modelData.name
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                        }

                        Repeater {
                            model: groupCard.modelData.rows
                            delegate: Row {
                                id: shortcutRow
                                required property var modelData
                                width: groupColumn.width
                                spacing: Style.space(10)

                                PlainLabel {
                                    width: Math.round(shortcutRow.width * 0.42)
                                    text: shortcutRow.modelData.keys
                                    color: Color.accent
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideNone
                                }
                                PlainLabel {
                                    width: shortcutRow.width - Math.round(shortcutRow.width * 0.42) - shortcutRow.spacing
                                    text: shortcutRow.modelData.action
                                    color: help.muted
                                    wrapMode: Text.WordWrap
                                    elide: Text.ElideNone
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Sibling of the flickable so it can sit at the overlay edge.
    QQC.ScrollBar {
        id: vbar
        anchors.top: flick.top
        anchors.bottom: flick.bottom
        anchors.right: help.right
        policy: QQC.ScrollBar.AsNeeded
    }
}
