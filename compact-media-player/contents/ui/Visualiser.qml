/*
 * Visualiser.qml
 *
 * Draws cava levels as bars. Bar count derives from the available width and
 * the configured thickness, so the widget re-bars itself as you resize it.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: vis

    property var levels: []
    property color baseColour: Kirigami.Theme.highlightColor
    property color peakColour: Qt.lighter(baseColour, 1.45)
    property real barThickness: 4
    property real barGap: 2
    property bool mirrored: false
    property int smoothing: 90          // ms of easing between frames
    property real minimumHeight: 1      // px floor so silence still shows a line
    property real topOpacity: 1.0
    property real bottomOpacity: 1.0

    // Derived: how many bars actually fit.
    readonly property int count: Math.max(3,
        Math.floor((width + barGap) / Math.max(1, barThickness + barGap)))

    readonly property real slot: count > 0 ? (width - barGap * (count - 1)) / count : 0
    readonly property real usableHeight: mirrored ? height / 2 : height

    // Resample here rather than at the source. The source has no idea how wide
    // this instance is, and there can be more than one instance at different
    // widths, so each one maps the incoming frame onto its own bar count.
    readonly property var scaled: resample(levels, count)

    function resample(arr, n) {
        if (!arr || arr.length === 0 || n <= 0) return [];
        if (arr.length === n) return arr;

        var out = new Array(n);
        if (arr.length > n) {
            // Max-pool downward so peaks survive.
            var ratio = arr.length / n;
            for (var i = 0; i < n; ++i) {
                var st = Math.floor(i * ratio);
                var en = Math.max(st + 1, Math.floor((i + 1) * ratio));
                var m = 0;
                for (var j = st; j < en && j < arr.length; ++j) {
                    if (arr[j] > m) m = arr[j];
                }
                out[i] = m;
            }
        } else {
            // Interpolate upward so wide widgets do not get gaps.
            for (var k = 0; k < n; ++k) {
                var pos = n > 1 ? (k / (n - 1)) * (arr.length - 1) : 0;
                var lo = Math.floor(pos);
                var hi = Math.min(arr.length - 1, lo + 1);
                var f = pos - lo;
                out[k] = arr[lo] * (1 - f) + arr[hi] * f;
            }
        }
        return out;
    }

    Repeater {
        model: vis.count

        delegate: Item {
            id: slotItem
            required property int index

            readonly property real level: {
                var l = vis.scaled;
                if (!l || index >= l.length) return 0;
                var v = l[index];
                return isNaN(v) ? 0 : Math.max(0, Math.min(100, v)) / 100;
            }

            x: index * (vis.slot + vis.barGap)
            width: vis.slot
            height: vis.height

            Rectangle {
                id: upper
                width: parent.width
                height: Math.max(vis.minimumHeight, vis.usableHeight * slotItem.level)
                y: vis.mirrored ? (vis.height / 2) - height : vis.height - height
                radius: Math.min(width / 2, Kirigami.Units.smallSpacing)
                opacity: vis.topOpacity
                antialiasing: true

                gradient: Gradient {
                    GradientStop { position: 0.0; color: vis.peakColour }
                    GradientStop { position: 1.0; color: vis.baseColour }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: vis.smoothing
                        easing.type: Easing.OutQuad
                    }
                }
            }

            Rectangle {
                visible: vis.mirrored
                width: parent.width
                height: upper.height * 0.6
                y: vis.height / 2
                radius: upper.radius
                opacity: vis.bottomOpacity * 0.45
                antialiasing: true

                gradient: Gradient {
                    GradientStop { position: 0.0; color: vis.baseColour }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }
    }
}
