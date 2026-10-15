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
        return n.toLocaleString()
    }
    function fmtTokens(n) {
        if (n === null || n === undefined) return "—"
        if (n >= 1000000) return (n/1000000).toFixed(1) + "M"
        if (n >= 1000) return (n/1000).toFixed(0) + "k"
        return fmtNum(n)
    }

    function getSummaryModel() {
        if (!root.payload || !root.payload.ok || !root.payload.data || !root.payload.data.summary) return []
        var s = root.payload.data.summary
        return [
            { label: "Requests (today)", value: s.totalRequests },
            { label: "Success %", value: (s.successRate || 0) + "%" },
            { label: "Avg Latency", value: (s.avgLatencyMs || 0) + " ms" },
            { label: "p50 Latency", value: (s.p50LatencyMs || 0) + " ms" },
            { label: "p95 Latency", value: (s.p95LatencyMs || 0) + " ms" },
            { label: "Avg TTFB", value: (s.avgTtfbMs || 0) + " ms" },
            { label: "Input Tokens (today)", value: fmtTokens(s.totalInputTokens) },
            { label: "Output Tokens (today)", value: fmtTokens(s.totalOutputTokens) }
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
        // Fetch daily data
        fetchSource.connectSource(root.clickCommand + " --range 1d")
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
        var s = root.payload.data && root.payload.data.summary
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
                    var s = root.payload.data && root.payload.data.summary
                    return s ? s.totalRequests + " req" : "—"
                }
                font.bold: true
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22
        spacing: Kirigami.Units.smallSpacing
        Layout.alignment: Qt.AlignTop

        RowLayout {
            Layout.fillWidth: true
            Kirigami.Heading { level: 4; text: "FreeLLMAPI Usage"; Layout.fillWidth: true }
            QQC2.ToolButton { icon.name: "view-refresh"; enabled: !root.loading; onClicked: root.refresh() }
        }
        Kirigami.Separator { Layout.fillWidth: true }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.errorMsg !== ""
            text: root.errorMsg
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: !root.payload || root.payload.ok === false
            text: root.loading ? "Fetching…" : "No data"
            opacity: 0.7
        }

        // Daily indicator
        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.payload && root.payload.ok
            text: "Today"
            font.bold: true
            font.pixelSize: Kirigami.Units.smallSpacing * 3.5
            color: Kirigami.Theme.highlightColor
        }

        // Summary cards - 2 columns, bigger
        GridLayout {
            visible: root.payload && root.payload.ok
            columns: 2
            rowSpacing: Kirigami.Units.mediumSpacing
            columnSpacing: Kirigami.Units.mediumSpacing
            Layout.fillWidth: true
            Repeater {
                model: root.getSummaryModel()
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 3.5
                    Layout.alignment: Qt.AlignTop
                    radius: 10
                    color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    border.color: Kirigami.Theme.disabledTextColor
                    ColumnLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Kirigami.Units.mediumSpacing
                        PlasmaComponents.Label { text: modelData.label; opacity: 0.7; font.pixelSize: Kirigami.Units.smallSpacing * 2.5; Layout.alignment: Qt.AlignTop }
                        PlasmaComponents.Label { text: modelData.value; font.bold: true; font.pixelSize: Kirigami.Units.smallSpacing * 4; Layout.fillWidth: true; wrapMode: Text.Wrap; Layout.alignment: Qt.AlignTop }
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Top 3 Models
        Kirigami.Heading { level: 5; text: "Top Models"; visible: root.payload && root.payload.ok }
        ColumnLayout {
            visible: root.payload && root.payload.ok
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Repeater {
                model: (root.payload && root.payload.data && root.payload.data.by_model) ? root.payload.data.by_model.slice(0, 3) : []
                delegate: Item {
                    Layout.fillWidth: true
                    implicitHeight: col.implicitHeight + Kirigami.Units.smallSpacing * 2
                    ColumnLayout {
                        id: col
                        width: parent.width
                        Layout.alignment: Qt.AlignTop
                        PlasmaComponents.Label { text: modelData.displayName || modelData.modelId; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignTop }
                        PlasmaComponents.Label { text: (modelData.requests || 0) + " req · " + fmtTokens(modelData.totalInputTokens) + " in · " + fmtTokens(modelData.totalOutputTokens) + " out"; opacity: 0.7; elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignTop }
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Lifetime totals
        PlasmaComponents.Label {
            visible: root.getLifetimeTotals() !== null
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            text: "Lifetime totals (server settings):"
            font.bold: true
        }
        GridLayout {
            visible: root.getLifetimeTotals() !== null
            columns: 2
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.mediumSpacing
            PlasmaComponents.Label { text: "Total requests:"; opacity: 0.7; Layout.alignment: Qt.AlignLeft }
            PlasmaComponents.Label { text: root.getLifetimeTotals() ? fmtNum(root.getLifetimeTotals().total_requests) : "—"; font.bold: true; Layout.alignment: Qt.AlignLeft }
            PlasmaComponents.Label { text: "Input tokens:"; opacity: 0.7; Layout.alignment: Qt.AlignLeft }
            PlasmaComponents.Label { text: root.getLifetimeTotals() ? fmtTokens(root.getLifetimeTotals().total_input_tokens) : "—"; font.bold: true; Layout.alignment: Qt.AlignLeft }
            PlasmaComponents.Label { text: "Output tokens:"; opacity: 0.7; Layout.alignment: Qt.AlignLeft }
            PlasmaComponents.Label { text: root.getLifetimeTotals() ? fmtTokens(root.getLifetimeTotals().total_output_tokens) : "—"; font.bold: true; Layout.alignment: Qt.AlignLeft }
            PlasmaComponents.Label { text: "First request:"; opacity: 0.7; Layout.alignment: Qt.AlignLeft }
            PlasmaComponents.Label { text: root.getLifetimeTotals() ? (root.getLifetimeTotals().first_request_at || "—") : "—"; font.bold: true; Layout.alignment: Qt.AlignLeft }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            font.pixelSize: Kirigami.Units.smallSpacing * 3
            opacity: 0.5
            text: root.payload && root.payload.received_at ? ("Updated " + new Date(root.payload.received_at).toLocaleString()) : ""
        }

        // Absorb leftover height so content stays pinned to the top
        Item { Layout.fillHeight: true }
    }
}
