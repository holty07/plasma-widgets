/*
 * SeekBar.qml
 *
 * A hairline progress track that thickens on hover. Click or drag to seek.
 * Positions are in microseconds, matching MPRIS.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: seek

    property real position: 0
    property real length: 0
    property bool seekable: true
    property color accent: Kirigami.Theme.highlightColor

    signal seekRequested(real microseconds)

    readonly property real fraction: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
    readonly property bool interacting: mouse.containsMouse || mouse.pressed

    implicitHeight: Kirigami.Units.gridUnit * 0.75

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: seek.interacting && seek.seekable ? 5 : 3
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.22)

        Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Rectangle {
            id: fill
            width: parent.width * (mouse.pressed && seek.seekable ? mouse.dragFraction : seek.fraction)
            height: parent.height
            radius: parent.radius
            color: seek.accent

            Behavior on width {
                enabled: !mouse.pressed
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            id: handle
            x: Math.max(0, Math.min(track.width - width, fill.width - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: Kirigami.Units.gridUnit * 0.6
            height: width
            radius: width / 2
            color: seek.accent
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.25)
            opacity: seek.interacting && seek.seekable ? 1 : 0
            scale: opacity

            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.topMargin: -Kirigami.Units.smallSpacing
        anchors.bottomMargin: -Kirigami.Units.smallSpacing
        hoverEnabled: true
        enabled: seek.seekable && seek.length > 0
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        preventStealing: true

        property real dragFraction: 0

        function fractionAt(x) {
            return Math.max(0, Math.min(1, x / Math.max(1, width)));
        }

        onPressed: (e) => dragFraction = fractionAt(e.x)
        onPositionChanged: (e) => { if (pressed) dragFraction = fractionAt(e.x) }
        onReleased: (e) => {
            dragFraction = fractionAt(e.x);
            seek.seekRequested(dragFraction * seek.length);
        }
    }
}
