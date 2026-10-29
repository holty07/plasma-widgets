import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support

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

    Timer {
        interval: Math.max(1, plasmoid.configuration.pollInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
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
        Layout.preferredHeight: Kirigami.Units.gridUnit * 18
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

        contentItem: Item {
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

    // Icon font for the agent glyphs; rows fall back to a plain dot without it.
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property bool hasIconFont: Qt.fontFamilies().indexOf(iconFont) !== -1
}