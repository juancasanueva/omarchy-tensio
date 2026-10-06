import QtQuick
import qs.Commons
import "../Model.js" as Model

// Six-segment colour bar (Low .. Severe) with a marker over the segment of
// the current category, as on the reading form of the iOS app.
Item {
    id: bar

    property string categoryKey: 'normal'
    readonly property int activeIndex: {
        for (var i = 0; i < Model.CATEGORIES.length; i++)
            if (Model.CATEGORIES[i].key === bar.categoryKey) return i
        return 1
    }
    readonly property real segmentWidth: (width - (Model.CATEGORIES.length - 1) * gap) / Model.CATEGORIES.length
    readonly property real gap: Style.space(3)

    implicitHeight: Style.space(18)

    Row {
        id: segments
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(8)
        spacing: bar.gap

        Repeater {
            model: Model.CATEGORIES
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: bar.segmentWidth
                height: segments.height
                radius: height / 2
                color: modelData.color
                opacity: index === bar.activeIndex ? 1 : 0.35
            }
        }
    }

    // Downward triangle above the active segment.
    Canvas {
        id: marker
        width: Style.space(10)
        height: Style.space(7)
        x: bar.activeIndex * (bar.segmentWidth + bar.gap) + bar.segmentWidth / 2 - width / 2
        anchors.bottom: segments.top
        anchors.bottomMargin: Style.space(2)
        property color fill: Color.popups.text
        onFillChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext('2d')
            ctx.reset()
            ctx.fillStyle = String(fill)
            ctx.beginPath()
            ctx.moveTo(0, 0)
            ctx.lineTo(width, 0)
            ctx.lineTo(width / 2, height)
            ctx.closePath()
            ctx.fill()
        }
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
}
