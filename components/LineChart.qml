import QtQuick
import qs.Commons

// SYS / DIA / pulse line chart on a Canvas. `points` must already be
// downsampled by the caller (Model.downsample, at most 400 points) and
// `labels` thinned (Model.thinLabels); this item only paints them.
Canvas {
    id: chart

    property var points: []
    property var labels: []
    property color foreground: Color.popups.text
    property string fontFamily: Style.font.family
    property int fontSize: Style.font.caption

    readonly property var series: [
        { key: 'sys', color: '#3b82f6' },
        { key: 'dia', color: '#22c55e' },
        { key: 'pulse', color: '#ef4444' }
    ]

    onPointsChanged: requestPaint()
    onLabelsChanged: requestPaint()
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
        var pts = chart.points || []
        var left = Style.space(30), right = Style.space(10), top = Style.space(8), bottom = Style.space(22)
        var w = width - left - right
        var h = height - top - bottom
        if (w <= 0 || h <= 0) return

        var maxValue = 150
        for (var i = 0; i < pts.length; i++)
            maxValue = Math.max(maxValue, pts[i].sys, pts[i].dia, pts[i].pulse)
        var yMax = Math.ceil(maxValue / 50) * 50
        function yOf(v) { return top + h - (v / yMax) * h }

        ctx.font = fontSize + 'px "' + fontFamily + '"'
        ctx.lineWidth = 1
        ctx.textAlign = 'right'
        ctx.textBaseline = 'middle'
        for (var g = 0; g <= yMax; g += 50) {
            var gy = Math.round(yOf(g)) + 0.5
            ctx.strokeStyle = rgba(foreground, g === 0 ? 0.3 : 0.12)
            ctx.beginPath()
            ctx.moveTo(left, gy)
            ctx.lineTo(left + w, gy)
            ctx.stroke()
            ctx.fillStyle = rgba(foreground, 0.6)
            ctx.fillText(String(g), left - Style.space(6), gy)
        }

        if (pts.length === 0) return
        var tMin = pts[0].t
        var tMax = pts[pts.length - 1].t
        var span = tMax - tMin
        function xOf(t) { return span > 0 ? left + ((t - tMin) / span) * w : left + w / 2 }

        ctx.textAlign = 'center'
        ctx.textBaseline = 'top'
        ctx.fillStyle = rgba(foreground, 0.6)
        var lbls = chart.labels || []
        // Skip a label that would overlap the previous one drawn.
        var lastRight = -Infinity
        for (var l = 0; l < lbls.length; l++) {
            var text = String(lbls[l].label)
            var half = ctx.measureText(text).width / 2
            var lx = Math.max(left + half, Math.min(left + w - half, xOf(Math.max(tMin, lbls[l].t))))
            if (lx - half < lastRight + Style.space(6)) continue
            ctx.fillText(text, lx, top + h + Style.space(6))
            lastRight = lx + half
        }

        var dots = pts.length <= 120
        for (var s = 0; s < series.length; s++) {
            var key = series[s].key
            ctx.strokeStyle = series[s].color
            ctx.fillStyle = series[s].color
            ctx.lineWidth = 2
            ctx.beginPath()
            for (var p = 0; p < pts.length; p++) {
                var x = xOf(pts[p].t), y = yOf(pts[p][key])
                if (p === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
            }
            ctx.stroke()
            if (dots) {
                for (var d = 0; d < pts.length; d++) {
                    ctx.beginPath()
                    ctx.arc(xOf(pts[d].t), yOf(pts[d][key]), 2.5, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }
    }
}
