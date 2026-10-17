import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

import "../code/usage.js" as Usage

PlasmoidItem {
    id: root

    property var snapshot: Usage.emptySnapshot()
    property real nowTs: Date.now() / 1000

    readonly property bool isStale: snapshot.available && snapshot.receivedAt !== null
        && (nowTs - snapshot.receivedAt) > 6 * 3600

    // A session "looks active" if the hook has fired in the last 15 min.
    readonly property bool codeActive: snapshot.available && snapshot.receivedAt !== null
        && (nowTs - snapshot.receivedAt) < 15 * 60

    // Unlike Claude Code, antigravity-cli's hook tells us the activity
    // state directly via agent_state - no timestamp-delta guessing needed.
    // "idle" (or the startup states) means it's not actively generating.
    readonly property bool isThinking: codeActive &&
        (snapshot.agentState === "idle" || snapshot.agentState === "initializing"
         || snapshot.agentState === "authenticating" || snapshot.agentState === "")

    Plasma5Support.DataSource {
        id: catHook
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            var text = (data && data["stdout"]) ? data["stdout"] : ""
            var snap = text ? Usage.fromHookPayload(text) : null
            root.snapshot = snap || Usage.emptySnapshot()
        }
    }

    function refresh() {
        catHook.connectSource("cat ~/.gemini/antigravity-cli/plasma-agy-status.json 2>/dev/null")
    }

    function resetLabel(resetsAt) {
        if (resetsAt === null || resetsAt === undefined) return ""
        var remain = resetsAt - nowTs
        if (remain <= 0) return "resetting…"
        return Usage.fmtDuration(remain) + " left"
    }

    Component.onCompleted: refresh()

    Timer {
        // Poll faster while a session looks active, same as the Claude widget.
        interval: root.codeActive ? 5000 : 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.nowTs = Date.now() / 1000
    }

    toolTipMainText: "Antigravity Usage"
    toolTipSubText: {
        if (!snapshot.available) return "Not set up yet — click for instructions"
        var lines = []
        if (snapshot.sessionPct !== null) lines.push("Gemini (weekly): " + snapshot.sessionPct + "%")
        if (snapshot.weeklyPct !== null) lines.push("Other models (weekly): " + snapshot.weeklyPct + "%")
        if (isStale) lines.push("(data looks stale)")
        return lines.join("\n")
    }

    // ---- Panel / topbar: pie with the percentage inside ----
    compactRepresentation: Item {
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.iconSizes.huge * 1.2
        Layout.minimumWidth: height
        Layout.preferredWidth: height

        UsageRing {
            anchors.fill: parent
            anchors.margins: 0
            percent: root.snapshot.sessionPct
            ringColor: Usage.levelColor(root.snapshot.sessionPct)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // ---- Desktop: full breakdown ----
    fullRepresentation: Item {
        implicitWidth: Kirigami.Units.gridUnit * 16
        implicitHeight: setupColumn.visible
            ? setupColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
            : mainColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

        ColumnLayout {
            id: setupColumn
            visible: !root.snapshot.available
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 4
                text: "Antigravity Usage — not set up yet"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "No usage data found yet. Either antigravity-cli hasn't run " +
                      "since you logged in, or the hook isn't installed. To install it, run:"
                opacity: 0.8
            }
            QQC2.TextArea {
                Layout.fillWidth: true
                readOnly: true
                wrapMode: TextEdit.NoWrap
                font.family: "monospace"
                text: "python3 ~/.local/share/plasma/plasmoids/io.github.holty07.antigravityusage/hook/setup-antigravity-usage-hook.py\n# then restart antigravity-cli"
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Once installed, run a prompt through antigravity-cli — the widget " +
                      "updates automatically after that."
                opacity: 0.6
                font.pixelSize: Kirigami.Units.smallSpacing * 3
            }
            QQC2.Button {
                text: "Check again"
                onClicked: root.refresh()
            }
        }

        ColumnLayout {
            id: mainColumn
            visible: root.snapshot.available
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 4
                    text: "Antigravity Usage"
                    Layout.fillWidth: true
                }
                TypingDog {
                    active: root.codeActive
                    thinking: root.isThinking
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 40
                }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh()
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: root.codeActive
                text: root.isThinking ? "Antigravity is waiting for your input" : "Antigravity is running"
                opacity: 0.6
                font.pixelSize: Kirigami.Units.smallSpacing * 3
            }

            // Gemini weekly quota (primary - the ring)
            RowLayout {
                Layout.fillWidth: true
                QQC2.Label { text: "Gemini (weekly)"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                QQC2.Label {
                    text: root.snapshot.sessionPct !== null ? root.snapshot.sessionPct + "%" : "—"
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: root.resetLabel(root.snapshot.sessionResetsAt)
                    opacity: 0.6
                }
            }
            UsageBar {
                Layout.fillWidth: true
                percent: root.snapshot.sessionPct
                barColor: Usage.levelColor(root.snapshot.sessionPct)
            }

            // 3rd-party weekly quota (secondary bar)
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                QQC2.Label { text: "Other models (weekly)"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                QQC2.Label {
                    text: root.snapshot.weeklyPct !== null ? root.snapshot.weeklyPct + "%" : "—"
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: root.resetLabel(root.snapshot.weeklyResetsAt)
                    opacity: 0.6
                }
            }
            UsageBar {
                Layout.fillWidth: true
                percent: root.snapshot.weeklyPct
                barColor: Usage.levelColor(root.snapshot.weeklyPct)
            }

            // Context window
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.snapshot.contextPct !== null
                QQC2.Label { text: "Context"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                QQC2.Label {
                    text: root.snapshot.contextPct !== null ? root.snapshot.contextPct + "%" : "—"
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                QQC2.Label {
                    text: root.snapshot.contextSize ? ("of " + Usage.fmtTokens(root.snapshot.contextSize)) : ""
                    opacity: 0.6
                }
            }
            UsageBar {
                Layout.fillWidth: true
                visible: root.snapshot.contextPct !== null
                percent: root.snapshot.contextPct
                barColor: "#89b4fa" // Catppuccin Mocha blue
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: root.snapshot.model !== "" || root.snapshot.planTier !== ""
            }

            GridLayout {
                columns: 2
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing / 2

                QQC2.Label {
                    visible: root.snapshot.model !== ""
                    text: "Model"
                    opacity: 0.6
                }
                QQC2.Label {
                    visible: root.snapshot.model !== ""
                    text: root.snapshot.model + (root.snapshot.effort ? (" (" + root.snapshot.effort + ")") : "")
                }

                QQC2.Label {
                    visible: root.snapshot.planTier !== ""
                    text: "Plan"
                    opacity: 0.6
                }
                QQC2.Label {
                    visible: root.snapshot.planTier !== ""
                    text: root.snapshot.planTier
                }

                QQC2.Label {
                    visible: root.snapshot.project !== ""
                    text: "Project"
                    opacity: 0.6
                }
                QQC2.Label {
                    visible: root.snapshot.project !== ""
                    text: root.snapshot.project
                    elide: Text.ElideMiddle
                }
            }

            Item { Layout.fillHeight: true }

            QQC2.Label {
                Layout.fillWidth: true
                font.pixelSize: Kirigami.Units.smallSpacing * 3
                opacity: 0.5
                wrapMode: Text.WordWrap
                text: {
                    if (root.snapshot.receivedAt === null) return ""
                    var ago = Math.max(0, Math.round(root.nowTs - root.snapshot.receivedAt))
                    return "Updated " + Usage.fmtDuration(ago) + " ago" + (root.isStale ? " ⚠ stale" : "")
                }
            }
        }
    }
}
