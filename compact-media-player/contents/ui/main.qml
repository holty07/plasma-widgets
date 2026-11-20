/*
 * Compact Media Player
 * MPRIS controller with a cava visualiser, built to survive being resized.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris

PlasmoidItem {
    id: root

    // ────────────────────────────────────────────────────────────── state ──

    Mpris.Mpris2Model { id: mpris2Model }

    // Pinning. Plasma's model always jumps to the most recent player, so a
    // notification chime or a browser tab hijacks the widget and never hands it
    // back. When pinned we steer currentIndex to the wanted player and refuse
    // to report anything else as the current player.
    readonly property bool pinned: Plasmoid.configuration.pinPlayer
        && Plasmoid.configuration.pinnedPlayer !== ""
    readonly property string pinnedId: Plasmoid.configuration.pinnedPlayer
    property bool repinning: false

    readonly property var player: {
        var p = mpris2Model.currentPlayer;
        if (!p) return null;
        if (root.pinned && !root.playerMatches(p, root.pinnedId)) return null;
        return p;
    }

    function playerMatches(p, want) {
        if (!p || !want) return false;
        return p.desktopEntry === want || p.identity === want;
    }

    function modelRows() {
        try {
            var n = mpris2Model.rowCount();
            return isFinite(n) ? n : 0;
        } catch (e) {
            return 0;
        }
    }

    // Walk the model looking for the pinned player. Reading each row's
    // container means moving currentIndex, so this restores it when the pinned
    // player is absent rather than leaving some other app selected.
    function repin() {
        if (!root.pinned || root.repinning) return;
        root.repinning = true;

        if (!root.playerMatches(mpris2Model.currentPlayer, root.pinnedId)) {
            var saved = mpris2Model.currentIndex;
            var found = false;
            var n = root.modelRows();
            for (var i = 0; i < n; ++i) {
                mpris2Model.currentIndex = i;
                if (root.playerMatches(mpris2Model.currentPlayer, root.pinnedId)) {
                    found = true;
                    break;
                }
            }
            if (!found) mpris2Model.currentIndex = saved;
        }

        root.repinning = false;
    }

    Timer {
        id: repinTimer
        interval: 250
        onTriggered: root.repin()
    }

    Connections {
        target: mpris2Model
        function onCurrentPlayerChanged() { repinTimer.restart(); }
        function onRowsInserted() { repinTimer.restart(); }
        function onRowsRemoved() { repinTimer.restart(); }
        function onModelReset() { repinTimer.restart(); }
    }

    onPinnedChanged: repinTimer.restart()
    onPinnedIdChanged: repinTimer.restart()
    readonly property bool hasPlayer: player !== null && player !== undefined
    readonly property bool isPlaying: hasPlayer && player.playbackStatus === Mpris.PlaybackStatus.Playing

    readonly property string trackTitle: hasPlayer && player.track ? player.track : ""
    readonly property string trackArtist: hasPlayer && player.artist ? player.artist : ""
    readonly property string trackAlbum: hasPlayer && player.album ? player.album : ""
    readonly property string artUrl: hasPlayer && player.artUrl ? String(player.artUrl) : ""

    readonly property string visualiserMode: Plasmoid.configuration.visualiserMode
    readonly property bool visualiserOn: visualiserMode !== "off"

    // `expanded` is only meaningful for a popup. A widget sitting on the
    // desktop shows its full representation with expanded == false, so gating
    // timers on it alone stops them ever running there.
    readonly property bool viewActive: Plasmoid.formFactor === PlasmaCore.Types.Planar
        || root.expanded

    Plasmoid.status: !hasPlayer ? PlasmaCore.Types.HiddenStatus
                                : (isPlaying ? PlasmaCore.Types.ActiveStatus
                                             : PlasmaCore.Types.PassiveStatus)

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground

    toolTipMainText: trackTitle !== "" ? trackTitle
        : (root.pinned ? i18n("Waiting for %1", root.pinnedId) : i18n("Nothing playing"))
    toolTipSubText: {
        var bits = [trackArtist, trackAlbum].filter(function (s) { return s !== ""; });
        if (root.visualiserOn && root.isPlaying && !cava.receiving) {
            bits.push(cava.pathReady
                ? i18n("visualiser: no data from %1", cava.displayPath)
                : i18n("visualiser: path unresolved (%1)", cava.resolvedVia));
        }
        return bits.join(" — ");
    }

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation : compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 9
    switchHeight: Kirigami.Units.gridUnit * 4

    Layout.minimumWidth: Kirigami.Units.gridUnit * 8
    Layout.minimumHeight: Kirigami.Units.gridUnit * 3
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredHeight: Kirigami.Units.gridUnit * 8

    // ───────────────────────────────────────────────────────────── helpers ──

    // Reading a config key that the loaded schema does not know about yields
    // undefined, and undefined arithmetic yields NaN, which silently destroys
    // any binding it touches. Every numeric config read goes through this.
    function cfgNum(value, fallback) {
        var n = Number(value);
        return isFinite(n) ? n : fallback;
    }

    function formatTime(microseconds) {
        var total = Math.max(0, Math.floor(microseconds / 1000000));
        var h = Math.floor(total / 3600);
        var m = Math.floor((total % 3600) / 60);
        var s = total % 60;
        var mm = h > 0 && m < 10 ? "0" + m : String(m);
        var ss = s < 10 ? "0" + s : String(s);
        return (h > 0 ? h + ":" : "") + mm + ":" + ss;
    }

    function togglePlay() { if (hasPlayer) player.PlayPause(); }
    function next() { if (hasPlayer && player.canGoNext) player.Next(); }
    function previous() { if (hasPlayer && player.canGoPrevious) player.Previous(); }

    function seekTo(microseconds) {
        if (hasPlayer && player.canSeek) player.position = microseconds;
    }

    function nudgeVolume(delta) {
        if (!hasPlayer) return;
        var v = player.volume;
        if (v === undefined || v === null) return;
        player.volume = Math.max(0, Math.min(1, v + delta));
    }

    function cycleLoop() {
        if (!hasPlayer) return;
        if (player.loopStatus === Mpris.LoopStatus.None) {
            player.loopStatus = Mpris.LoopStatus.Playlist;
        } else if (player.loopStatus === Mpris.LoopStatus.Playlist) {
            player.loopStatus = Mpris.LoopStatus.Track;
        } else {
            player.loopStatus = Mpris.LoopStatus.None;
        }
    }

    function toggleShuffle() {
        if (!hasPlayer) return;
        player.shuffle = player.shuffle === Mpris.ShuffleStatus.On
            ? Mpris.ShuffleStatus.Off : Mpris.ShuffleStatus.On;
    }

    // ──────────────────────────────────────────────────── cava plumbing ──

    CavaSource {
        id: cava
        fps: root.cfgNum(Plasmoid.configuration.framerate, 20)
        active: root.visualiserOn && root.isPlaying && root.viewActive
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function (source) { disconnectSource(source); }
        function run(cmd) { if (cmd) connectSource(cmd); }
    }

    // Debounced so a quick pause/skip does not thrash the service.
    Timer {
        id: serviceGate
        interval: 1500
        onTriggered: root.syncCavaService()
    }

    function syncCavaService() {
        if (!Plasmoid.configuration.autoManageCava) return;
        var svc = Plasmoid.configuration.cavaService;
        if (!svc) return;
        var wanted = root.visualiserOn && root.isPlaying;
        runner.run("systemctl --user " + (wanted ? "start " : "stop ") + svc);
    }

    onIsPlayingChanged: serviceGate.restart()
    onVisualiserOnChanged: serviceGate.restart()
    Component.onCompleted: {
        serviceGate.restart();
        repinTimer.restart();
    }

    // MPRIS position is not pushed by most players; poll it while playing.
    Timer {
        interval: 1000
        repeat: true
        running: root.isPlaying && root.viewActive
        onTriggered: {
            if (root.hasPlayer && root.player.updatePosition) root.player.updatePosition();
        }
    }

    // ──────────────────────────────────────────────── full representation ──

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 8
        Layout.minimumHeight: Kirigami.Units.gridUnit * 3

        readonly property real pad: Kirigami.Units.smallSpacing
        readonly property bool rowMode: width > height * 1.25

        // Explicit geometry rather than conditional anchors. Switching anchors
        // with ternaries means left/horizontalCenter (and top/verticalCenter)
        // can both be live during a transition, which lays out unpredictably —
        // it caused the art to centre while the metadata kept anchoring to its
        // right edge and fell off the widget. Plain numbers cannot do that.
        readonly property real coverSize: {
            // Never let the art claim more than half the width in row mode, or
            // the metadata column gets squeezed out of existence.
            var s = rowMode ? Math.min(height - pad * 2, width * 0.5)
                            : Math.min(width - pad * 2, height * 0.52);
            return isFinite(s) && s > 0 ? s : 0;
        }

        readonly property real coverX: rowMode ? pad : (width - coverSize) / 2
        readonly property real coverY: rowMode ? (height - coverSize) / 2 : pad

        readonly property real infoX: rowMode ? coverX + coverSize + pad * 2 : pad * 1.5
        readonly property real infoY: rowMode ? pad : coverY + coverSize + pad
        // Clamped at zero so the column can never extend past the right edge.
        readonly property real infoW: Math.max(0, width - infoX - pad * 1.5)
        readonly property real infoH: Math.max(0, height - infoY - pad)

        // Album art tint, with a legible fallback.
        Kirigami.ImageColors {
            id: albumColours
            source: cover
        }

        Connections {
            target: cover
            function onStatusChanged() {
                if (cover.status === Image.Ready) albumColours.update();
            }
        }

        readonly property color accent: {
            if (!Plasmoid.configuration.useAlbumColours || root.artUrl === "") {
                return Kirigami.Theme.highlightColor;
            }
            var c = albumColours.highlight;
            if (!c || c.a === 0) return Kirigami.Theme.highlightColor;
            // Keep it readable against the panel background.
            return Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark
                ? Qt.lighter(c, 1.15) : Qt.darker(c, 1.05);
        }

        // ── blurred backdrop ──
        Item {
            anchors.fill: parent
            visible: Plasmoid.configuration.showBackdrop && root.artUrl !== ""
            clip: true

            Image {
                id: backdropSource
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: backdropSource
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                blurMultiplier: 1.2
                saturation: 0.35
                opacity: root.cfgNum(Plasmoid.configuration.backdropOpacity, 30) / 100
            }

            // Scrim keeps text legible on both light and dark themes.
            Rectangle {
                anchors.fill: parent
                color: Kirigami.Theme.backgroundColor
                opacity: 0.45
            }
        }

        // ── background visualiser ──
        Visualiser {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * 0.5
            visible: root.visualiserMode === "background"
            levels: cava.levels
            baseColour: view.accent
            peakColour: Qt.lighter(view.accent, 1.5)
            barThickness: root.cfgNum(Plasmoid.configuration.barThickness, 4)
            barGap: root.cfgNum(Plasmoid.configuration.barGap, 2)
            mirrored: false
            smoothing: Math.round(1000 / cava.effectiveFps * 1.35)
            opacity: 0.32
            z: -1
        }

        // ── album art ──
        Rectangle {
            id: coverFrame
            width: view.coverSize
            height: view.coverSize
            radius: Kirigami.Units.cornerRadius !== undefined
                ? Kirigami.Units.cornerRadius : Kirigami.Units.smallSpacing
            // Transparent once the art loads, so a non-square cover letterboxes
            // against the backdrop rather than against a grey slab.
            color: cover.status === Image.Ready
                ? "transparent"
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                          Kirigami.Theme.textColor.b, 0.08)
            clip: true
            visible: view.coverSize > Kirigami.Units.gridUnit

            // left and horizontalCenter are mutually exclusive — setting both
            // is a conflicting-anchor warning and lays out unpredictably.
            x: view.coverX
            y: view.coverY

            Image {
                id: cover
                anchors.fill: parent
                source: root.artUrl
                // object-fit: contain — never crop the artwork.
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                visible: status === Image.Ready
            }

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.45)
                height: width
                source: "media-optical-audio"
                visible: cover.status !== Image.Ready
                opacity: 0.45
            }
        }

        // ── metadata + transport ──
        ColumnLayout {
            id: info
            spacing: Kirigami.Units.smallSpacing / 2

            x: view.infoX
            y: view.infoY
            width: view.infoW
            height: view.infoH

            readonly property bool showSubtitle: height > titleSize + subtitleSize + Kirigami.Units.gridUnit * 2
            readonly property bool showSeek: height > Kirigami.Units.gridUnit * 2.2
            readonly property bool showTimes: Plasmoid.configuration.showTimes
                && width > Kirigami.Units.gridUnit * 12 && showSeek
            readonly property int ctrlSize: Math.round(Math.max(
                Kirigami.Units.iconSizes.small,
                Math.min(Kirigami.Units.iconSizes.large, height * 0.16)) * textScale)

            // Type scales with the widget instead of sitting at theme default,
            // clamped so it stays readable when tiny and sane when huge.
            readonly property real textScale: root.cfgNum(Plasmoid.configuration.textScale, 100) / 100
            readonly property int titleSize:
                Math.round(Math.max(11, Math.min(height * 0.11, 44)) * textScale)
            readonly property int subtitleSize: Math.round(Math.max(10, titleSize * 0.62))
            readonly property int metaSize: Math.round(Math.max(9, titleSize * 0.48))

            // Centres the text block when there is no strip to fill the gap.
            Item {
                Layout.fillHeight: true
                Layout.preferredHeight: 0
                visible: root.visualiserMode !== "strip"
            }

            MarqueeText {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                text: root.hasPlayer
                    ? (root.trackTitle !== "" ? root.trackTitle : i18n("Unknown track"))
                    : (root.pinned ? i18n("Waiting for %1", root.pinnedId) : i18n("Nothing playing"))
                font.weight: Font.DemiBold
                font.pixelSize: info.titleSize
                scrolling: Plasmoid.configuration.scrollTitle
            }

            MarqueeText {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                visible: info.showSubtitle && text !== ""
                opacity: 0.75
                text: {
                    var bits = [root.trackArtist];
                    if (Plasmoid.configuration.showAlbum && root.trackAlbum !== "") {
                        bits.push(root.trackAlbum);
                    }
                    return bits.filter(function (s) { return s && s !== ""; }).join("  ·  ");
                }
                font.pixelSize: info.subtitleSize
                scrolling: Plasmoid.configuration.scrollTitle
            }

            // Strip visualiser fills the slack; otherwise this is plain spacing.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0

                Visualiser {
                    anchors.fill: parent
                    anchors.topMargin: Kirigami.Units.smallSpacing / 2
                    visible: root.visualiserMode === "strip" && parent.height > 4
                    levels: cava.levels
                    baseColour: view.accent
                    peakColour: Qt.lighter(view.accent, 1.5)
                    barThickness: root.cfgNum(Plasmoid.configuration.barThickness, 4)
                    barGap: root.cfgNum(Plasmoid.configuration.barGap, 2)
                    mirrored: Plasmoid.configuration.mirrorBars
                    smoothing: Math.round(1000 / cava.effectiveFps * 1.35)
                    opacity: 0.9
                }

                // Silent failure is the enemy here: say so rather than sitting
                // at a flat 1px line and looking like a styling choice.
                PC3.Label {
                    anchors.centerIn: parent
                    visible: root.visualiserOn && root.isPlaying && !cava.receiving
                        && parent.height > Kirigami.Units.gridUnit
                    // Report which layer failed rather than just sitting flat.
                    text: cava.pathReady
                        ? i18n("No cava data — %1", cava.displayPath)
                        : i18n("Cava path unresolved (%1)", cava.resolvedVia)
                    opacity: 0.5
                    font.pixelSize: info.metaSize
                    elide: Text.ElideMiddle
                    width: parent.width
                }
            }

            // Transport row. In row mode the seek bar shares this line.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PC3.ToolButton {
                    icon.name: "media-playlist-shuffle"
                    icon.width: info.ctrlSize; icon.height: info.ctrlSize
                    implicitWidth: info.ctrlSize + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    visible: info.width > Kirigami.Units.gridUnit * 16 && root.hasPlayer
                    checked: root.hasPlayer && root.player.shuffle === Mpris.ShuffleStatus.On
                    display: PC3.ToolButton.IconOnly
                    onClicked: root.toggleShuffle()
                    PC3.ToolTip.text: i18n("Shuffle")
                    PC3.ToolTip.visible: hovered
                    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                PC3.ToolButton {
                    icon.name: "media-skip-backward"
                    icon.width: info.ctrlSize; icon.height: info.ctrlSize
                    implicitWidth: info.ctrlSize + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    enabled: root.hasPlayer && root.player.canGoPrevious
                    display: PC3.ToolButton.IconOnly
                    onClicked: root.previous()
                }

                PC3.ToolButton {
                    icon.name: root.isPlaying ? "media-playback-pause" : "media-playback-start"
                    icon.width: Math.round(info.ctrlSize * 1.2)
                    icon.height: icon.width
                    implicitWidth: Math.round(info.ctrlSize * 1.2) + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    enabled: root.hasPlayer
                    display: PC3.ToolButton.IconOnly
                    onClicked: root.togglePlay()
                }

                PC3.ToolButton {
                    icon.name: "media-skip-forward"
                    icon.width: info.ctrlSize; icon.height: info.ctrlSize
                    implicitWidth: info.ctrlSize + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    enabled: root.hasPlayer && root.player.canGoNext
                    display: PC3.ToolButton.IconOnly
                    onClicked: root.next()
                }

                PC3.ToolButton {
                    icon.name: root.hasPlayer && root.player.loopStatus === Mpris.LoopStatus.Track
                        ? "media-playlist-repeat-song" : "media-playlist-repeat"
                    icon.width: info.ctrlSize; icon.height: info.ctrlSize
                    implicitWidth: info.ctrlSize + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    visible: info.width > Kirigami.Units.gridUnit * 16 && root.hasPlayer
                    checked: root.hasPlayer && root.player.loopStatus !== Mpris.LoopStatus.None
                    display: PC3.ToolButton.IconOnly
                    onClicked: root.cycleLoop()
                    PC3.ToolTip.text: i18n("Repeat")
                    PC3.ToolTip.visible: hovered
                    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                SeekBar {
                    id: inlineSeek
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    visible: view.rowMode && info.showSeek
                    accent: view.accent
                    position: root.hasPlayer ? root.player.position : 0
                    length: root.hasPlayer ? root.player.length : 0
                    seekable: root.hasPlayer && root.player.canSeek
                    onSeekRequested: (us) => root.seekTo(us)
                }

                PC3.Label {
                    visible: view.rowMode && info.showTimes
                    opacity: 0.7
                    font.pixelSize: info.metaSize
                    text: root.hasPlayer
                        ? root.formatTime(root.player.position) + " / " + root.formatTime(root.player.length)
                        : ""
                }
            }

            // Column mode gets its own seek row underneath.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing / 2
                visible: !view.rowMode && info.showSeek
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    visible: info.showTimes
                    opacity: 0.7
                    font.pixelSize: info.metaSize
                    text: root.hasPlayer ? root.formatTime(root.player.position) : "0:00"
                }

                SeekBar {
                    Layout.fillWidth: true
                    accent: view.accent
                    position: root.hasPlayer ? root.player.position : 0
                    length: root.hasPlayer ? root.player.length : 0
                    seekable: root.hasPlayer && root.player.canSeek
                    onSeekRequested: (us) => root.seekTo(us)
                }

                PC3.Label {
                    visible: info.showTimes
                    opacity: 0.7
                    font.pixelSize: info.metaSize
                    text: root.hasPlayer ? root.formatTime(root.player.length) : "0:00"
                }
            }
        }

        // Wheel = volume, middle click = play/pause. Sits behind the controls
        // so buttons still get their clicks.
        MouseArea {
            anchors.fill: parent
            z: -2
            acceptedButtons: Qt.MiddleButton
            onClicked: root.togglePlay()
            onWheel: function (wheel) {
                if (!Plasmoid.configuration.volumeOnWheel) return;
                root.nudgeVolume(wheel.angleDelta.y > 0 ? 0.03 : -0.03);
            }
        }

        // Quiet hint when nothing is on.
        PC3.Label {
            anchors.centerIn: parent
            visible: !root.hasPlayer
            opacity: 0.6
            horizontalAlignment: Text.AlignHCenter
            text: root.pinned ? i18n("Waiting for %1", root.pinnedId) : i18n("Nothing playing")
        }
    }

    // ───────────────────────────────────────────── compact representation ──

    compactRepresentation: MouseArea {
        id: compact

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        implicitWidth: vertical ? -1 : Math.round(height * (root.visualiserOn ? 2.2 : 1))
        implicitHeight: vertical ? Math.round(width) : -1

        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true

        onClicked: function (mouse) {
            if (mouse.button === Qt.MiddleButton) root.togglePlay();
            else root.expanded = !root.expanded;
        }
        onWheel: function (wheel) {
            if (!Plasmoid.configuration.volumeOnWheel) return;
            root.nudgeVolume(wheel.angleDelta.y > 0 ? 0.03 : -0.03);
        }

        Row {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            height: parent.height

            Item {
                width: parent.height
                height: parent.height

                Image {
                    id: compactCover
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing / 2
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Kirigami.Icon {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing / 2
                    source: root.isPlaying ? "media-playback-start" : "media-playback-pause"
                    visible: compactCover.status !== Image.Ready
                }
            }

            Visualiser {
                width: Math.round(compact.height * 1.2)
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                visible: root.visualiserOn && !compact.vertical
                levels: cava.levels
                baseColour: Kirigami.Theme.highlightColor
                barThickness: Math.max(2, root.cfgNum(Plasmoid.configuration.barThickness, 4) - 1)
                barGap: 1
            }
        }
    }
}
