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
        var s = root.payload.data && root.payload.data.summary
        if (!s) return "No data"
        return s.totalRequests + " req · " + fmtTokens(s.totalInputTokens) + " in · " + fmtTokens(s.totalOutputTokens) + " out"
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

        // Summary cards
        GridLayout {
            visible: root.payload && root.payload.ok
            columns: 3
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.smallSpacing
            Layout.fillWidth: true
            Repeater {
                model: [
                    { label: "Requests", value: root.payload.data && root.payload.data.summary ? root.payload.data.summary.totalRequests : "—"},
                    { label: "Success %", value: root.payload.data && root.payload.data.summary ? (root.payload.data.summary.successRate || 0) + "%" : "—"},
                    { label: "Avg Latency", value: root.payload.data && root.payload.data.summary ? (root.payload.data.summary.avgLatencyMs || 0) + " ms" : "—"},
                    { label: "Input Tokens", value: root.payload.data && root.payload.data.summary ? fmtTokens(root.payload.data.summary.totalInputTokens) : "—"},
                    { label: "Output Tokens", value: root.payload.data && root.payload.data.summary ? fmtTokens(root.payload.data.summary.totalOutputTokens) : "—"},
                    { label: "Cost Savings", value: root.payload.data && root.payload.data.summary ? "$" + (root.payload.data.summary.estimatedCostSavings || 0) : "—"},
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    radius: 8
                    color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    border.color: Kirigami.Theme.disabledTextColor
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        PlasmaComponents.Label { text: modelData.label; opacity: 0.7; font.pixelSize: Kirigami.Units.smallSpacing * 2 }
                        PlasmaComponents.Label { text: modelData.value; font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Model catalog status
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label { text: "Model Catalog"; font.bold: true }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: {
                    if (!root.payload || !root.payload.model_changes) return "—"
                    var c = root.payload.model_changes
                    return c.changed ? "Changed " + (c.current_version || "") : "Up to date"
                }
                color: root.payload && root.payload.model_changes && root.payload.model_changes.changed ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
            }
        }
        GridLayout {
            visible: root.payload && root.payload.model_changes
            columns: 2
            Layout.fillWidth: true
            PlasmaComponents.Label { text: "Version:"; opacity: 0.7 }
            PlasmaComponents.Label { text: (root.payload.model_changes.current_version || "—") }
            PlasmaComponents.Label { text: "Tier:"; opacity: 0.7 }
            PlasmaComponents.Label { text: (root.payload.model_changes.current_tier || "—") }
            PlasmaComponents.Label { text: "Enabled / Total:"; opacity: 0.7 }
            PlasmaComponents.Label { text: fmtNum(root.payload.model_changes.enabled_models) + " / " + fmtNum(root.payload.model_changes.total_models) }
        }

        // Disabled models warning
        Kirigami.Separator { Layout.fillWidth: true; visible: root.payload && root.payload.model_changes && root.payload.model_changes.disabled_models && root.payload.model_changes.disabled_models.length > 0 }
        PlasmaComponents.Label {
            visible: root.payload && root.payload.model_changes && root.payload.model_changes.disabled_models && root.payload.model_changes.disabled_models.length > 0
            Layout.fillWidth: true
            text: "⚠ " + root.payload.model_changes.disabled_models.length + " model(s) disabled:"
            color: Kirigami.Theme.negativeTextColor
            font.bold: true
        }
        ListView {
            visible: root.payload && root.payload.model_changes && root.payload.model_changes.disabled_models && root.payload.model_changes.disabled_models.length > 0
            model: root.payload.model_changes.disabled_models
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5 * root.payload.model_changes.disabled_models.length
            clip: true
            delegate: PlasmaComponents.Label {
                width: ListView.view.width
                text: "  " + modelData.display_name + " (" + modelData.platform + ") — " + modelData.monthly_token_budget
                color: Kirigami.Theme.negativeTextColor
                opacity: 0.9
                font.pixelSize: Kirigami.Units.smallSpacing * 3
                wrapMode: Text.Wrap
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Top models
        Kirigami.Heading { level: 5; text: "By Model"; visible: root.payload && root.payload.ok }
        PlasmaComponents.ScrollView {
            visible: root.payload && root.payload.ok
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 12
            ListView {
                model: root.payload.data && root.payload.data.by_model ? root.payload.data.by_model.slice(0, 15) : []
                delegate: Item {
                    width: ListView.view.width
                    implicitHeight: col.implicitHeight + Kirigami.Units.smallSpacing * 2
                    ColumnLayout {
                        id: col
                        width: parent.width
                        PlasmaComponents.Label { text: modelData.displayName || modelData.modelId; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        PlasmaComponents.Label { text: (modelData.requests || 0) + " req · " + fmtTokens(modelData.totalInputTokens) + " in · " + fmtTokens(modelData.totalOutputTokens) + " out"; opacity: 0.7; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
            }
        }

        // Lifetime totals
        Kirigami.Separator { Layout.fillWidth: true }
        PlasmaComponents.Label {
            visible: root.payload && root.payload.model_changes && root.payload.model_changes.lifetime_totals
            Layout.fillWidth: true
            text: "Lifetime totals (server settings):"
            font.bold: true
        }
        GridLayout {
            visible: root.payload && root.payload.model_changes && root.payload.model_changes.lifetime_totals
            columns: 2
            Layout.fillWidth: true
            PlasmaComponents.Label { text: "Total requests:"; opacity: 0.7 }
            PlasmaComponents.Label { text: fmtNum(root.payload.model_changes.lifetime_totals.total_requests) }
            PlasmaComponents.Label { text: "Input tokens:"; opacity: 0.7 }
            PlasmaComponents.Label { text: fmtTokens(root.payload.model_changes.lifetime_totals.total_input_tokens) }
            PlasmaComponents.Label { text: "Output tokens:"; opacity: 0.7 }
            PlasmaComponents.Label { text: fmtTokens(root.payload.model_changes.lifetime_totals.total_output_tokens) }
            PlasmaComponents.Label { text: "First request:"; opacity: 0.7 }
            PlasmaComponents.Label { text: root.payload.model_changes.lifetime_totals.first_request_at || "—" }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            font.pixelSize: Kirigami.Units.smallSpacing * 3
            opacity: 0.5
            text: root.payload && root.payload.received_at ? ("Updated " + new Date(root.payload.received_at).toLocaleString()) : ""
        }
    }
}
