import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
                             ? fullRepresentation : compactRepresentation

    readonly property string scriptPath: Qt.resolvedUrl("../code/freellmapi.py").toString().replace(/^file:\/\//, "")
    readonly property string clickCommand: "python3 '" + root.scriptPath + "'"
    property var payload: null
    property bool loading: false
    property string errorMsg: ""

    function fmtNum(n) {
        if (n === null || n === undefined) return "—"
        return Math.round(n).toLocaleString(Qt.locale(), "f", 0)
    }
    function fmtTokens(n) {
        if (n === null || n === undefined) return "—"
        if (n >= 1000000) return (n/1000000).toFixed(1) + "M"
        if (n >= 1000) return (n/1000).toFixed(0) + "k"
        return fmtNum(n)
    }

    // Catppuccin Mocha
    readonly property color cBase:    "#1e1e2e"
    readonly property color cMantle:  "#181825"
    readonly property color cSurf0:   "#313244"
    readonly property color cSurf1:   "#45475a"
    readonly property color cOverlay: "#6c7086"
    readonly property color cText:    "#cdd6f4"
    readonly property color cSub0:    "#a6adc8"
    readonly property color cSub1:    "#bac2de"
    readonly property color cMauve:   "#cba6f7"
    readonly property color cBlue:    "#89b4fa"
    readonly property color cSapphire:"#74c7ec"
    readonly property color cGreen:   "#a6e3a1"
    readonly property color cRed:     "#f38ba8"
    readonly property color cPeach:   "#fab387"
    readonly property color cYellow:  "#f9e2af"

    readonly property var today: root.payload && root.payload.daily ? root.payload.daily.today : null
    readonly property var yesterday: root.payload && root.payload.daily ? root.payload.daily.yesterday : null

    // Change vs yesterday as {text, color}. higherIsBetter decides red/green;
    // points=true reports an absolute difference (for percentages like success rate).
    function delta(key, higherIsBetter, points) {
        if (!root.today || !root.yesterday) return null
        var t = root.today[key], y = root.yesterday[key]
        if (t === null || t === undefined || y === null || y === undefined) return null
        var d
        if (points) {
            d = t - y
        } else {
            if (y === 0) return null
            d = (t - y) / y * 100
        }
        var rounded = Math.round(d * 10) / 10
        var arrow = rounded > 0 ? "▲ " : (rounded < 0 ? "▼ " : "")
        var text = arrow + Math.abs(rounded).toFixed(1) + (points ? " pp" : "%")
        var good = higherIsBetter ? rounded > 0 : rounded < 0
        return { text: text, color: rounded === 0 ? root.cOverlay : (good ? root.cGreen : root.cRed) }
    }

    function fmtMs(n) {
        if (n === null || n === undefined) return "—"
        return n >= 10000 ? (n / 1000).toFixed(1) + " s" : n + " ms"
    }

    function getSummaryModel() {
        var s = root.today
        if (!s) return []
        return [
            { label: "Requests", value: fmtNum(s.totalRequests), accent: root.cBlue, delta: delta("totalRequests", true, false) },
            { label: "Success", value: s.successRate === null ? "—" : s.successRate + "%", accent: root.cGreen, delta: delta("successRate", true, true) },
            { label: "Avg Latency", value: fmtMs(s.avgLatencyMs), accent: root.cPeach, delta: delta("avgLatencyMs", false, false) },
            { label: "p50 Latency", value: fmtMs(s.p50LatencyMs), accent: root.cPeach, delta: delta("p50LatencyMs", false, false) },
            { label: "p95 Latency", value: fmtMs(s.p95LatencyMs), accent: root.cPeach, delta: delta("p95LatencyMs", false, false) },
            { label: "Avg TTFB", value: fmtMs(s.avgTtfbMs), accent: root.cYellow, delta: delta("avgTtfbMs", false, false) },
            { label: "Input Tokens", value: fmtTokens(s.totalInputTokens), accent: root.cMauve, delta: delta("totalInputTokens", true, false) },
            { label: "Output Tokens", value: fmtTokens(s.totalOutputTokens), accent: root.cMauve, delta: delta("totalOutputTokens", true, false) }
        ]
    }

    function getLifetimeTotals() {
        if (!root.payload || !root.payload.model_changes || !root.payload.model_changes.lifetime_totals) return null
        return root.payload.model_changes.lifetime_totals
    }

    Plasma5Support.DataSource {
        id: fetchSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            root.loading = false
            var stdout = (data["stdout"] || "").trim()
            var obj = null
            try { obj = stdout ? JSON.parse(stdout) : null } catch(e) { obj = null }
            if (!obj) {
                root.errorMsg = (data["stderr"] || "").trim() || "Parse error"
                root.payload = null
                return
            }
            root.errorMsg = obj.error || ""
            root.payload = obj
        }
    }

    function refresh() {
        if (root.loading) return
        root.loading = true
        fetchSource.connectSource(root.clickCommand)
    }

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    toolTipMainText: "FreeLLMAPI Usage"
    toolTipSubText: {
        if (root.errorMsg) return root.errorMsg
        if (!root.payload || !root.payload.ok) return "Loading…"
        var s = root.today
        if (!s) return "No data"
        return "Today: " + s.totalRequests + " req · " + fmtTokens(s.totalInputTokens) + " in · " + fmtTokens(s.totalOutputTokens) + " out"
    }

    compactRepresentation: MouseArea {
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        RowLayout {
            anchors.centerIn: parent
            Kirigami.Icon { source: "view-refresh"; Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium; Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium }
            PlasmaComponents.Label {
                text: {
                    if (!root.payload || !root.payload.ok) return "…"
                    return root.today ? root.today.totalRequests + " req" : "—"
                }
                font.bold: true
            }
        }
    }

    Plasmoid.backgroundHints: Plasmoid.formFactor === PlasmaCore.Types.Planar
                              ? PlasmaCore.Types.NoBackground : PlasmaCore.Types.DefaultBackground

    fullRepresentation: Rectangle {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22
        color: root.cBase
        radius: 12

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Text { text: "FreeLLMAPI Usage"; color: root.cMauve; font.bold: true; font.pixelSize: 18; Layout.fillWidth: true }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    icon.color: root.cSub0
                    enabled: !root.loading
                    onClicked: root.refresh()
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.cSurf1 }

            Text {
                Layout.fillWidth: true
                visible: root.errorMsg !== ""
                text: root.errorMsg
                color: root.cRed
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                visible: !root.today
                text: root.loading ? "Fetching…" : "No data"
                color: root.cOverlay
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.today !== null
                Text { text: "Today"; color: root.cBlue; font.bold: true; font.pixelSize: 14 }
                Text { text: "vs. yesterday at this time"; color: root.cOverlay; font.pixelSize: 11; Layout.fillWidth: true }
            }

            // Summary cards - today, with change vs yesterday
            GridLayout {
                visible: root.today !== null
                columns: 2
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true
                Repeater {
                    model: root.getSummaryModel()
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: card.implicitHeight + Kirigami.Units.mediumSpacing * 2
                        radius: 8
                        color: root.cSurf0
                        Rectangle {
                            width: 3; radius: 1.5
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: Kirigami.Units.mediumSpacing }
                            color: modelData.accent
                        }
                        ColumnLayout {
                            id: card
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Kirigami.Units.mediumSpacing
                            anchors.leftMargin: Kirigami.Units.mediumSpacing + 9
                            spacing: 2
                            Text { text: modelData.label; color: root.cSub0; font.pixelSize: 11 }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: modelData.value; color: root.cText; font.bold: true; font.pixelSize: 17 }
                                Item { Layout.fillWidth: true }
                                Text {
                                    visible: modelData.delta !== null
                                    text: modelData.delta ? modelData.delta.text : ""
                                    color: modelData.delta ? modelData.delta.color : root.cOverlay
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.cSurf1; Layout.topMargin: Kirigami.Units.smallSpacing }

            // Top 3 models today
            Text { text: "Top Models Today"; color: root.cBlue; font.bold: true; font.pixelSize: 14; visible: root.today !== null }
            Repeater {
                model: root.today ? root.today.by_model.slice(0, 3) : []
                delegate: RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: modelData.displayName; color: root.cText; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: fmtTokens(modelData.totalInputTokens) + " in · " + fmtTokens(modelData.totalOutputTokens) + " out"; color: root.cSub0; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    Text { text: modelData.requests + " req"; color: root.cPeach; font.bold: true }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.cSurf1; Layout.topMargin: Kirigami.Units.smallSpacing }

            // Lifetime totals
            Text {
                visible: root.getLifetimeTotals() !== null
                text: "Lifetime"
                color: root.cBlue
                font.bold: true
                font.pixelSize: 14
            }
            GridLayout {
                visible: root.getLifetimeTotals() !== null
                columns: 2
                Layout.fillWidth: true
                rowSpacing: 2
                columnSpacing: Kirigami.Units.mediumSpacing
                Text { text: "Requests"; color: root.cSub0 }
                Text { text: root.getLifetimeTotals() ? fmtNum(root.getLifetimeTotals().total_requests) : "—"; color: root.cText; font.bold: true }
                Text { text: "Input tokens"; color: root.cSub0 }
                Text { text: root.getLifetimeTotals() ? fmtTokens(root.getLifetimeTotals().total_input_tokens) : "—"; color: root.cText; font.bold: true }
                Text { text: "Output tokens"; color: root.cSub0 }
                Text { text: root.getLifetimeTotals() ? fmtTokens(root.getLifetimeTotals().total_output_tokens) : "—"; color: root.cText; font.bold: true }
                Text { text: "First request"; color: root.cSub0 }
                Text { text: root.getLifetimeTotals() ? (root.getLifetimeTotals().first_request_at || "—") : "—"; color: root.cText; font.bold: true }
            }

            // Absorb leftover height so content stays pinned to the top
            Item { Layout.fillHeight: true }

            Text {
                Layout.fillWidth: true
                font.pixelSize: 10
                color: root.cOverlay
                text: root.payload && root.payload.received_at ? ("Updated " + new Date(root.payload.received_at).toLocaleString()) : ""
            }
        }
    }
}
