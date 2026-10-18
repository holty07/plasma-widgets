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

    // True while Claude Code's statusLine hook has fired recently — i.e. a
    // Code session looks actively running right now.
    readonly property bool codeActive: _hookSnap && _hookSnap.available
        && _hookSnap.receivedAt !== null && (nowTs - _hookSnap.receivedAt) < 15 * 60

    // Detecting "typing" vs "waiting for input": the hook only rewrites its
    // status file when Claude Code's own status line refreshes, which only
    // happens while something is actively happening (streaming a response,
    // finishing a turn). If that timestamp keeps advancing between our
    // polls, Code is doing something; if it goes still, it's idle waiting
    // on you. Each detected advance holds the "typing" pose for a few
    // seconds so it doesn't flicker between polls.
    property real _lastHookReceivedAt: -1
    property real _typingUntil: 0
    readonly property bool isTyping: nowTs < _typingUntil
    readonly property bool isThinking: codeActive && !isTyping

    // Three sources, combined once all have reported back:
    //   1. plan-usage-history.json - the desktop app's own rolling usage
    //      cache (same numbers as the tray icon). Always present once the
    //      app has run, covers chat + Cowork + Code equally. Primary source.
    //   2. plasma-usage-status.json - our Claude Code statusLine hook.
    //      Only present if that's been installed and Code has run recently.
    //      If very fresh (<15min), its percentages take priority (most
    //      real-time during an active coding session). Either way, if it's
    //      reasonably fresh (<6h) its cost/context/model detail gets merged
    //      in on top of whichever snapshot wins.
    //   3. ~/.claude.json cachedUsageUtilization - last-resort fallback,
    //      only used if neither of the above produced anything.
    property var _appSnap: null
    property var _hookSnap: null
    property int _pending: 0

    // Shell out to `cat` rather than reading file:// URLs from QML directly —
    // sidesteps any QML-engine/module quirks around local file access entirely.
    Plasma5Support.DataSource {
        id: catAppUsage
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            var text = (data && data["stdout"]) ? data["stdout"] : ""
            root._appSnap = text ? Usage.fromPlanUsageHistory(text) : null
            root._maybeCombine()
        }
    }

    Plasma5Support.DataSource {
        id: catHook
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            var text = (data && data["stdout"]) ? data["stdout"] : ""
            root._hookSnap = text ? Usage.fromHookPayload(text) : null
            root._maybeCombine()
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
            root.snapshot = snap || Usage.emptySnapshot()
        }
    }

    function refresh() {
        _appSnap = null
        _hookSnap = null
        _pending = 2
        catAppUsage.connectSource("cat ~/.config/Claude/plan-usage-history.json 2>/dev/null")
        catHook.connectSource("cat ~/.claude/plasma-usage-status.json 2>/dev/null")
    }

    function _maybeCombine() {
        _pending -= 1
        if (_pending > 0) return

        var now = Date.now() / 1000
        var appAvail = _appSnap && _appSnap.available
        var hookAvail = _hookSnap && _hookSnap.available
        var hookAge = (hookAvail && _hookSnap.receivedAt !== null) ? (now - _hookSnap.receivedAt) : Infinity
        var hookFresh = hookAvail && hookAge < 15 * 60
        var hookUsableForDetail = hookAvail && hookAge < 6 * 3600

        // Did the hook write something new since our last poll?
        if (hookAvail && _hookSnap.receivedAt !== null) {
            if (_lastHookReceivedAt >= 0 && _hookSnap.receivedAt > _lastHookReceivedAt) {
                _typingUntil = now + 8
            }
            _lastHookReceivedAt = _hookSnap.receivedAt
        }

        var chosen = null
        if (hookFresh) {
            chosen = _hookSnap
        } else if (appAvail) {
            chosen = Object.assign({}, _appSnap)
            if (hookUsableForDetail) {
                chosen.contextPct = _hookSnap.contextPct
                chosen.contextSize = _hookSnap.contextSize
                chosen.costUsd = _hookSnap.costUsd
                chosen.durationMs = _hookSnap.durationMs
                chosen.model = _hookSnap.model
                chosen.effort = _hookSnap.effort
                chosen.project = _hookSnap.project
            }
        } else if (hookAvail) {
            chosen = _hookSnap
        }

        if (chosen) {
            root.snapshot = chosen
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

    Component.onCompleted: refresh()

    Timer {
        // Poll faster while a session looks active, so the typing/thinking
        // distinction actually has a chance to catch changes between polls.
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

    toolTipMainText: "Claude Usage"
    toolTipSubText: {
        if (!snapshot.available) return "Not set up yet — click for instructions"
        var lines = []
        if (snapshot.sessionPct !== null) lines.push("Session (5h, outer): " + snapshot.sessionPct + "%")
        if (snapshot.weeklyPct !== null) lines.push("Weekly (7d, inner): " + snapshot.weeklyPct + "%")
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
            innerPercent: root.snapshot.weeklyPct
            innerColor: Usage.weeklyLevelColor(root.snapshot.weeklyPct)
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

        // Shown until the statusLine hook has ever written anything, and
        // ~/.claude.json has no cached quota either.
        ColumnLayout {
            id: setupColumn
            visible: !root.snapshot.available
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 4
                text: "Claude Usage — not set up yet"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "No usage data found yet. Either Claude Code hasn't run since you " +
                      "logged in, or the hook isn't installed. To install it, run:"
                opacity: 0.8
            }
            QQC2.TextArea {
                Layout.fillWidth: true
                readOnly: true
                wrapMode: TextEdit.NoWrap
                font.family: "monospace"
                text: "python3 ~/.local/share/plasma/plasmoids/io.github.holty07.claudeusage/hook/setup-claude-usage-hook.py\n# then restart Claude Code"
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Once installed, open Claude Code and send a message — the widget " +
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
                    text: "Claude Usage"
                    Layout.fillWidth: true
                }
                TypingCat {
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
                text: root.isThinking ? "Claude Code is waiting for your input" : "Claude Code is running"
                opacity: 0.6
                font.pixelSize: Kirigami.Units.smallSpacing * 3
            }

            // Session (5 hour)
            RowLayout {
                Layout.fillWidth: true
                QQC2.Label { text: "Session (5h)"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
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

            // Weekly (7 day)
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                QQC2.Label { text: "Weekly (7d)"; Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
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
                barColor: Usage.weeklyLevelColor(root.snapshot.weeklyPct)
            }

            // Context window (only known via the hook, not the claude.json fallback)
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
                visible: root.snapshot.costUsd !== null || root.snapshot.model !== ""
            }

            // Cost / duration / model / project
            GridLayout {
                columns: 2
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing / 2

                QQC2.Label {
                    visible: root.snapshot.costUsd !== null
                    text: "Session cost"
                    opacity: 0.6
                }
                QQC2.Label {
                    visible: root.snapshot.costUsd !== null
                    text: root.snapshot.costUsd !== null ? "$" + root.snapshot.costUsd.toFixed(2) : ""
                }

                QQC2.Label {
                    visible: root.snapshot.durationMs !== null
                    text: "Session length"
                    opacity: 0.6
                }
                QQC2.Label {
                    visible: root.snapshot.durationMs !== null
                    text: root.snapshot.durationMs !== null ? Usage.fmtDuration(root.snapshot.durationMs / 1000) : ""
                }

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
                    var src = root.snapshot.source === "claude-json" ? " (fallback source — no usage cache found yet)" : ""
                    return "Updated " + Usage.fmtDuration(ago) + " ago" + src + (root.isStale ? " ⚠ stale" : "")
                }
            }
        }
    }
}
