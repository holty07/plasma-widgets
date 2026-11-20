/*
 * MarqueeText.qml
 *
 * Elides by default; scrolls instead when the text overflows and scrolling is
 * enabled. Resets cleanly whenever the track changes.
 */
import QtQuick
import org.kde.plasma.components as PC3

Item {
    id: marquee

    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property bool scrolling: true
    property int pauseDuration: 2200
    property real pixelsPerSecond: 28

    readonly property bool overflowing: label.implicitWidth > width + 1

    implicitHeight: label.implicitHeight
    implicitWidth: label.implicitWidth
    clip: true

    PC3.Label {
        id: label
        x: 0
        width: marquee.overflowing && marquee.scrolling ? implicitWidth : marquee.width
        height: marquee.height
        elide: marquee.overflowing && marquee.scrolling ? Text.ElideNone : Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
    }

    onTextChanged: restart()
    onWidthChanged: restart()
    onScrollingChanged: restart()

    function restart() {
        anim.stop();
        label.x = 0;
        if (overflowing && scrolling) anim.restart();
    }

    SequentialAnimation {
        id: anim
        loops: Animation.Infinite

        PauseAnimation { duration: marquee.pauseDuration }

        NumberAnimation {
            target: label
            property: "x"
            to: Math.min(0, marquee.width - label.implicitWidth)
            duration: Math.max(600,
                (label.implicitWidth - marquee.width) / Math.max(1, marquee.pixelsPerSecond) * 1000)
            easing.type: Easing.Linear
        }

        PauseAnimation { duration: marquee.pauseDuration }

        NumberAnimation {
            target: label
            property: "x"
            to: 0
            duration: 450
            easing.type: Easing.InOutQuad
        }
    }
}
