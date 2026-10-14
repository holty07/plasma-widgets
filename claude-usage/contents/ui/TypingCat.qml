import QtQuick

// A tiny Catppuccin-styled cat, shown while Claude Code looks actively
// running (hook data received recently). Two poses:
//   - typing (thinking = false): paws alternate on the keyboard, keys light
//     up, eyes closed and happy
//   - thinking (thinking = true): paws rest still, eyes open, a small
//     pulsing thought bubble appears - Code has a session open but is
//     waiting on you
Canvas {
    id: root
    implicitWidth: 80
    implicitHeight: 50
    property bool active: false
    property bool thinking: false
    property bool pawUp: true

    // Catppuccin Mocha
    readonly property color fur: "#fab387"        // peach
    readonly property color furShade: "#f2cdcd"   // flamingo (inner ear)
    readonly property color ink: "#11111b"        // crust (outline/eyes)
    readonly property color kbBase: "#313244"     // surface0
    readonly property color key: "#45475a"        // surface1
    readonly property color keyLit: "#f9e2af"     // yellow (key under active paw)
    readonly property color bubbleFill: "#cdd6f4" // text
    readonly property color bubbleOutline: "#585b70" // surface2

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220 } }

    Timer {
        interval: 280
        running: root.active && !root.thinking
        repeat: true
        onTriggered: root.pawUp = !root.pawUp
    }

    // Gentle tail sway, purely cosmetic, in both poses
    property real tailPhase: 0
    NumberAnimation on tailPhase {
        running: root.active
        loops: Animation.Infinite
        from: 0; to: Math.PI * 2
        duration: 1800
    }

    // Sequential dot pulse inside the thought bubble
    property real dotPhase: 0
    NumberAnimation on dotPhase {
        running: root.active && root.thinking
        loops: Animation.Infinite
        from: 0; to: Math.PI * 2
        duration: 1400
    }

    onActiveChanged: requestPaint()
    onThinkingChanged: requestPaint()
    onPawUpChanged: requestPaint()
    onTailPhaseChanged: requestPaint()
    onDotPhaseChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (!active) return

        var sx = width / 80
        var sy = height / 50
        function X(v) { return v * sx }
        function Y(v) { return v * sy }

        // --- tail, behind everything ---
        var tailSway = Math.sin(tailPhase) * Y(4)
        ctx.strokeStyle = fur
        ctx.lineWidth = X(4)
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(X(62), Y(30))
        ctx.quadraticCurveTo(X(74), Y(30) + tailSway, X(70), Y(14) + tailSway)
        ctx.stroke()

        // --- keyboard ---
        var kbX = X(8), kbY = Y(36), kbW = X(64), kbH = Y(12)
        ctx.fillStyle = kbBase
        roundRect(ctx, kbX, kbY, kbW, kbH, X(3))
        ctx.fill()

        var keys = 6
        var keyW = X(6), keyH = Y(5)
        var gap = (kbW - keys * keyW) / (keys + 1)
        for (var i = 0; i < keys; i++) {
            var kx = kbX + gap + i * (keyW + gap)
            var ky = kbY + Y(3.5)
            var lit = !thinking && ((i === 1 && !pawUp) || (i === 4 && pawUp))
            ctx.fillStyle = lit ? keyLit : key
            roundRect(ctx, kx, ky, keyW, keyH, X(1))
            ctx.fill()
        }

        // --- head ---
        var headCx = X(40), headCy = Y(20), headR = X(16)

        ctx.fillStyle = fur
        ctx.strokeStyle = ink
        ctx.lineWidth = X(1.2)
        drawEar(ctx, headCx - X(11), headCy - Y(10), X(9), Y(12), -1)
        drawEar(ctx, headCx + X(11), headCy - Y(10), X(9), Y(12), 1)

        ctx.beginPath()
        ctx.fillStyle = fur
        ctx.arc(headCx, headCy, headR, 0, Math.PI * 2)
        ctx.fill()
        ctx.stroke()

        // eyes: closed & happy while typing, small open dots while thinking
        ctx.strokeStyle = ink
        ctx.lineWidth = X(1.6)
        ctx.lineCap = "round"
        if (thinking) {
            ctx.fillStyle = ink
            ;[-1, 1].forEach(function (side) {
                ctx.beginPath()
                ctx.arc(headCx + side * X(6), headCy + Y(1), X(1.6), 0, Math.PI * 2)
                ctx.fill()
            })
        } else {
            drawEyeArc(ctx, headCx - X(6), headCy + Y(1))
            drawEyeArc(ctx, headCx + X(6), headCy + Y(1))
        }

        // nose
        ctx.fillStyle = "#eba0ac" // maroon
        ctx.beginPath()
        ctx.moveTo(headCx - X(1.5), headCy + Y(6))
        ctx.lineTo(headCx + X(1.5), headCy + Y(6))
        ctx.lineTo(headCx, headCy + Y(8))
        ctx.closePath()
        ctx.fill()

        // whiskers
        ctx.strokeStyle = ink
        ctx.lineWidth = X(0.8)
        ;[-1, 1].forEach(function (side) {
            for (var w = -1; w <= 1; w++) {
                ctx.beginPath()
                ctx.moveTo(headCx + side * X(9), headCy + Y(6) + Y(w * 2))
                ctx.lineTo(headCx + side * X(16), headCy + Y(5) + Y(w * 2.6))
                ctx.stroke()
            }
        })

        // --- paws ---
        var pawW = X(8), pawH = Y(9)
        var leftPawY, rightPawY
        if (thinking) {
            leftPawY = kbY - pawH + Y(4)
            rightPawY = kbY - pawH + Y(4)
        } else {
            leftPawY = kbY - pawH + (pawUp ? Y(2) : Y(6))
            rightPawY = kbY - pawH + (pawUp ? Y(6) : Y(2))
        }
        ctx.fillStyle = fur
        ctx.strokeStyle = ink
        ctx.lineWidth = X(1)
        roundRect(ctx, X(24), leftPawY, pawW, pawH, X(3))
        ctx.fill(); ctx.stroke()
        roundRect(ctx, X(48), rightPawY, pawW, pawH, X(3))
        ctx.fill(); ctx.stroke()

        // --- thought bubble, only while thinking ---
        if (thinking) {
            var bcx = headCx + X(24), bcy = headCy - Y(18)

            ctx.fillStyle = bubbleFill
            ctx.strokeStyle = bubbleOutline
            ctx.lineWidth = X(0.8)
            ;[
                { x: headCx + X(9), y: headCy - Y(11), r: X(1.6) },
                { x: headCx + X(13), y: headCy - Y(15), r: X(2.3) }
            ].forEach(function (c) {
                ctx.beginPath()
                ctx.arc(c.x, c.y, c.r, 0, Math.PI * 2)
                ctx.fill()
                ctx.stroke()
            })

            var bw = X(22), bh = Y(13)
            ctx.beginPath()
            roundRect(ctx, bcx - bw / 2, bcy - bh / 2, bw, bh, Y(6))
            ctx.fillStyle = bubbleFill
            ctx.fill()
            ctx.strokeStyle = bubbleOutline
            ctx.stroke()

            for (var d = 0; d < 3; d++) {
                var phase = dotPhase - d * (Math.PI * 2 / 3.6)
                var alpha = 0.35 + 0.65 * Math.max(0, Math.sin(phase))
                ctx.beginPath()
                ctx.fillStyle = "rgba(17,17,27," + alpha.toFixed(2) + ")" // ink w/ alpha
                ctx.arc(bcx - bw * 0.26 + d * bw * 0.26, bcy, X(1.7), 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }

    function roundRect(ctx, x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.arcTo(x + w, y, x + w, y + h, r)
        ctx.arcTo(x + w, y + h, x, y + h, r)
        ctx.arcTo(x, y + h, x, y, r)
        ctx.arcTo(x, y, x + w, y, r)
        ctx.closePath()
    }

    function drawEar(ctx, tipX, tipY, w, h, dir) {
        ctx.beginPath()
        ctx.moveTo(tipX, tipY)
        ctx.lineTo(tipX - dir * w * 0.6, tipY + h)
        ctx.lineTo(tipX + dir * w * 0.9, tipY + h * 0.7)
        ctx.closePath()
        ctx.fill()
        ctx.stroke()
    }

    function drawEyeArc(ctx, cx, cy) {
        ctx.beginPath()
        ctx.arc(cx, cy, width * 0.045, Math.PI * 0.15, Math.PI * 0.85)
        ctx.stroke()
    }
}
