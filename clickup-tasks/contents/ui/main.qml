import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Desktop: show the task list; panel: show the counts and expand on click.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
                             ? fullRepresentation : compactRepresentation

    // The helper ships inside the package and reads
    // ~/.config/clickup-tasks/config.json. Quote the path: the dev checkout
    // lives under "Plasma Widgets" and the engine runs it through a shell.
    readonly property string clickupScript:
        Qt.resolvedUrl("../code/clickup.py").toString().replace(/^file:\/\//, "")
    readonly property string clickupCommand: "python3 '" + root.clickupScript + "'"

    // Last known counts; -1 until the first fetch succeeded.
    property int countOverdue: -1
    property int countOpen: -1
    property int countDone: -1
    property int countTotal: -1
    property string stateError: ""
    property var taskList: []
    property bool hasData: false
    property bool fetching: false

    // True once at least one fetch succeeded.
    readonly property bool loaded: root.hasData

    readonly property int shownOverdue: Math.max(0, root.countOverdue)
    readonly property int shownOpen: Math.max(0, root.countOpen)
    readonly property int shownDone: Math.max(0, root.countDone)
    readonly property int shownTotal: Math.max(0, root.countTotal)

    toolTipMainText: i18n("ClickUp tasks")
    toolTipSubText: root.stateError !== "" ? root.stateError
                  : !root.loaded ? i18n("Fetching tasks…")
                  : i18n("%1 overdue · %2 open · %3 done",
                         root.shownOverdue, root.shownOpen, root.shownDone)

    // One-shot runs: connect, read the JSON payload, disconnect. The helper
    // prints { received_at, ok, counts:{overdue,open,done,total}, tasks:[...],
    // error } on stdout even when it fails.
    Plasma5Support.DataSource {
        id: fetchSource
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            root.fetching = false
            var stdout = (data["stdout"] || "").trim()
            var payload = null
            try {
                payload = stdout ? JSON.parse(stdout) : null
            } catch (e) {
                payload = null
            }
            if (!payload) {
                root.stateError = (data["stderr"] || "").trim() || i18n("Could not parse fetch output")
                return
            }
            root.stateError = payload.error || ""
            if (!payload.ok)
                return
            root.taskList = Array.isArray(payload.tasks) ? payload.tasks : []
            root.countOverdue = payload.counts.overdue
            root.countOpen = payload.counts.open
            root.countDone = payload.counts.done
            root.countTotal = payload.counts.total
            root.hasData = true
        }
    }

    function refresh() {
        if (root.fetching)
            return
        root.fetching = true
        fetchSource.connectSource(root.clickupCommand)
    }

    // ClickUp rate-limits at 100 requests/minute per token; a fetch costs a
    // handful, so every 5 minutes is plenty.
    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    function groupColor(bucket) {
        return bucket === "overdue" ? "#f38ba8"
             : bucket === "open"    ? "#f9e2af"
             : "#a6e3a1"
    }

    function formatDue(ms) {
        if (!ms)
            return ""
        var due = new Date(ms)
        var today = new Date()
        today.setHours(0, 0, 0, 0)
        var day = new Date(due)
        day.setHours(0, 0, 0, 0)
        var diff = Math.round((day - today) / 86400000)
        if (diff === 0) return i18n("Due today")
        if (diff === 1) return i18n("Due tomorrow")
        if (diff === -1) return i18n("Due yesterday")
        return i18n("Due %1", Qt.formatDate(due, diff > -7 && diff < 7 ? "ddd" : "d MMM"))
    }

    // ---- Panel compact representation ----
    compactRepresentation: MouseArea {
        Layout.minimumWidth: compactRow.implicitWidth
        Layout.preferredWidth: compactRow.implicitWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                source: "view-list-details"
            }
            PlasmaComponents.Label {
                visible: root.loaded && root.shownOverdue > 0
                text: root.shownOverdue
                color: root.groupColor("overdue")
                font.bold: true
            }
            PlasmaComponents.Label {
                text: root.loaded ? root.shownOpen : (root.stateError !== "" ? "!" : "…")
                font.bold: true
            }
        }
    }

    // ---- Desktop / popup full representation ----
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 4
                text: i18n("ClickUp tasks")
            }

            Repeater {
                model: [
                    { label: i18n("Overdue"), bucket: "overdue", count: root.shownOverdue },
                    { label: i18n("Open"),    bucket: "open",    count: root.shownOpen },
                    { label: i18n("Done"),    bucket: "done",    count: root.shownDone }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    spacing: 0
                    visible: root.loaded

                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData.count
                        font.bold: true
                        color: root.groupColor(modelData.bucket)
                    }
                    PlasmaComponents.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData.label
                        opacity: 0.65
                        font: Kirigami.Theme.smallFont
                    }
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                enabled: !root.fetching
                onClicked: root.refresh()
                PlasmaComponents.ToolTip { text: i18n("Refresh") }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: root.stateError !== ""
            text: root.stateError
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.stateError === "" && (!root.loaded || root.taskList.length === 0)
            text: !root.loaded ? i18n("Fetching tasks…") : i18n("Nothing assigned to you")
            opacity: 0.7
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.loaded && root.taskList.length > 0

            ListView {
                model: root.taskList
                clip: true
                spacing: Kirigami.Units.smallSpacing

                delegate: MouseArea {
                    id: taskRow
                    required property var modelData
                    width: ListView.view.width
                    implicitHeight: taskColumn.implicitHeight + Kirigami.Units.smallSpacing * 2
                    hoverEnabled: true
                    cursorShape: modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (modelData.url) Qt.openUrlExternally(modelData.url)

                    Rectangle {
                        anchors.fill: parent
                        radius: Kirigami.Units.smallSpacing
                        color: Kirigami.Theme.highlightColor
                        opacity: taskRow.containsMouse ? 0.15 : 0
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            Layout.fillHeight: true
                            implicitWidth: 3
                            radius: 1
                            color: root.groupColor(taskRow.modelData.bucket)
                        }

                        ColumnLayout {
                            id: taskColumn
                            Layout.fillWidth: true
                            spacing: 0

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: taskRow.modelData.name
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: [taskRow.modelData.status,
                                       taskRow.modelData.list,
                                       root.formatDue(taskRow.modelData.due)]
                                      .filter(function(s) { return !!s }).join(" · ")
                                color: taskRow.modelData.bucket === "overdue"
                                       ? root.groupColor("overdue") : Kirigami.Theme.textColor
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
