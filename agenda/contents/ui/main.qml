import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import "../../contents/code/ics.js" as ICS
import "../../contents/code/feeds.js" as Feeds

PlasmoidItem {
    id: root

    implicitWidth:  inPanel ? 300 : 380
    implicitHeight: inPanel ? 28  : 520

    readonly property bool inPanel: plasmoid.formFactor === 2 || plasmoid.formFactor === 3

    readonly property color cBase:   "#1e1e2e"
    readonly property color cSurf0:  "#313244"
    readonly property color cSurf1:  "#45475a"
    readonly property color cText:   "#cdd6f4"
    readonly property color cSub0:   "#a6adc8"
    readonly property color cSub1:   "#7f849c"
    readonly property color cMauve:  "#cba6f7"
    readonly property color cBlue:   "#89b4fa"
    readonly property color cGreen:  "#a6e3a1"
    readonly property color cPeach:  "#fab387"
    readonly property color cTeal:   "#94e2d5"
    readonly property color cPink:   "#f5c2e7"
    readonly property color cYellow: "#f9e2af"

    readonly property var accentColors: [cMauve, cBlue, cTeal, cPeach, cPink, cGreen, cYellow]

    readonly property var icsUrls: Feeds.urls

    property var allEvents: []
    property int fetchedCount: 0
    property var rawResults: []
    // Last good ICS text per feed. A failed fetch falls back to it instead of
    // blanking the agenda (this is what showed "Nothing left today" after resume).
    property var feedCache: []
    property var feedDone: []
    property var pendingXhrs: []
    property int fetchGeneration: 0
    property int failedCount: 0
    property bool loading: true
    property string lastUpdated: ""
    property var minuteClock: new Date()
    property real lastTickMs: Date.now()
    property string lastDayKey: new Date().toDateString()

    readonly property string feedStatus: failedCount === 0 ? ""
        : failedCount + "/" + icsUrls.length + " feeds offline" + (lastUpdated ? " · cached" : "")

    readonly property var nextEvent: {
        var _ = root.minuteClock;
        var now = new Date();
        for (var i = 0; i < allEvents.length; i++) {
            var e = allEvents[i];
            if (!e.allDay && e.end > now) return e;
        }
        return null;
    }

    function fetchAll() {
        fetchGeneration++;
        var stale = pendingXhrs;
        pendingXhrs = [];
        for (var p = 0; p < stale.length; p++) stale[p].abort();

        if (!lastUpdated) loading = true;
        fetchedCount = 0;
        failedCount = 0;
        rawResults = new Array(icsUrls.length).fill("");
        feedDone = new Array(icsUrls.length).fill(false);
        fetchWatchdog.restart();
        for (var i = 0; i < icsUrls.length; i++) { fetchFeed(i, fetchGeneration); }
    }

    function fetchFeed(index, gen) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", icsUrls[index], true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || gen !== root.fetchGeneration) return;
            var ok = xhr.status === 200 && xhr.responseText.indexOf("BEGIN:VCALENDAR") !== -1;
            if (!ok) console.warn("Agenda: feed " + index + " failed, status " + xhr.status);
            finishFeed(index, ok ? xhr.responseText : "");
        };
        pendingXhrs.push(xhr);
        xhr.send();
    }

    function finishFeed(index, text) {
        if (feedDone[index]) return;
        feedDone[index] = true;
        if (text) {
            rawResults[index] = text;
            feedCache[index] = text;
        } else {
            rawResults[index] = feedCache[index] || "";
            failedCount++;
        }
        fetchedCount++;
        if (fetchedCount === icsUrls.length) {
            fetchWatchdog.stop();
            pendingXhrs = [];
            processAll();
            if (failedCount > 0) retryTimer.restart();
        }
    }

    function processAll() {
        var combined = [];
        for (var i = 0; i < rawResults.length; i++) {
            if (rawResults[i]) {
                var events = ICS.parseICS(rawResults[i]);
                for (var j = 0; j < events.length; j++) {
                    events[j].colorIndex = combined.length % accentColors.length;
                    combined.push(events[j]);
                }
            }
        }
        combined.sort(function(a, b) {
            if (a.allDay && !b.allDay) return -1;
            if (!a.allDay && b.allDay) return 1;
            return a.start - b.start;
        });
        for (var k = 0; k < combined.length; k++) combined[k].colorIndex = k % accentColors.length;
        allEvents = combined;
        loading = false;
        if (failedCount < icsUrls.length) lastUpdated = Qt.formatTime(new Date(), "h:mm AP");
    }

    Timer {
        interval: 15 * 60 * 1000
        running: true; repeat: true
        onTriggered: root.fetchAll()
    }

    // Requests can hang on dead sockets after suspend; give up and use the cache.
    Timer {
        id: fetchWatchdog
        interval: 30 * 1000
        onTriggered: {
            for (var i = 0; i < root.icsUrls.length; i++) root.finishFeed(i, "");
            var stale = root.pendingXhrs;
            root.fetchGeneration++;
            for (var p = 0; p < stale.length; p++) stale[p].abort();
        }
    }

    Timer {
        id: retryTimer
        interval: 60 * 1000
        onTriggered: root.fetchAll()
    }

    Timer {
        id: pruneTimer
        interval: 60 * 1000
        running: true; repeat: true
        onTriggered: {
            var nowMs = Date.now();
            // A tick gap means we just resumed from suspend; a new date means
            // "today" moved. Either way the parsed agenda is stale, so refetch.
            var resumed = nowMs - root.lastTickMs > 3 * 60 * 1000;
            var dayKey = new Date(nowMs).toDateString();
            var newDay = dayKey !== root.lastDayKey;
            root.lastTickMs = nowMs;
            root.lastDayKey = dayKey;
            root.minuteClock = new Date(nowMs);
            if (resumed || newDay) { root.fetchAll(); return; }

            var now = new Date(nowMs);
            var pruned = root.allEvents.filter(function(e) { return e.allDay || e.end > now; });
            if (pruned.length !== root.allEvents.length) root.allEvents = pruned;
        }
    }

    Component.onCompleted: fetchAll()

    function todayHeader() {
        var d = new Date();
        var days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
        var months = ["January","February","March","April","May","June",
        "July","August","September","October","November","December"];
        return days[d.getDay()] + ", " + d.getDate() + " " + months[d.getMonth()];
    }

    // PANEL MODE
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        visible: root.inPanel

        Rectangle {
            id: accentBar
            width: 4
            height: parent.height * 0.7
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            radius: 2
            color: root.loading ? root.cSub1
            : root.nextEvent ? root.accentColors[root.nextEvent.colorIndex]
            : root.cGreen
        }

        ColumnLayout {
            anchors.left: accentBar.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width:parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: root.cText
                font.pixelSize: 11
                font.bold: true
                font.family: "monospace"
                text: {
                    var _ = root.minuteClock;
                    if (root.loading) return "Loading...";
                    var e = root.nextEvent;
                    if (!e) return root.failedCount === root.icsUrls.length && root.allEvents.length === 0 ? "Calendar offline" : "Nothing left today";
                    return e.summary;
                }
            }

            Text {
                width:parent.width
                color: root.nextEvent ? root.accentColors[root.nextEvent.colorIndex] : root.cSub1
                font.pixelSize: 10
                font.family: "monospace"
                visible: !root.loading && root.nextEvent !== null
                text: {
                    var _ = root.minuteClock;
                    var e = root.nextEvent;
                    if (!e) return "";
                    return e.startStr + "  →  " + ICS.formatTime(e.end, false) + "   " + ICS.endsIn(e.start, e.end);
                }
            }
        }
    }

    // DESKTOP MODE
    Rectangle {
        anchors.fill: parent
        color: root.cBase
        radius: 12
        visible: !root.inPanel

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 12

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: root.minuteClock ? root.todayHeader() : root.todayHeader()
                        color: root.cText
                        font.pixelSize: Math.max(14, root.height * 0.038)
                        font.bold: true
                        font.family: "monospace"
                    }
                    Text {
                        visible: root.feedStatus !== ""
                        text: "⚠ " + root.feedStatus
                        color: root.cPeach
                        font.pixelSize: Math.max(10, root.height * 0.025)
                        font.family: "monospace"
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 28; height: 28; radius: 6
                    color: refreshMouse.containsMouse ? root.cSurf1 : root.cSurf0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "↻"; color: root.cMauve; font.pixelSize: 16 }
                    MouseArea {
                        id: refreshMouse
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.fetchAll()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.cSurf1; Layout.bottomMargin: 12 }

            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: root.loading
                Text { anchors.centerIn: parent; text: "Loading calendars..."; color: root.cSub1; font.pixelSize: 13; font.family: "monospace" }
            }

            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: !root.loading && root.allEvents.length === 0
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 8
                    Text { Layout.alignment: Qt.AlignHCenter; text: "✓"; color: root.cGreen; font.pixelSize: 32 }
                    Text { Layout.alignment: Qt.AlignHCenter; text: root.failedCount === root.icsUrls.length ? "Calendar offline" : "Nothing left today"; color: root.cSub0; font.pixelSize: 13; font.family: "monospace" }
                    Text { Layout.alignment: Qt.AlignHCenter; text: root.lastUpdated ? "Updated " + root.lastUpdated : "Retrying…"; color: root.cSub1; font.pixelSize: 11; font.family: "monospace" }
                }
            }

            ListView {
                id: eventList
                Layout.fillWidth: true; Layout.fillHeight: true
                visible: !root.loading && root.allEvents.length > 0
                clip: true; spacing: 8
                model: root.allEvents

                delegate: Rectangle {
                    width: eventList.width
                    height: eventCol.implicitHeight + 16
                    radius: 8; color: root.cSurf0

                    Rectangle {
                        width: 3; height: parent.height - 12
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 2
                        color: root.accentColors[modelData.colorIndex]
                    }

                    ColumnLayout {
                        id: eventCol
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: modelData.startStr; color: root.accentColors[modelData.colorIndex]; font.pixelSize: Math.max(10, root.height * 0.022); font.bold: true; font.family: "monospace" }
                            Text { visible: !modelData.allDay && modelData.end; text: "→ " + ICS.formatTime(modelData.end, false); color: root.cSub1; font.pixelSize: Math.max(10, root.height * 0.022); font.family: "monospace" }
                            Item { Layout.fillWidth: true }
                            Text { visible: !modelData.allDay && modelData.end; text: root.minuteClock ? ICS.endsIn(modelData.start, modelData.end) : ICS.endsIn(modelData.start, modelData.end); color: root.cSub1; font.pixelSize: Math.max(10, root.height * 0.022); font.family: "monospace" }
                        }

                        Text { Layout.fillWidth: true; text: modelData.summary; color: root.cText; font.pixelSize: Math.max(12, root.height * 0.028); font.bold: true; font.family: "monospace"; wrapMode: Text.WordWrap }
                        Text { visible: modelData.location !== ""; text: "📍 " + modelData.location; color: root.cSub0; font.pixelSize: Math.max(10, root.height * 0.022); font.family: "monospace"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                }
            }

            Text { visible: !root.loading && root.allEvents.length > 0; Layout.alignment: Qt.AlignRight; Layout.topMargin: 8; text: "Updated " + root.lastUpdated; color: root.cSub1; font.pixelSize: 10; font.family: "monospace" }
        }
    }
}
