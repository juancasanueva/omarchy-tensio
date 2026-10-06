import QtQuick
import qs.Commons

// Text that always renders as plain text in the panel's palette. Every
// label in the plugin goes through this type or sets textFormat itself.
Text {
    textFormat: Text.PlainText
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
}
