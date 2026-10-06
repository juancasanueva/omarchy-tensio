import QtQuick
import qs.Commons

// Category distribution as six vertical bars with percent labels above and
// the category labels below. `items` is Model.distribution() output.
Canvas {
    id: chart

    property var items: []
    property color foreground: Color.popups.text
    property string fontFamily: Style.font.family
    property int fontSize: Style.font.caption

    onItemsChanged: requestPaint()
    onForegroundChanged: requestPaint()
    onFontFamilyChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function rgba(c, a) {
        return 'rgba(' + Math.round(c.r * 255) + ',' + Math.round(c.g * 255) + ',' + Math.round(c.b * 255) + ',' + a + ')'
    }

    onPaint: {
        var ctx = getContext('2d')
        ctx.reset()
        var list = chart.items || []
        var n = Math.min(list.length, 6)
        var top = Style.space(18), bottom = Style.space(22)
        var h = height - top - bottom
        if (n === 0 || width <= 0 || h <= 0) return
        var slot = width / n
        var barWidth = Math.min(Style.space(36), slot * 0.6)

        ctx.font = fontSize + 'px "' + fontFamily + '"'
        ctx.textAlign = 'center'
        ctx.strokeStyle = rgba(foreground, 0.25)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(0, top + h + 0.5)
        ctx.lineTo(width, top + h + 0.5)
        ctx.stroke()

        for (var i = 0; i < n; i++) {
            var item = list[i]
            var pct = Math.max(0, Math.min(100, Number(item.pct) || 0))
            var barHeight = h * pct / 100
            var cx = slot * i + slot / 2
            ctx.fillStyle = String(item.color)
            if (barHeight > 0) ctx.fillRect(cx - barWidth / 2, top + h - barHeight, barWidth, barHeight)
            ctx.fillStyle = rgba(foreground, 0.85)
            ctx.textBaseline = 'bottom'
            ctx.fillText(pct + '%', cx, top + h - barHeight - Style.space(3))
            ctx.fillStyle = rgba(foreground, 0.6)
            ctx.textBaseline = 'top'
            ctx.fillText(String(item.label), cx, top + h + Style.space(6))
        }
    }
}
