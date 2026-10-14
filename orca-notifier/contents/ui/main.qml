import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // Last known agent counts, or -1 while we have no data yet.
    property int runningCount: -1
    property int waitingCount: -1
    property int idleCount: -1
    property string stateError: ""

    // Orca CLI shim. Used over `orca` on PATH because the shell shim is only
    // exported inside interactive Orca shells.
    readonly property string orcaCli: "\"$HOME/.config/orca/linux-orca-cli-shim/orca\""

    // True once at least one fetch succeeded; before that we show "…" so a
    // cold panel never misreads zeros as "no agents".
    property bool hasData: false

    // Shown while Orca is unreachable, once we have had a successful read.
    readonly property bool loaded: root.hasData
    // Round up negative edges so the panel never shows "-1".
    readonly property int shownRunning: Math.max(0, root.runningCount)
    readonly property int shownWaiting: Math.max(0, root.waitingCount)
    readonly property int shownIdle: Math.max(0, root.idleCount)

    // The executable engine re-issues all connectedSources on `interval`.
    // Keep the command in one string so a single source name is reused across
    // polling cycles.
    readonly property string orcaCommand:
        orcaCli + " worktree ps --limit 100 --json"

    Plasma5Support.DataSource {
        id: stateSource
        engine: "executable"
        connectedSources: [root.orcaCommand]
        interval: 3000
        onNewData: function(sourceName, data) {
            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""
            // The CLI shim prints JSON on stdout and app diagnostics on stderr.
            if (data["exit code"] !== 0) {
                root.stateError = stderr.trim()
                return
            }
            try {
                // Accept both bare output and the wrapped {result:{...}} form.
                var payload = JSON.parse(stdout)
                var result = payload.result || payload
                var worktrees = result.worktrees || []
                var running = 0, waiting = 0, idle = 0
                for (var w = 0; w < worktrees.length; ++w) {
                    var agents = worktrees[w].agents || []
                    for (var a = 0; a < agents.length; ++a) {
                        var st = "" + agents[a].state
                        // Orca agent states: working, waiting, monitoring,
                        // idle, done, blocked, failed, stopped, unverifiable.
                        if (st === "working" || st === "monitoring") {
                            ++running
                        } else if (st === "waiting" || st === "blocked") {
                            ++waiting
                        } else if (st === "idle" || st === "done") {
                            ++idle
                        }
                    }
                }
                root.runningCount = running
                root.waitingCount = waiting
                root.idleCount = idle
                root.stateError = ""
                root.hasData = true
            } catch (e) {
                root.stateError = "Could not parse orca output"
            }
        }
    }

    // Convenience so a single dot/total pair can be reused.
    component DotAndCount: RowLayout {
        id: pair
        // blue (running), yellow (waiting), green (done)
        property color dotColor: "#89b4fa"
        property bool pulse: false
        property int count: 0
        property bool available: true

        spacing: Math.round(0.5 * Kirigami.Units.smallSpacing)

        Rectangle {
            implicitWidth: Kirigami.Units.smallSpacing * 3
            implicitHeight: Kirigami.Units.smallSpacing * 3
            radius: width / 2
            color: pair.dotColor
            visible: pair.available
            opacity: 0.95

            SequentialAnimation on opacity {
                running: pair.pulse
                loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 0.95; duration: 700; easing.type: Easing.InOutQuad }
            }
        }

        // Solid background so the dot color reads clearly on both dark and
        // light panels.
        Rectangle {
            implicitWidth: Math.max(countLabel.implicitWidth + Kirigami.Units.smallSpacing * 2, implicitHeight)
            implicitHeight: countLabel.implicitHeight
            color: pair.dotColor
            border.color: Kirigami.Theme.textColor
            border.width: 1
            radius: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                id: countLabel
                anchors.centerIn: parent
                text: pair.available ? pair.count : "…"
                // Dark text: the badge colors are all light pastels.
                color: "#1e1e2e"
                font.bold: true
            }
        }
    }

    compactRepresentation: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        DotAndCount {
            dotColor: "#89b4fa"            // blue  - in progress
            count: root.shownRunning
            pulse: root.runningCount > 0
            available: root.loaded
        }
        DotAndCount {
            dotColor: "#f9e2af"            // yellow - waiting on response
            count: root.shownWaiting
            pulse: root.waitingCount > 0
            available: root.loaded
        }
        DotAndCount {
            dotColor: "#a6e3a1"            // green - done/idle
            count: root.shownIdle
            available: root.loaded
        }
    }

    fullRepresentation: Item {
        // Simple centered summary in the popup.
        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Kirigami.Units.largeSpacing

                DotAndCount {
                    dotColor: "#89b4fa"
                    count: root.shownRunning
                    pulse: root.runningCount > 0
                    available: root.loaded
                }
                DotAndCount {
                    dotColor: "#f9e2af"
                    count: root.shownWaiting
                    pulse: root.waitingCount > 0
                    available: root.loaded
                }
                DotAndCount {
                    dotColor: "#a6e3a1"
                    count: root.shownIdle
                    available: root.loaded
                }
            }

            PlasmaComponents.Label {
                text: root.loaded
                      ? i18n("Orca agents")
                      : (root.stateError || i18n("Orca unavailable"))
                color: Kirigami.Theme.textColor
                opacity: 0.7
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}