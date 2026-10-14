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
    // One entry per agent for the desktop list: {group, state, agentType, paneKey, place, since}.
    property var agentList: []
    // paneKey -> spinner text ("Churning…") read off each working agent's screen.
    property var activity: ({})
    // paneKey -> terminal handle, from `orca terminal list`.
    property var paneHandles: ({})
    // paneKey -> Orca tab title, with the agent's spinner glyph removed.
    property var paneTitles: ({})
    readonly property var workingPanes: root.agentList
        .filter(function(entry) { return entry.group === "running" })
        .map(function(entry) { return entry.paneKey })
    // Refreshed on every poll so the "x min ago" labels keep moving.
    property double now: Date.now()

    // On the desktop show the full card directly; in a panel keep the dots.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
                             ? fullRepresentation : compactRepresentation

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
        interval: 5000
        onNewData: function(sourceName, data) {
            root.now = Date.now()
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
                var list = []
                for (var w = 0; w < worktrees.length; ++w) {
                    var wt = worktrees[w]
                    var agents = wt.agents || []
                    for (var a = 0; a < agents.length; ++a) {
                        var agent = agents[a]
                        var st = "" + agent.state
                        var group = ""
                        // Orca agent states: working, waiting, monitoring,
                        // idle, done, blocked, failed, stopped, unverifiable.
                        if (st === "working" || st === "monitoring") {
                            ++running
                            group = "running"
                        } else if (st === "waiting" || st === "blocked") {
                            ++waiting
                            group = "waiting"
                        } else if (st === "idle" || st === "done") {
                            ++idle
                            group = "idle"
                        }
                        if (group === "") {
                            continue
                        }
                        // Worktrees are usually named after their branch, so
                        // only add the name when it isn't the main checkout.
                        var place = wt.repo || wt.displayName || ""
                        if (!wt.isMainWorktree && wt.displayName && wt.displayName !== place) {
                            place += " · " + wt.displayName
                        }
                        list.push({
                            group: group,
                            state: st,
                            agentType: "" + (agent.agentType || ""),
                            paneKey: "" + (agent.paneKey || ""),
                            place: place,
                            since: agent.stateStartedAt || 0
                        })
                    }
                }
                // Agents needing attention first, then running, then idle;
                // newest state change first within each group.
                var rank = { waiting: 0, running: 1, idle: 2 }
                list.sort(function(x, y) {
                    return rank[x.group] - rank[y.group] || y.since - x.since
                })
                root.agentList = list
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

    // Maps agent panes to terminal handles and tab titles.
    Plasma5Support.DataSource {
        id: terminalListSource
        engine: "executable"
        connectedSources: [root.orcaCli + " terminal list --json"]
        // Titles rarely change, and each CLI call starts the full Orca binary.
        interval: 15000
        onNewData: function(sourceName, data) {
            if (data["exit code"] !== 0) {
                return
            }
            try {
                var payload = JSON.parse(data["stdout"] || "")
                var terminals = (payload.result || payload).terminals || []
                var handles = {}
                var titles = {}
                for (var i = 0; i < terminals.length; ++i) {
                    var t = terminals[i]
                    var pane = t.tabId + ":" + t.leafId
                    handles[pane] = t.handle
                    // "✳ Claude usage widget" -> "Claude usage widget". Titles
                    // that are just a path or command aren't worth showing.
                    var title = ("" + (t.title || "")).replace(/^[^\w~\/]+/, "").trim()
                    if (title !== "" && !/^[~\/]/.test(title)) {
                        titles[pane] = title
                    }
                }
                root.paneHandles = handles
                root.paneTitles = titles
            } catch (e) {
            }
        }
    }

    // Reads each working agent's rendered screen to pick up its spinner text.
    Plasma5Support.DataSource {
        id: screenSource
        engine: "executable"
        connectedSources: root.workingPanes
            .filter(function(pane) { return root.paneHandles[pane] !== undefined })
            .map(function(pane) { return root.screenCommand(pane) })
        interval: 5000
        onNewData: function(sourceName, data) {
            var pane = sourceName.split(" #")[1]
            var verb = ""
            try {
                var tail = JSON.parse(data["stdout"] || "").result.terminal.tail
                var lines = Array.isArray(tail) ? tail : ("" + tail).split("\n")
                for (var i = lines.length - 1; i >= 0 && verb === ""; --i) {
                    // e.g. "✶ Churning… (26s · ↓ 2.0k tokens)"
                    var m = lines[i].match(/^\s*\S\s+([A-Z][\w' -]*?(?:…|\.\.\.))/)
                    if (m) {
                        verb = m[1]
                    }
                }
            } catch (e) {
            }
            var next = Object.assign({}, root.activity)
            next[pane] = verb
            root.activity = next
        }
    }

    // The trailing "#pane" comment is ignored by the shell and lets
    // onNewData tell which agent a screen belongs to.
    function screenCommand(pane) {
        return root.orcaCli + " terminal read --terminal " + root.paneHandles[pane]
               + " --screen --limit 20 --json #" + pane
    }

    // Second line of a list row: what the agent is doing right now.
    function statusText(entry) {
        if (entry.group === "running") {
            return root.activity[entry.paneKey] || i18n("Working…")
        }
        if (entry.state === "blocked") {
            return i18n("Blocked")
        }
        if (entry.group === "waiting") {
            return i18n("Waiting for you")
        }
        return entry.state === "idle" ? i18n("Idle") : i18n("Done")
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

    // Dot color for a list group, matching the counters above.
    function groupColor(group) {
        return group === "running" ? "#89b4fa"
             : group === "waiting" ? "#f9e2af"
             : "#a6e3a1"
    }

    // Icon font for the agent glyphs; rows fall back to a plain dot without it.
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property bool hasIconFont: Qt.fontFamilies().indexOf(iconFont) !== -1

    // Nerd Font glyph per Orca agentType.
    function agentGlyph(type) {
        switch (type) {
        case "claude":      return "\uec82"    // cod-claude
        case "codex":
        case "openai":      return "\uec81"    // cod-openai
        case "gemini":      return "\uec21"    // cod-sparkle_filled
        case "antigravity": return "\ue7f0"    // dev-google
        case "copilot":     return "\uec1e"    // cod-copilot
        case "cursor":      return "\uec5c"    // cod-cursor
        case "opencode":    return "\uebc4"    // cod-terminal_cmd
        default:            return "\uec20"    // cod-robot
        }
    }

    function ago(ms) {
        if (!ms) {
            return ""
        }
        var mins = Math.max(0, Math.floor((root.now - ms) / 60000))
        if (mins < 1) {
            return i18n("just now")
        }
        if (mins < 60) {
            return i18n("%1 min ago", mins)
        }
        var hours = Math.floor(mins / 60)
        if (hours < 24) {
            return i18n("%1 h ago", hours)
        }
        return i18n("%1 d ago", Math.floor(hours / 24))
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 20
        spacing: Kirigami.Units.smallSpacing

        // Labelled counters.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.largeSpacing * 2

            Repeater {
                model: [
                    { label: i18n("Running"), color: "#89b4fa", count: root.shownRunning, pulse: root.runningCount > 0 },
                    { label: i18n("Waiting"), color: "#f9e2af", count: root.shownWaiting, pulse: root.waitingCount > 0 },
                    { label: i18n("Idle"),    color: "#a6e3a1", count: root.shownIdle,    pulse: false }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    spacing: 0

                    DotAndCount {
                        Layout.alignment: Qt.AlignHCenter
                        dotColor: modelData.color
                        count: modelData.count
                        pulse: modelData.pulse
                        available: root.loaded
                    }
                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData.label
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                    }
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.agentList.length > 0

            ListView {
                model: root.agentList
                clip: true
                spacing: Kirigami.Units.largeSpacing * 1.5

                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width
                    spacing: Kirigami.Units.smallSpacing

                    // Agent icon, tinted with the state color.
                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 1.25
                        visible: root.hasIconFont
                        text: root.agentGlyph(modelData.agentType)
                        font.family: root.iconFont
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                        color: root.groupColor(modelData.group)
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        visible: !root.hasIconFont
                        implicitWidth: Kirigami.Units.smallSpacing * 2
                        implicitHeight: implicitWidth
                        radius: width / 2
                        color: root.groupColor(modelData.group)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: root.paneTitles[modelData.paneKey] || modelData.place
                                elide: Text.ElideRight
                                font.weight: Font.DemiBold
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.05
                            }
                            PlasmaComponents.Label {
                                // The repo moves here once the tab title takes the bold line.
                                text: (root.paneTitles[modelData.paneKey] ? modelData.place + " · " : "")
                                      + root.ago(modelData.since)
                                opacity: 0.6
                                font: Kirigami.Theme.smallFont
                            }
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: root.statusText(modelData)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: modelData.group === "idle"
                                   ? Kirigami.Theme.textColor : root.groupColor(modelData.group)
                            opacity: modelData.group === "idle" ? 0.6 : 0.9
                            font: Kirigami.Theme.smallFont
                        }
                    }
                }
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.fillHeight: root.agentList.length === 0
            visible: root.agentList.length === 0 || !root.loaded || root.stateError !== ""
            text: !root.loaded
                  ? (root.stateError || i18n("Orca unavailable"))
                  : root.stateError !== "" ? root.stateError
                  : i18n("No agents")
            opacity: 0.7
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }
}
