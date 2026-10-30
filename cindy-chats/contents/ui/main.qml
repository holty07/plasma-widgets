import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support

import "../code/usage.js" as Usage

PlasmoidItem {
    id: root

    // ------------------------------------------------------------------ state

    readonly property var stateOrder: ["working", "waiting", "idle"]

    // Catppuccin Mocha, same running / waiting / idle palette as the orca widget
    readonly property var stateColour: ({
        "working": "#89b4fa",   // blue  - in progress
        "waiting": "#f9e2af",   // yellow - waiting on you / blocked
        "idle":    "#a6e3a1",   // green
    })

    readonly property var stateLabel: ({
        "working": i18n("Working"),
        "waiting": i18n("Waiting for you"),
        "idle":    i18n("Idle")
    })

    property var counts: ({ working: 0, waiting: 0, idle: 0 })
    property var chatList: []
    property string summary: i18n("Waiting for Cindy…")
    property string errorText: ""
    property bool loaded: false

    readonly property int runningCount: counts.working
    readonly property int waitingCount: counts.waiting
    readonly property int idleCount: counts.idle

    Plasmoid.status: (plasmoid.configuration.attentionOnWaiting && counts.waiting > 0)
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("Cindy Chats")
    toolTipSubText: errorText !== "" ? errorText : summary

    // Full card on the desktop, compact dots in the panel — like the orca widget.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
                        ? fullRepresentation : compactRepresentation

    // ------------------------------------------------------------------ data

    // Path to the Cindy SQLite database
    readonly property string cindyDbPath: plasmoid.configuration.cindyDbPath || "/home/holty/.config/CindyGlobal/cindy-cmvsyhcia10i9yw01rst1i34s.db"

    // Usage tracker state
    property var usageSnapshot: Usage.emptySnapshot()
    property real nowTs: Date.now() / 1000
    property var _usageAppSnap: null
    property var _usageHookSnap: null
    property var _usageAgySnap: null
    property var _usageCindySnap: null
    property int _usagePending: 0

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        signal finished(int code, string stdout, string stderr)

        onNewData: function(source, data) {
            disconnectSource(source)
            finished(data["exit code"], data.stdout, data.stderr)
        }

        function run(cmd) {
            connectSource(cmd)
        }
    }

    Connections {
        target: executable
        function onFinished(code, stdout, stderr) {
            if (code !== 0) {
                root.errorText = (stderr && stderr.trim().length > 0)
                    ? stderr.trim().split("\n")[0]
                    : i18n("Cindy database not found or query failed")
                root.loaded = true
                root.applyChats([])
                return
            }
            root.errorText = ""
            root.applyChats(root.parseChats(stdout))
        }
    }

    // Usage tracker DataSources
    // Cindy's own copy of the Claude rate limits, refreshed from the API
    // response headers on every Claude Code turn Cindy runs.
    Plasma5Support.DataSource {
        id: cindyUsage
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            var text = (data && data["stdout"]) ? data["stdout"] : ""
            root._usageCindySnap = text ? Usage.fromCindyDb(text) : null
            root._maybeCombineUsage()
        }
    }

    Plasma5Support.DataSource {
        id: catAppUsage
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            var text = (data && data["stdout"]) ? data["stdout"] : ""
            root._usageAppSnap = text ? Usage.fromPlanUsageHistory(text) : null
            root._maybeCombineUsage()
        }
    }

    Plasma5Support.DataSource {
        id: catHook
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            var text = (data && data["stdout"]) ? data["stdout"] : ""
            root._usageHookSnap = text ? Usage.fromHookPayload(text) : null
            root._maybeCombineUsage()
        }
    }

    Plasma5Support.DataSource {
        id: catAgyHook
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            var text = (data && data["stdout"]) ? data["stdout"] : ""
            root._usageAgySnap = text ? Usage.fromAgyPayload(text) : null
            root._maybeCombineUsage()
        }
    }

    Plasma5Support.DataSource {
        id: catFallback
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            var text = (data && data["stdout"]) ? data["stdout"] : ""
            var snap = text ? Usage.fromClaudeJson(text) : null
            if (snap) {
                root.usageSnapshot = snap
            }
        }
    }

    Timer {
        interval: Math.max(1, plasmoid.configuration.pollInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.nowTs = Date.now() / 1000
    }

    function refresh() {
        // Query active sessions with their timestamps
        // State logic:
        // - working: active_turn_started_at > last_turn_ended_at (or last_turn_ended_at IS NULL)
        // - waiting: user_send_at > last_turn_ended_at (or last_turn_ended_at IS NULL) AND NOT working
        // - idle: otherwise (ready for user input)
        var cmd = "sqlite3 -json '" + root.cindyDbPath + "' "
            + "\"SELECT id, title, working_dir, model, agent_kind, "
            + "       user_send_at, active_turn_started_at, last_turn_ended_at "
            + "FROM sessions "
            + "WHERE status = 'active' "
            + "ORDER BY updated_at DESC;\""
        executable.run(cmd)

        // Also refresh usage data
        root.refreshUsage()
    }

    function refreshUsage() {
        _usageAppSnap = null
        _usageHookSnap = null
        _usageAgySnap = null
        _usageCindySnap = null
        _usagePending = 4
        cindyUsage.connectSource("sqlite3 -readonly -json '" + root.cindyDbPath + "' "
            + "\"SELECT snapshot FROM account_usage_snapshots WHERE agent_kind = 'claude-code';\"")
        catAppUsage.connectSource("cat ~/.config/Claude/plan-usage-history.json 2>/dev/null")
        catHook.connectSource("cat ~/.claude/plasma-usage-status.json 2>/dev/null")
        catAgyHook.connectSource("cat ~/.gemini/antigravity-cli/plasma-agy-status.json 2>/dev/null")
    }

    function _maybeCombineUsage() {
        _usagePending -= 1
        if (_usagePending > 0) return

        var now = Date.now() / 1000
        var hookAvail = _usageHookSnap && _usageHookSnap.available
        var agyAvail = _usageAgySnap && _usageAgySnap.available
        var hookAge = (hookAvail && _usageHookSnap.receivedAt !== null) ? (now - _usageHookSnap.receivedAt) : Infinity
        var hookFresh = hookAvail && hookAge < 15 * 60
        var hookUsableForDetail = hookAvail && hookAge < 6 * 3600

        // Claude limits are account-wide, so whichever source saw them most
        // recently wins: Cindy's DB, the statusLine hook, or the desktop app cache.
        var claudeSnaps = [_usageCindySnap, _usageHookSnap, _usageAppSnap].filter(function (s) {
            return s && s.available
        })
        claudeSnaps.sort(function (a, b) { return (b.receivedAt || 0) - (a.receivedAt || 0) })

        var chosen = null
        if (claudeSnaps.length > 0) {
            chosen = Object.assign({}, claudeSnaps[0])
            // Merge hook details (cost, context, model) only if hook is reasonably fresh
            if (hookUsableForDetail && chosen.source !== "hook") {
                chosen.contextPct = _usageHookSnap.contextPct
                chosen.contextSize = _usageHookSnap.contextSize
                chosen.costUsd = _usageHookSnap.costUsd
                chosen.durationMs = _usageHookSnap.durationMs
                chosen.model = _usageHookSnap.model
                chosen.effort = _usageHookSnap.effort
                chosen.project = _usageHookSnap.project
            }
        }

        // Merge antigravity data if available
        if (agyAvail && chosen) {
            chosen.agySessionPct = _usageAgySnap.agySessionPct
            chosen.agySessionResetsAt = _usageAgySnap.agySessionResetsAt
            chosen.agyWeeklyPct = _usageAgySnap.agyWeeklyPct
            chosen.agyWeeklyResetsAt = _usageAgySnap.agyWeeklyResetsAt
            chosen.agyContextPct = _usageAgySnap.agyContextPct
            chosen.agyContextSize = _usageAgySnap.agyContextSize
            chosen.agyModel = _usageAgySnap.agyModel
            chosen.agyEffort = _usageAgySnap.agyEffort
            chosen.agyProject = _usageAgySnap.agyProject
            chosen.agyPlanTier = _usageAgySnap.agyPlanTier
            chosen.agyAgentState = _usageAgySnap.agyAgentState
        } else if (agyAvail && !chosen) {
            chosen = _usageAgySnap
        }

        if (chosen) {
            root.usageSnapshot = chosen
        } else {
            catFallback.connectSource("cat ~/.claude.json 2>/dev/null")
        }
    }

    function resetLabel(resetsAt) {
        if (resetsAt === null || resetsAt === undefined) return ""
        var remain = resetsAt - nowTs
        if (remain <= 0) return "resetting…"
        return Usage.fmtDuration(remain) + " left"
    }

    // sqlite3 -json returns an array of objects
    function parseChats(stdout) {
        var payload
        try {
            payload = JSON.parse(stdout)
        } catch (e) {
            root.errorText = i18n("Could not parse database output")
            return []
        }
        if (!Array.isArray(payload)) {
            return []
        }
        return payload
    }

    function normalise(state) {
        return stateOrder.indexOf(state) >= 0 ? state : "idle"
    }

    function groupOf(state) {
        var s = normalise(state)
        if (s === "working") return "running"
        if (s === "waiting") return "waiting"
        return "idle"
    }

    function placeOf(chat) {
        var where = chat.working_dir || ""
        var parts = where.split("/")
        return parts[parts.length - 1] || where || i18n("Unknown")
    }

    function agentGlyph(type) {
        switch (type) {
        case "claude":
        case "cc":        return "\uec82"    // cod-claude
        case "codex":
        case "openai":    return "\uec81"    // cod-openai
        case "gemini":    return "\uec21"    // cod-sparkle_filled
        case "hermes":    return "\udb86\udc6e"  // md-horse_variant_fast
        case "copilot":   return "\uec1e"    // cod-copilot
        case "cursor":    return "\uec5c"    // cod-cursor
        case "opencode":  return "\uebc4"    // cod-terminal_cmd
        case "pi":        return "\uec21"    // cod-sparkle_filled (Pi uses sparkle)
        default:          return "\uec20"    // cod-robot
        }
    }

    function ago(ms) {
        if (!ms || ms === 0) {
            return ""
        }
        var now = Date.now()
        var mins = Math.max(0, Math.floor((now - ms) / 60000))
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

    function applyChats(list) {
        var tally = { working: 0, waiting: 0, idle: 0 }
        var entries = []

        for (var i = 0; i < list.length; i++) {
            var chat = list[i]

            // Determine state from timestamps (all in milliseconds since epoch)
            var userSendAt = chat.user_send_at || 0
            var turnStartedAt = chat.active_turn_started_at || 0
            var turnEndedAt = chat.last_turn_ended_at || 0

            var isWorking = turnStartedAt > 0 && (turnEndedAt === 0 || turnStartedAt > turnEndedAt)
            var isWaiting = userSendAt > 0 && (turnEndedAt === 0 || userSendAt > turnEndedAt) && !isWorking

            var state = isWorking ? "working" : (isWaiting ? "waiting" : "idle")
            tally[state]++

            // Agent kind from agent_kind column (cc, pi, etc.)
            var agentKind = "" + (chat.agent_kind || "cc")

            entries.push({
                group: groupOf(state),
                state: state,
                agentType: agentKind,
                paneKey: chat.id,
                place: placeOf(chat),
                since: isWorking ? turnStartedAt : (isWaiting ? userSendAt : turnEndedAt),
                title: chat.title || i18n("Untitled chat"),
                model: chat.model || ""
            })
        }

        // Agents needing attention first, then working, then idle;
        // newest state change first within each group.
        var rank = { waiting: 0, running: 1, idle: 2 }
        entries.sort(function(x, y) {
            return rank[x.group] - rank[y.group] || y.since - x.since
        })

        counts = tally
        chatList = entries
        loaded = true

        var parts = []
        if (tally.working > 0) {
            parts.push(tally.working + " " + i18n("working"))
        }
        if (tally.waiting > 0) {
            parts.push(tally.waiting + " " + i18n("waiting"))
        }
        if (tally.idle > 0) {
            parts.push(tally.idle + " " + i18n("idle"))
        }
        summary = list.length === 0
            ? i18n("No active chats")
            : parts.join(", ")
    }

    // ------------------------------------------------------------------ panel

    compactRepresentation: MouseArea {
        id: compact

        readonly property int dotSize: Math.round(Kirigami.Units.gridUnit * 0.45)

        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: Kirigami.Units.iconSizes.small

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh()
            } else {
                root.expanded = !root.expanded
            }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            DotAndCount {
                dotColor: "#89b4fa"   // blue  - working
                count: root.runningCount
                pulse: root.runningCount > 0
                available: root.loaded
            }
            DotAndCount {
                dotColor: "#f9e2af"   // yellow - waiting
                count: root.waitingCount
                pulse: root.waitingCount > 0
                available: root.loaded
            }
            DotAndCount {
                dotColor: "#a6e3a1"   // green - idle
                count: root.idleCount
                pulse: false
                available: root.loaded && !plasmoid.configuration.hideIdle
            }

            PlasmaComponents.Label {
                visible: root.chatList.length === 0
                text: root.errorText !== "" ? "!" : "·"
                opacity: 0.6
                color: root.errorText !== "" ? root.stateColour["waiting"] : Kirigami.Theme.textColor
            }
        }
    }

    // ------------------------------------------------------------------ popup / desktop

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 26
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                PlasmaExtras.Heading {
                    level: 4
                    text: root.errorText !== "" ? i18n("Cindy unavailable") : root.summary
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Refresh")
                    onClicked: root.refresh()

                    PlasmaComponents.ToolTip { text: parent.text }
                }
            }
        }

        // No anchors here: Page positions contentItem below the header, and
        // anchoring it to the parent would pull it up underneath the header.
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            // Chat list section
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 10

                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: root.chatList.length === 0
                    iconName: root.errorText !== "" ? "dialog-warning" : "applications-internet"
                    text: root.errorText !== "" ? root.errorText : i18n("No active chats")
                    explanation: root.errorText !== ""
                        ? i18n("Check the database path in the widget settings.")
                        : i18n("Open a chat in Cindy and it will show up here.")
                }

                PlasmaComponents.ScrollView {
                    anchors.fill: parent
                    visible: root.chatList.length > 0

                    ListView {
                        model: root.chatList
                        clip: true
                        spacing: 0

                        delegate: PlasmaComponents.ItemDelegate {
                            width: ListView.view.width

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.largeSpacing

                                PlasmaComponents.Label {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.25
                                    visible: root.hasIconFont
                                    text: root.agentGlyph(modelData.agentType)
                                    font.family: root.iconFont
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                                    color: root.stateColour[root.normalise(modelData.state)]
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: Kirigami.Units.smallSpacing
                                    visible: !root.hasIconFont
                                    implicitWidth: Kirigami.Units.smallSpacing * 2
                                    implicitHeight: implicitWidth
                                    radius: width / 2
                                    color: root.stateColour[root.normalise(modelData.state)]
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    PlasmaComponents.Label {
                                        text: modelData.title
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        font.weight: Font.DemiBold
                                    }

                                    PlasmaComponents.Label {
                                        text: modelData.place + (modelData.model ? " · " + modelData.model : "")
                                        elide: Text.ElideRight
                                        opacity: 0.65
                                        font: Kirigami.Theme.smallFont
                                        Layout.fillWidth: true
                                    }
                                }

                                PlasmaComponents.Label {
                                    text: root.stateLabel[root.normalise(modelData.state)]
                                    font: Kirigami.Theme.smallFont
                                    color: root.stateColour[root.normalise(modelData.state)]
                                }
                            }
                        }
                    }
                }
            }

            // Usage tracker section
            UsageSection {
                Layout.fillWidth: true
                visible: root.usageSnapshot.available
            }
        }
    }

    // ------------------------------------------------------------------ shared components

    // One dot + count badge, matching orca's DotAndCount. Pulses while > 0,
    // shows "…" until the first successful poll.
    component DotAndCount: RowLayout {
        id: pair

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
                color: "#1e1e2e"
                font.bold: true
            }
        }
    }

    // Usage tracker section at bottom of full view
    component UsageSection: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            Kirigami.Heading {
                level: 5
                text: i18n("Usage Tracker")
                Layout.fillWidth: true
            }
        }

        // Claude Section
        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing / 2
            visible: usageSnapshot.sessionPct !== null || usageSnapshot.weeklyPct !== null

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label { text: "Claude"; font.bold: true }
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label { text: "Session (5h)"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                PlasmaComponents.Label {
                    text: usageSnapshot.sessionPct !== null ? usageSnapshot.sessionPct + "%" : "—"
                    font.bold: true
                    color: Usage.levelColor(usageSnapshot.sessionPct)
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: resetLabel(usageSnapshot.sessionResetsAt)
                    opacity: 0.6
                }
            }
            UsageBar {
                Layout.fillWidth: true
                percent: usageSnapshot.sessionPct
                barColor: Usage.levelColor(usageSnapshot.sessionPct)
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label { text: "Weekly (7d)"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                PlasmaComponents.Label {
                    text: usageSnapshot.weeklyPct !== null ? usageSnapshot.weeklyPct + "%" : "—"
                    font.bold: true
                    color: Usage.weeklyLevelColor(usageSnapshot.weeklyPct)
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: resetLabel(usageSnapshot.weeklyResetsAt)
                    opacity: 0.6
                }
            }
            UsageBar {
                Layout.fillWidth: true
                percent: usageSnapshot.weeklyPct
                barColor: Usage.weeklyLevelColor(usageSnapshot.weeklyPct)
            }
        }

        // Antigravity (agy) Section
        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing / 2
            visible: usageSnapshot.agySessionPct !== null || usageSnapshot.agyWeeklyPct !== null

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label { text: "antigravity (agy)"; font.bold: true }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: usageSnapshot.agyAgentState !== ""
                text: "State: " + usageSnapshot.agyAgentState
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }

            RowLayout {
                Layout.fillWidth: true
                visible: usageSnapshot.agySessionPct !== null
                PlasmaComponents.Label { text: "Gemini Weekly"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                PlasmaComponents.Label {
                    text: usageSnapshot.agySessionPct + "%"
                    font.bold: true
                    color: Usage.agyLevelColor(usageSnapshot.agySessionPct)
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: resetLabel(usageSnapshot.agySessionResetsAt)
                    opacity: 0.6
                }
            }
            UsageBar {
                Layout.fillWidth: true
                visible: usageSnapshot.agySessionPct !== null
                percent: usageSnapshot.agySessionPct
                barColor: Usage.agyLevelColor(usageSnapshot.agySessionPct)
            }

            RowLayout {
                Layout.fillWidth: true
                visible: usageSnapshot.agyWeeklyPct !== null
                PlasmaComponents.Label { text: "3p Weekly"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                PlasmaComponents.Label {
                    text: usageSnapshot.agyWeeklyPct + "%"
                    font.bold: true
                    color: Usage.agyWeeklyLevelColor(usageSnapshot.agyWeeklyPct)
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    text: resetLabel(usageSnapshot.agyWeeklyResetsAt)
                    opacity: 0.6
                }
            }
            UsageBar {
                Layout.fillWidth: true
                visible: usageSnapshot.agyWeeklyPct !== null
                percent: usageSnapshot.agyWeeklyPct
                barColor: Usage.agyWeeklyLevelColor(usageSnapshot.agyWeeklyPct)
            }
        }

        // Last updated
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: usageSnapshot.receivedAt !== null
            font: Kirigami.Theme.smallFont
            opacity: 0.5
            text: "Updated " + Usage.fmtDuration(Math.max(0, Math.round(nowTs - usageSnapshot.receivedAt))) + " ago"
        }
    }

    // Simple usage bar component
    component UsageBar: Item {
        property var percent: null
        property color barColor: "#585b70"
        implicitHeight: 10

        // Track and fill are siblings so the track's opacity doesn't dim the fill.
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.highlightColor
            border.width: 1
            opacity: 0.2
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: (percent !== null) ? (parent.width * Math.max(0, Math.min(100, percent)) / 100) : 0
            radius: height / 2
            color: barColor
        }
    }

    // Icon font for the agent glyphs; rows fall back to a plain dot without it.
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property bool hasIconFont: Qt.fontFamilies().indexOf(iconFont) !== -1
}