import QtQuick

// A simple donut-style ring chart. `percent` is 0-100, null means "no data".
Canvas {
    id: ring
    property var percent: null
    property color ringColor: "#a6e3a1"
    property color trackColor: "#313244" // Catppuccin Mocha "surface0"
    property real thickness: 0.22 // fraction of radius
    property bool showLabel: true
    property color labelColor: "#cdd6f4" // Catppuccin Mocha "text"

    onPercentChanged: requestPaint()
    onRingColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        var w = width
        var h = height
        var cx = w / 2
        var cy = h / 2
        var radius = Math.min(w, h) / 2 - 1
        var lineWidth = Math.max(2, radius * thickness)
        var r = radius - lineWidth / 2

        var startAngle = -Math.PI / 2

        // Background track
        ctx.beginPath()
        ctx.lineWidth = lineWidth
        ctx.strokeStyle = trackColor
        ctx.lineCap = "round"
        ctx.arc(cx, cy, r, 0, Math.PI * 2, false)
        ctx.stroke()

        if (percent !== null && percent !== undefined) {
            var frac = Math.max(0, Math.min(100, percent)) / 100
            if (frac > 0) {
                var endAngle = startAngle + frac * Math.PI * 2
                ctx.beginPath()
                ctx.lineWidth = lineWidth
                ctx.strokeStyle = ringColor
                ctx.lineCap = "round"
                ctx.arc(cx, cy, r, startAngle, endAngle, false)
                ctx.stroke()
            }
        }

        if (showLabel && percent !== null && percent !== undefined && Math.min(w, h) >= 20) {
            var innerDiameter = (r - lineWidth / 2) * 2
            var fontPx = Math.max(7, Math.round(innerDiameter * 0.34))
            ctx.font = "bold " + fontPx + "px sans-serif"
            ctx.fillStyle = labelColor
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillText(Math.round(percent) + "%", cx, cy + fontPx * 0.04)
        }
    }
}
