import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    property string stateError: ""
    // Agents Orca has a status row for, from `orca worktree ps`:
    // [{group, state, agentType, paneKey, place, since}].
    property var statusAgents: []
    // worktreeId -> display place ("repo · worktree"), from `orca worktree ps`.
    property var worktreePlaces: ({})
    // paneKey -> {agentIdentity, worktreeId, worktreePath, lastOutputAt, title}
    // for every live terminal, from `orca terminal list`.
    property var paneInfo: ({})
    // Panes with a Hermes process running in them, from hermes_panes.py.
    property var hermesPanes: []
    // One entry per agent for the desktop list: {group, state, agentType, paneKey, place, since}.
    readonly property var agentList: root.mergeAgents(root.statusAgents, root.paneInfo, root.hermesPanes, root.now)
    readonly property int runningCount: root.countGroup("running")
    readonly property int waitingCount: root.countGroup("waiting")
    readonly property int idleCount: root.countGroup("idle")
    // paneKey -> spinner text ("Churning…") read off each working agent's screen.
    property var activity: ({})
    // paneKey -> terminal handle, from `orca terminal list`.
    property var paneHandles: ({})
    // paneKey -> Orca tab title, with the agent's spinner glyph removed.
    property var paneTitles: ({})
    // paneKey -> running Claude sub-agents: [{id, description, agentType, model, tool, startedAt}].
    property var subagents: ({})
    readonly property int subagentCount: Object.keys(root.subagents)
        .reduce(function(sum, pane) { return sum + root.subagents[pane].length }, 0)
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
                var list = []
                var places = {}
                for (var w = 0; w < worktrees.length; ++w) {
                    var wt = worktrees[w]
                    // Worktrees are usually named after their branch, so
                    // only add the name when it isn't the main checkout.
                    var place = wt.repo || wt.displayName || ""
                    if (!wt.isMainWorktree && wt.displayName && wt.displayName !== place) {
                        place += " · " + wt.displayName
                    }
                    places[wt.worktreeId] = place
                    var agents = wt.agents || []
                    for (var a = 0; a < agents.length; ++a) {
                        var agent = agents[a]
                        var st = "" + agent.state
                        var group = ""
                        // Orca agent states: working, waiting, monitoring,
                        // idle, done, blocked, failed, stopped, unverifiable.
                        if (st === "working" || st === "monitoring") {
                            group = "running"
                        } else if (st === "waiting" || st === "blocked") {
                            group = "waiting"
                        } else if (st === "idle" || st === "done") {
                            group = "idle"
                        }
                        if (group === "") {
                            continue
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
                root.statusAgents = list
                root.worktreePlaces = places
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
        // Also the only state source for agents Orca has no status row for
        // (see mergeAgents), so poll as often as `worktree ps`.
        interval: 5000
        onNewData: function(sourceName, data) {
            if (data["exit code"] !== 0) {
                return
            }
            try {
                var payload = JSON.parse(data["stdout"] || "")
                var terminals = (payload.result || payload).terminals || []
                var handles = {}
                var titles = {}
                var info = {}
                for (var i = 0; i < terminals.length; ++i) {
                    var t = terminals[i]
                    var pane = t.tabId + ":" + t.leafId
                    handles[pane] = t.handle
                    info[pane] = {
                        agentIdentity: "" + (t.agentIdentity || ""),
                        worktreeId: t.worktreeId || "",
                        worktreePath: t.worktreePath || "",
                        lastOutputAt: t.lastOutputAt || 0,
                        title: "" + (t.title || "")
                    }
                    // "✳ Claude usage widget" -> "Claude usage widget". Titles
                    // that are just a path or command aren't worth showing.
                    var title = ("" + (t.title || "")).replace(/^[^\w~\/]+/, "").trim()
                    if (title !== "" && !/^[~\/]/.test(title)) {
                        titles[pane] = title
                    }
                }
                root.paneHandles = handles
                root.paneTitles = titles
                root.paneInfo = info
            } catch (e) {
            }
        }
    }

    // `orca worktree ps` leaves out sub-agents, so a helper reads them from
    // Claude's transcripts. Quoted because the repo path contains a space.
    readonly property string subagentScript:
        Qt.resolvedUrl("../code/subagents.py").toString().replace(/^file:\/\//, "")

    Plasma5Support.DataSource {
        id: subagentSource
        engine: "executable"
        connectedSources: ["python3 '" + root.subagentScript + "'"]
        interval: 5000
        onNewData: function(sourceName, data) {
            if (data["exit code"] !== 0) {
                return
            }
            try {
                root.subagents = JSON.parse(data["stdout"] || "{}")
            } catch (e) {
            }
        }
    }

    // Orca often has no status row for Hermes, and doesn't tag its TUI pane
    // with an agentIdentity, so a helper finds Hermes processes by pane.
    readonly property string hermesScript:
        Qt.resolvedUrl("../code/hermes_panes.py").toString().replace(/^file:\/\//, "")

    Plasma5Support.DataSource {
        id: hermesSource
        engine: "executable"
        connectedSources: ["python3 '" + root.hermesScript + "'"]
        interval: 5000
        onNewData: function(sourceName, data) {
            if (data["exit code"] !== 0) {
                return
            }
            try {
                root.hermesPanes = JSON.parse(data["stdout"] || "[]")
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

    // A pane with no status row counts as running while its output is this
    // fresh. Wider than the 5 s terminal poll so a busy pane never flickers idle.
    readonly property int outputRunningWindow: 10000

    // Group for an agent pane Orca has no status row for. The Hermes TUI marks
    // its tab title: ⚠ waiting on approval/input, ⏳ busy, ✓ idle. The TUI
    // redraws while idle, so only fall back to output recency without a marker.
    function untrackedGroup(info, now) {
        var marker = info.title.trim().charAt(0)
        if (marker === "\u26a0") {
            return "waiting"
        }
        if (marker === "\u23f3") {
            return "running"
        }
        if (marker === "\u2713") {
            return "idle"
        }
        return info.lastOutputAt && now - info.lastOutputAt < root.outputRunningWindow
               ? "running" : "idle"
    }

    // Orca's status rows plus agent panes it has no status row for: panes it
    // tagged with an agentIdentity, and panes running a Hermes process. Hermes
    // lands here because its hook events don't reach `worktree ps`.
    function mergeAgents(statusAgents, paneInfo, hermesPanes, now) {
        var list = statusAgents.slice()
        var types = {}
        for (var pane in paneInfo) {
            if (paneInfo[pane].agentIdentity) {
                types[pane] = paneInfo[pane].agentIdentity
            }
        }
        for (var h = 0; h < hermesPanes.length; ++h) {
            types[hermesPanes[h]] = "hermes"
        }
        for (var i = 0; i < list.length; ++i) {
            delete types[list[i].paneKey]
        }
        for (var key in types) {
            var info = paneInfo[key]
            // Not in `terminal list` (yet): no title or place to show.
            if (!info) {
                continue
            }
            var group = root.untrackedGroup(info, now)
            list.push({
                group: group,
                state: group === "running" ? "working" : group,
                agentType: types[key],
                paneKey: key,
                place: root.worktreePlaces[info.worktreeId]
                       || info.worktreePath.split("/").pop(),
                since: info.lastOutputAt
            })
        }
        // Agents needing attention first, then running, then idle;
        // newest state change first within each group.
        var rank = { waiting: 0, running: 1, idle: 2 }
        list.sort(function(x, y) {
            return rank[x.group] - rank[y.group] || y.since - x.since
        })
        return list
    }

    function countGroup(group) {
        return root.agentList.filter(function(entry) { return entry.group === group }).length
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
            count: root.runningCount
            pulse: root.runningCount > 0
            available: root.loaded
        }
        DotAndCount {
            dotColor: "#f9e2af"            // yellow - waiting on response
            count: root.waitingCount
            pulse: root.waitingCount > 0
            available: root.loaded
        }
        DotAndCount {
            dotColor: "#a6e3a1"            // green - done/idle
            count: root.idleCount
            available: root.loaded
        }
        DotAndCount {
            dotColor: "#cba6f7"            // mauve - sub-agents, only while some run
            count: root.subagentCount
            pulse: true
            visible: root.subagentCount > 0
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
        case "hermes":      return "\udb86\udc6e"    // md-horse_variant_fast (U+F186E)
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
                    { label: i18n("Running"), color: "#89b4fa", count: root.runningCount, pulse: root.runningCount > 0 },
                    { label: i18n("Waiting"), color: "#f9e2af", count: root.waitingCount, pulse: root.waitingCount > 0 },
                    { label: i18n("Idle"),    color: "#a6e3a1", count: root.idleCount,    pulse: false },
                    { label: i18n("Sub-agents"), color: "#cba6f7", count: root.subagentCount, pulse: root.subagentCount > 0 }
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

                        // Sub-agents this agent has running, one line each.
                        Repeater {
                            model: root.subagents[modelData.paneKey] || []
                            delegate: RowLayout {
                                id: subRow
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
                                spacing: Kirigami.Units.smallSpacing

                                Rectangle {
                                    implicitWidth: Kirigami.Units.smallSpacing * 1.5
                                    implicitHeight: implicitWidth
                                    radius: width / 2
                                    color: "#cba6f7"

                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutQuad }
                                    }
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: subRow.modelData.description || subRow.modelData.agentType || i18n("Sub-agent")
                                    elide: Text.ElideRight
                                    font: Kirigami.Theme.smallFont
                                }
                                PlasmaComponents.Label {
                                    text: [subRow.modelData.tool, subRow.modelData.model,
                                           root.ago(subRow.modelData.startedAt)]
                                          .filter(function(part) { return part }).join(" · ")
                                    opacity: 0.6
                                    font: Kirigami.Theme.smallFont
                                }
                            }
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
