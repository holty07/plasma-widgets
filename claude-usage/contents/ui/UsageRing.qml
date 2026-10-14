import QtQuick

// Concentric donut rings. The outer ring shows `percent` (session), the
// optional smaller inner ring shows `innerPercent` (weekly). Both are 0-100,
// null means "no data". The centre label stacks the outer value over the
// inner one, each tinted to match its ring.
Canvas {
    id: ring
    property var percent: null
    property color ringColor: "#a6e3a1"
    property var innerPercent: null
    property color innerColor: "#b4befe" // Catppuccin Mocha "lavender"
    property bool showInner: true
    property color trackColor: "#313244" // Catppuccin Mocha "surface0"
    property real thickness: 0.18 // fraction of radius
    property real innerThickness: 0.11 // fraction of radius
    property real ringGap: 0.05 // fraction of radius between the two rings
    property bool showLabel: true
    property color labelColor: "#cdd6f4" // Catppuccin Mocha "text"

    onPercentChanged: requestPaint()
    onRingColorChanged: requestPaint()
    onInnerPercentChanged: requestPaint()
    onInnerColorChanged: requestPaint()
    onShowInnerChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function hasValue(v) {
        return v !== null && v !== undefined
    }

    function drawRing(ctx, cx, cy, r, lineWidth, value, color) {
        ctx.beginPath()
        ctx.lineWidth = lineWidth
        ctx.strokeStyle = trackColor
        ctx.lineCap = "round"
        ctx.arc(cx, cy, r, 0, Math.PI * 2, false)
        ctx.stroke()

        if (!hasValue(value)) return
        var frac = Math.max(0, Math.min(100, value)) / 100
        if (frac <= 0) return
        var startAngle = -Math.PI / 2
        ctx.beginPath()
        ctx.lineWidth = lineWidth
        ctx.strokeStyle = color
        ctx.lineCap = "round"
        ctx.arc(cx, cy, r, startAngle, startAngle + frac * Math.PI * 2, false)
        ctx.stroke()
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        var w = width
        var h = height
        var cx = w / 2
        var cy = h / 2
        var radius = Math.min(w, h) / 2 - 1

        var outerWidth = Math.max(2, radius * thickness)
        var outerR = radius - outerWidth / 2
        drawRing(ctx, cx, cy, outerR, outerWidth, percent, ringColor)

        // Free space inside the rings, used to size the label.
        var hole = outerR - outerWidth / 2

        if (showInner) {
            var innerWidth = Math.max(1.5, radius * innerThickness)
            var innerR = hole - radius * ringGap - innerWidth / 2
            if (innerR > innerWidth) {
                drawRing(ctx, cx, cy, innerR, innerWidth, innerPercent, innerColor)
                hole = innerR - innerWidth / 2
            }
        }

        if (!showLabel || !hasValue(percent) || Math.min(w, h) < 20) return

        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        var diameter = hole * 2

        if (showInner && hasValue(innerPercent)) {
            var mainPx = Math.max(7, Math.round(diameter * 0.36))
            var subPx = Math.max(6, Math.round(diameter * 0.22))
            var blockH = mainPx + subPx
            var top = cy - blockH / 2

            ctx.font = "bold " + mainPx + "px sans-serif"
            ctx.fillStyle = labelColor
            ctx.fillText(Math.round(percent) + "%", cx, top + mainPx / 2)

            ctx.font = "bold " + subPx + "px sans-serif"
            ctx.fillStyle = innerColor
            ctx.fillText(Math.round(innerPercent) + "%", cx, top + mainPx + subPx / 2)
        } else {
            var fontPx = Math.max(7, Math.round(diameter * 0.40))
            ctx.font = "bold " + fontPx + "px sans-serif"
            ctx.fillStyle = labelColor
            ctx.fillText(Math.round(percent) + "%", cx, cy + fontPx * 0.04)
        }
    }
}
