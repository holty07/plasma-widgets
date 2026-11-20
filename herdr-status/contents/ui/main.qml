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

    readonly property var stateOrder: ["working", "blocked", "idle", "done", "unknown"]

    // Catppuccin Mocha, same running / waiting / idle palette as the orca widget
    readonly property var stateColour: ({
        "working": "#89b4fa",   // blue  - in progress
        "blocked": "#f9e2af",   // yellow - waiting on you / blocked
        "done":    "#a6e3a1",   // green
        "idle":    "#a6e3a1",   // green
        "unknown": "#9399b2"    // grey
    })

    readonly property var stateLabel: ({
        "working": i18n("Working"),
        "blocked": i18n("Blocked"),
        "done":    i18n("Done"),
        "idle":    i18n("Idle"),
        "unknown": i18n("Unknown")
    })

    property var counts: ({ working: 0, blocked: 0, idle: 0, done: 0, unknown: 0 })
    property var agentList: []
    property string summary: i18n("Waiting for herdr…")
    property string errorText: ""
    property bool loaded: false

    readonly property int runningCount: counts.working
    readonly property int waitingCount: counts.blocked
    // Panel dot merges idle, done and unknown into one "idle" count, like orca.
    readonly property int idleCount: counts.idle + counts.done + counts.unknown

    Plasmoid.status: (plasmoid.configuration.attentionOnBlocked && counts.blocked > 0)
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("herdr")
    toolTipSubText: errorText !== "" ? errorText : summary

    // Full card on the desktop, compact dots in the panel — like the orca widget.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
                        ? fullRepresentation : compactRepresentation

    // ------------------------------------------------------------------ data

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
                    : i18n("herdr is not running, or the binary was not found")
                root.loaded = true
                root.applyAgents([])
                return
            }
            root.errorText = ""
            root.applyAgents(root.parseAgents(stdout))
        }
    }

    Timer {
        interval: Math.max(1, plasmoid.configuration.pollInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    function herdrBin() {
        var bin = (plasmoid.configuration.herdrBinary || "herdr").trim()
        return bin.length > 0 ? bin : "herdr"
    }

    function refresh() {
        executable.run(herdrBin() + " agent list")
    }

    function focusAgent(target) {
        if (!target) {
            return
        }
        executable.run(herdrBin() + " agent focus " + target)
    }

    // herdr wraps results as {"id":…,"result":{"type":"agent_list","agents":[…]}}.
    // Walk the tree instead of assuming the key, so a schema tweak upstream
    // does not silently blank the widget.
    function parseAgents(stdout) {
        var payload
        try {
            payload = JSON.parse(stdout)
        } catch (e) {
            root.errorText = i18n("Could not read the herdr response")
            return []
        }
        var found = []
        collect(payload, found)
        return found
    }

    function collect(node, out) {
        if (node === null || typeof node !== "object") {
            return
        }
        if (Array.isArray(node)) {
            for (var i = 0; i < node.length; i++) {
                collect(node[i], out)
            }
            return
        }
        if (typeof statusOf(node) === "string" && node.pane_id !== undefined) {
            out.push(node)
            return
        }
        for (var key in node) {
            collect(node[key], out)
        }
    }

    function statusOf(agent) {
        return agent.agent_status || agent.status || agent.state
    }

    function normalise(value) {
        var s = String(value || "").toLowerCase()
        return stateOrder.indexOf(s) >= 0 ? s : "unknown"
    }

    // herdr statuses: working, blocked, idle, done, unknown.
    // Panel dots mirror the orca widget: running (working), waiting (blocked),
    // idle (idle + done + unknown).
    function groupOf(status) {
        var s = normalise(status)
        if (s === "working") {
            return "running"
        }
        if (s === "blocked") {
            return "waiting"
        }
        return "idle"
    }

    function placeOf(agent) {
        var where = agent.foreground_cwd || agent.cwd || ""
        var parts = where.split("/")
        return parts[parts.length - 1] || where
    }

    function applyAgents(list) {
        var tally = { working: 0, blocked: 0, idle: 0, done: 0, unknown: 0 }
        for (var i = 0; i < list.length; i++) {
            tally[normalise(statusOf(list[i]))]++
        }

        var entries = []
        for (var j = 0; j < list.length; j++) {
            var agent = list[j]
            var state = normalise(statusOf(agent))
            entries.push({
                group: groupOf(state),
                state: state,
                agentType: "" + (agent.agent || agent.kind || ""),
                paneKey: "" + (agent.pane_id || ""),
                place: placeOf(agent),
                since: agent.state_change_seq || 0,
                title: agent.terminal_title_stripped || agent.terminal_title || i18n("agent")
            })
        }

        // Agents needing attention first, then working, then idle;
        // newest state change first within each group.
        var rank = { waiting: 0, running: 1, idle: 2 }
        entries.sort(function(x, y) {
            return rank[x.group] - rank[y.group] || y.since - x.since
        })

        counts = tally
        agentList = entries
        loaded = true

        var idle = tally.idle + tally.done + tally.unknown
        var parts = []
        if (tally.working > 0) {
            parts.push(tally.working + " " + i18n("working"))
        }
        if (tally.blocked > 0) {
            parts.push(tally.blocked + " " + i18n("blocked"))
        }
        if (idle > 0) {
            parts.push(idle + " " + i18n("idle"))
        }
        summary = list.length === 0
            ? i18n("No agents")
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
                dotColor: "#f9e2af"   // yellow - blocked
                count: root.waitingCount
                pulse: root.waitingCount > 0
                available: root.loaded
            }
            DotAndCount {
                dotColor: "#a6e3a1"   // green - idle / done / unknown
                count: root.idleCount
                pulse: false
                available: root.loaded && !plasmoid.configuration.hideIdle
            }

            PlasmaComponents.Label {
                visible: root.agentList.length === 0
                text: root.errorText !== "" ? "!" : "·"
                opacity: 0.6
                color: root.errorText !== "" ? root.stateColour["blocked"] : Kirigami.Theme.textColor
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
                    text: root.errorText !== "" ? i18n("herdr unavailable") : root.summary
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
                visible: root.agentList.length === 0
                iconName: root.errorText !== "" ? "dialog-warning" : "utilities-terminal"
                text: root.errorText !== "" ? root.errorText : i18n("No agents")
                explanation: root.errorText !== ""
                    ? i18n("Check the binary path in the widget settings.")
                    : i18n("Start a coding agent inside a herdr pane and it will show up here.")
            }

            PlasmaComponents.ScrollView {
                anchors.fill: parent
                visible: root.agentList.length > 0

                ListView {
                    model: root.agentList
                    clip: true
                    spacing: 0

                    delegate: PlasmaComponents.ItemDelegate {
                        width: ListView.view.width
                        onClicked: root.focusAgent(modelData.paneKey)

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
                                    text: modelData.place
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

    // Nerd Font glyph per herdr agent name; falls back to a generic robot.
    function agentGlyph(type) {
        switch (type) {
        case "claude":     return "\uec82"    // cod-claude
        case "codex":
        case "openai":     return "\uec81"    // cod-openai
        case "gemini":     return "\uec21"    // cod-sparkle_filled
        case "hermes":     return "\udb86\udc6e"  // md-horse_variant_fast (U+F186E)
        case "copilot":    return "\uec1e"    // cod-copilot
        case "cursor":     return "\uec5c"    // cod-cursor
        case "opencode":   return "\uebc4"    // cod-terminal_cmd
        default:           return "\uec20"    // cod-robot
        }
    }
}
