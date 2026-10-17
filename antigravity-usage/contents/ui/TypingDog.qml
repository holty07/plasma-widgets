import QtQuick

// Dog counterpart to TypingCat - same rig (keyboard, paws, thought bubble),
// different critter. Two poses:
//   - typing (thinking = false): paws alternate on the keyboard, keys light
//     up, tongue out, happy
//   - thinking (thinking = true): paws rest still, head tilted/curious, a
//     small pulsing thought bubble appears
Canvas {
    id: root
    implicitWidth: 80
    implicitHeight: 50
    property bool active: false
    property bool thinking: false
    property bool pawUp: true

    // Catppuccin Mocha - blue/sapphire family, to sit visually apart from
    // the peach cat
    readonly property color fur: "#89b4fa"        // blue
    readonly property color furShade: "#74c7ec"   // sapphire (inner ear/muzzle)
    readonly property color ink: "#11111b"        // crust (outline/eyes)
    readonly property color kbBase: "#313244"     // surface0
    readonly property color key: "#45475a"        // surface1
    readonly property color keyLit: "#f9e2af"     // yellow (key under active paw)
    readonly property color bubbleFill: "#cdd6f4" // text
    readonly property color bubbleOutline: "#585b70" // surface2
    readonly property color tongue: "#eba0ac"     // maroon

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220 } }

    Timer {
        interval: 240
        running: root.active && !root.thinking
        repeat: true
        onTriggered: root.pawUp = !root.pawUp
    }

    // Tail wag - faster and wider than the cat's lazy sway, dogs are excitable
    property real tailPhase: 0
    NumberAnimation on tailPhase {
        running: root.active && !root.thinking
        loops: Animation.Infinite
        from: 0; to: Math.PI * 2
        duration: 500
    }
    // Slow single sway while thinking (head-tilt curiosity, not excitement)
    NumberAnimation on tailPhase {
        running: root.active && root.thinking
        loops: Animation.Infinite
        from: 0; to: Math.PI * 2
        duration: 2200
    }

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
        var tailAmp = thinking ? Y(2) : Y(6)
        var tailSway = Math.sin(tailPhase) * tailAmp
        ctx.strokeStyle = fur
        ctx.lineWidth = X(4)
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(X(62), Y(32))
        ctx.quadraticCurveTo(X(75), Y(30) + tailSway, X(71), Y(16) + tailSway)
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

        // --- head, tilted while thinking ---
        var headCx = X(40), headCy = Y(20), headR = X(15)
        var tilt = thinking ? Math.sin(tailPhase) * 0.12 : 0

        ctx.save()
        ctx.translate(headCx, headCy)
        ctx.rotate(tilt)
        ctx.translate(-headCx, -headCy)

        // floppy ears (droopy ovals rather than the cat's pointed triangles)
        ctx.fillStyle = furShade
        ctx.strokeStyle = ink
        ctx.lineWidth = X(1.2)
        drawFloppyEar(ctx, headCx - X(13), headCy - Y(2), X(7), Y(13), -1)
        drawFloppyEar(ctx, headCx + X(13), headCy - Y(2), X(7), Y(13), 1)

        // head
        ctx.beginPath()
        ctx.fillStyle = fur
        ctx.arc(headCx, headCy, headR, 0, Math.PI * 2)
        ctx.fill()
        ctx.stroke()

        // muzzle
        ctx.beginPath()
        ctx.fillStyle = furShade
        ctx.ellipse ? ctx.ellipse(headCx, headCy + Y(6), X(7), Y(5), 0, 0, Math.PI * 2)
                    : ctx.arc(headCx, headCy + Y(6), X(6), 0, Math.PI * 2)
        ctx.fill()
        ctx.stroke()

        // eyes
        ctx.fillStyle = ink
        if (thinking) {
            ;[-1, 1].forEach(function (side) {
                ctx.beginPath()
                ctx.arc(headCx + side * X(6), headCy - Y(1), X(1.7), 0, Math.PI * 2)
                ctx.fill()
            })
        } else {
            // happy squinted eyes (small upward arcs)
            ctx.strokeStyle = ink
            ctx.lineWidth = X(1.6)
            ctx.lineCap = "round"
            ;[-1, 1].forEach(function (side) {
                ctx.beginPath()
                ctx.arc(headCx + side * X(6), headCy + Y(0.5), X(2), Math.PI * 1.1, Math.PI * 1.9)
                ctx.stroke()
            })
        }

        // nose
        ctx.fillStyle = ink
        ctx.beginPath()
        ctx.arc(headCx, headCy + Y(3.5), X(1.8), 0, Math.PI * 2)
        ctx.fill()

        // tongue while typing, closed mouth while thinking
        if (!thinking) {
            ctx.fillStyle = tongue
            roundRect(ctx, headCx - X(2), headCy + Y(7), X(4), Y(6), X(2))
            ctx.fill()
        }

        ctx.restore()

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

    function drawFloppyEar(ctx, cx, cy, w, h, dir) {
        ctx.beginPath()
        ctx.moveTo(cx, cy - h * 0.3)
        ctx.quadraticCurveTo(cx + dir * w, cy + h * 0.1, cx + dir * w * 0.6, cy + h)
        ctx.quadraticCurveTo(cx, cy + h * 0.7, cx, cy - h * 0.3)
        ctx.closePath()
        ctx.fill()
        ctx.stroke()
    }
}
