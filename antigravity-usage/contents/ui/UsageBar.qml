import QtQuick

Item {
    id: bar
    property var percent: null
    property color barColor: "#a6e3a1"
    implicitHeight: 10

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "#313244" // Catppuccin Mocha surface0
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: height / 2
        color: bar.barColor
        width: bar.percent === null ? 0 : parent.width * Math.max(0, Math.min(100, bar.percent)) / 100

        Behavior on width {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
    }
}
