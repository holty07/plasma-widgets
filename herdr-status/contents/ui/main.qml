import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // ---- state ------------------------------------------------------------

    readonly property var stateOrder: ["blocked", "working", "done", "idle", "unknown"]

    // Catppuccin Mocha
    readonly property var stateColour: ({
        "blocked": "#f38ba8",
        "working": "#89b4fa",
        "done":    "#a6e3a1",
        "idle":    "#6c7086",
        "unknown": "#9399b2"
    })

    readonly property var stateLabel: ({
        "blocked": i18n("blocked"),
        "working": i18n("working"),
        "done":    i18n("done"),
        "idle":    i18n("idle"),
        "unknown": i18n("unknown")
    })

    property var counts: ({ blocked: 0, working: 0, done: 0, idle: 0, unknown: 0 })
    property var chips: []
    property var agentList: []
    property string summary: i18n("Waiting for herdr…")
    property string errorText: ""

    Plasmoid.status: (plasmoid.configuration.attentionOnBlocked && counts.blocked > 0)
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("herdr")
    toolTipSubText: errorText !== "" ? errorText : summary

    preferredRepresentation: compactRepresentation

    // ---- data ---------------------------------------------------------------

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

    function applyAgents(list) {
        var tally = { blocked: 0, working: 0, done: 0, idle: 0, unknown: 0 }
        for (var i = 0; i < list.length; i++) {
            tally[normalise(statusOf(list[i]))]++
        }

        var built = []
        for (var j = 0; j < stateOrder.length; j++) {
            var key = stateOrder[j]
            if (tally[key] === 0) {
                continue
            }
            if (key === "idle" && plasmoid.configuration.hideIdle) {
                continue
            }
            built.push({ key: key, count: tally[key], colour: stateColour[key] })
        }

        var parts = []
        for (var k = 0; k < stateOrder.length; k++) {
            if (tally[stateOrder[k]] > 0) {
                parts.push(tally[stateOrder[k]] + " " + stateLabel[stateOrder[k]])
            }
        }

        counts = tally
        chips = built
        agentList = list
        summary = list.length === 0
            ? i18n("No agents")
            : parts.join(", ")
    }

    function agentName(agent) {
        return agent.display_agent || agent.agent || agent.name || agent.kind || i18n("agent")
    }

    function agentWhere(agent) {
        var where = agent.workspace_label || agent.workspace_id || ""
        var title = agent.terminal_title_stripped || agent.title || ""
        if (title.length > 0) {
            return where.length > 0 ? where + " · " + title : title
        }
        return where.length > 0 ? where + " · " + agent.pane_id : agent.pane_id
    }

    // ---- panel --------------------------------------------------------------

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

            Repeater {
                model: root.chips

                delegate: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: compact.dotSize
                        implicitHeight: compact.dotSize
                        radius: compact.dotSize / 2
                        color: modelData.colour

                        SequentialAnimation on opacity {
                            running: modelData.key === "blocked"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutQuad }
                        }
                    }

                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignVCenter
                        text: modelData.count
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: modelData.key === "blocked" ? Font.Bold : Font.Normal
                    }
                }
            }

            PlasmaComponents.Label {
                visible: root.chips.length === 0
                text: root.errorText !== "" ? "!" : "·"
                opacity: 0.6
                color: root.errorText !== "" ? root.stateColour["blocked"] : Kirigami.Theme.textColor
            }
        }
    }

    // ---- popup --------------------------------------------------------------

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
                text: root.errorText !== "" ? root.errorText : i18n("No agents running")
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
                        onClicked: root.focusAgent(modelData.pane_id)

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.largeSpacing

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: Kirigami.Units.gridUnit * 0.5
                                implicitHeight: Kirigami.Units.gridUnit * 0.5
                                radius: width / 2
                                color: root.stateColour[root.normalise(root.statusOf(modelData))]
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                PlasmaComponents.Label {
                                    text: root.agentName(modelData)
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                PlasmaComponents.Label {
                                    text: root.agentWhere(modelData)
                                    elide: Text.ElideRight
                                    opacity: 0.65
                                    font: Kirigami.Theme.smallFont
                                    Layout.fillWidth: true
                                }
                            }

                            PlasmaComponents.Label {
                                text: root.stateLabel[root.normalise(root.statusOf(modelData))]
                                font: Kirigami.Theme.smallFont
                                color: root.stateColour[root.normalise(root.statusOf(modelData))]
                            }
                        }
                    }
                }
            }
        }
    }
}
