import QtQuick
import qs.Commons
import "../Model.js" as Model

// Coloured pill with the short label of a blood-pressure category.
Rectangle {
    id: badge

    property string categoryKey: 'normal'
    readonly property var category: Model.category(categoryKey)

    implicitWidth: badgeText.implicitWidth + Style.space(14)
    implicitHeight: badgeText.implicitHeight + Style.space(4)
    radius: height / 2
    color: Util.alpha(category.color, 0.2)
    border.width: 1
    border.color: Util.alpha(category.color, 0.6)

    Text {
        id: badgeText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: badge.category.label
        color: badge.category.color
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
    }
}
