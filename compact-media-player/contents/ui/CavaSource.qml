/*
 * CavaSource.qml
 *
 * Reads the newest cava frame using Plasma5Support's executable engine.
 *
 * Why not XMLHttpRequest: QML's XHR will not read file:// URLs from inside a
 * plasmoid. The QML document has no file: base URL, so the read is treated as
 * cross-origin and comes back as an empty string with no error raised — which
 * looks identical to "the audio pipeline is broken". The executable engine has
 * no such restriction and is the same mechanism other plasmoids on this
 * machine already use successfully.
 *
 * The cost is that the engine only delivers data when the process exits, so
 * this polls at ~20fps rather than 60. The Visualiser interpolates between
 * frames, so the result still reads as smooth.
 *
 * Values arrive 0..100 (ascii_max_range in the cava config).
 */
import QtQuick
import QtCore
import org.kde.plasma.plasma5support as P5Support

Item {
    id: src

    // Polls per second. The engine forks a process per poll, so this is
    // deliberately capped well below a display refresh rate.
    property int fps: 20
    readonly property int effectiveFps: Math.max(4, Math.min(30, fps))

    property bool active: false

    property var levels: []
    property var rawLevels: []

    property bool receiving: false

    // Surfaced so the UI can report which layer failed.
    property string runtimeDir: ""
    property string resolvedVia: "unresolved"
    property string lastError: ""

    readonly property bool pathReady: runtimeDir !== "" && runtimeDir !== "/"
    readonly property string framePath: pathReady ? runtimeDir + "/cava-plasmoid.raw" : ""
    readonly property string displayPath: pathReady ? framePath : "<path unresolved>"
    // No shell metacharacters, so this runs directly without a shell.
    readonly property string readCommand: pathReady ? "cat " + framePath : ""

    property int _misses: 0
    property bool _pending: false
    property double _sentAt: 0

    onActiveChanged: if (!active) src.clear()

    Component.onCompleted: {
        clear();
        resolvePath();
    }

    function clear() {
        // 64 matches the cava config; consumers resample to their own width.
        var z = new Array(64);
        for (var i = 0; i < z.length; ++i) z[i] = 0;
        levels = z;
        receiving = false;
        _misses = 0;
    }

    // ── path resolution ──────────────────────────────────────────────────

    function resolvePath() {
        var viaQt = "";
        try {
            viaQt = String(StandardPaths.writableLocation(StandardPaths.RuntimeLocation));
        } catch (e) {
            viaQt = "";
        }
        viaQt = viaQt.replace(/^file:\/\//, "");

        if (viaQt !== "" && viaQt !== "/" && viaQt !== "undefined") {
            src.runtimeDir = viaQt;
            src.resolvedVia = "StandardPaths";
            return;
        }

        src.resolvedVia = "resolving via shell";
        resolver.connectSource('printf %s "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"');
    }

    P5Support.DataSource {
        id: resolver
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source);
            var out = data && data["stdout"] ? String(data["stdout"]).trim() : "";
            if (out !== "" && out !== "/") {
                src.runtimeDir = out;
                src.resolvedVia = "shell";
                src.lastError = "";
            } else {
                src.resolvedVia = "failed";
                src.lastError = "could not resolve XDG_RUNTIME_DIR";
            }
        }
    }

    // ── frame reading ────────────────────────────────────────────────────

    P5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source);
            src._pending = false;

            var code = data ? data["exit code"] : -1;
            if (code !== 0 && code !== undefined) {
                var err = data && data["stderr"] ? String(data["stderr"]).trim() : "";
                src.lastError = err !== "" ? err : ("read exited " + code);
                src.miss();
                return;
            }
            src.parse(data && data["stdout"] ? String(data["stdout"]) : "");
        }
    }

    function poll() {
        if (!pathReady) return;

        // A process that never returns must not wedge the poller.
        if (_pending) {
            if (Date.now() - _sentAt > 1500) {
                reader.disconnectSource(readCommand);
                _pending = false;
                lastError = "read timed out";
                miss();
            }
            return;
        }

        _pending = true;
        _sentAt = Date.now();
        reader.connectSource(readCommand);
    }

    function miss() {
        _misses++;
        if (_misses > 4) clear();
    }

    function parse(text) {
        if (!text || text.length === 0) {
            if (_misses === 0) src.lastError = "frame file read returned nothing";
            miss();
            return;
        }
        var parts = text.trim().split(";");
        var out = [];
        for (var i = 0; i < parts.length; ++i) {
            var v = parseInt(parts[i], 10);
            if (!isNaN(v)) out.push(v);
        }
        if (out.length === 0) {
            src.lastError = "no numbers in frame";
            miss();
            return;
        }
        _misses = 0;
        lastError = "";
        receiving = true;
        rawLevels = out;
        levels = out;
    }

    Timer {
        interval: Math.round(1000 / src.effectiveFps)
        repeat: true
        running: src.active && src.pathReady
        triggeredOnStart: true
        onTriggered: src.poll()
    }
}
