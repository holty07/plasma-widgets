import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.private.mpris as Mpris

KCM.SimpleKCM {
    id: page

    property alias cfg_pinPlayer: pinPlayer.checked
    property string cfg_pinnedPlayer: ""

    // Its own model instance, so probing it cannot disturb the widget's.
    Mpris.Mpris2Model { id: probe }

    property var detected: []

    // Reading a row's container means moving currentIndex, so put it back.
    function scan() {
        var out = [];
        var saved = probe.currentIndex;
        var n = 0;
        try { n = probe.rowCount(); } catch (e) { n = 0; }

        for (var i = 0; i < n; ++i) {
            probe.currentIndex = i;
            var p = probe.currentPlayer;
            if (!p) continue;
            var entry = p.desktopEntry ? String(p.desktopEntry) : "";
            var identity = p.identity ? String(p.identity) : "";
            if (entry === "" && identity === "") continue;
            out.push({
                value: entry !== "" ? entry : identity,
                identity: identity,
                entry: entry
            });
        }

        probe.currentIndex = saved;
        page.detected = out;
    }

    Component.onCompleted: scan()

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.CheckBox {
            id: pinPlayer
            Kirigami.FormData.label: i18n("Player:")
            text: i18n("Only ever follow one player")
        }

        QQC2.Label {
            text: i18n("Off, the widget follows whatever started playing most recently — including notification sounds and browser tabs, which it won't hand back.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        Item { Kirigami.FormData.isSection: true }

        RowLayout {
            Kirigami.FormData.label: i18n("Follow:")
            enabled: pinPlayer.checked

            QQC2.ComboBox {
                id: playerBox
                editable: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                model: page.detected.map(function (d) { return d.value; })
                editText: page.cfg_pinnedPlayer

                onActivated: page.cfg_pinnedPlayer = editText
                onEditTextChanged: if (activeFocus) page.cfg_pinnedPlayer = editText
            }

            QQC2.Button {
                icon.name: "view-refresh"
                text: i18n("Rescan")
                onClicked: page.scan()
            }
        }

        QQC2.Label {
            text: i18n("Matched against the player's desktop entry first, then its identity. Start the app before rescanning.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        Item { Kirigami.FormData.isSection: true }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Detected now:")
            spacing: Kirigami.Units.smallSpacing / 2

            QQC2.Label {
                visible: page.detected.length === 0
                text: i18n("Nothing is registered on MPRIS right now.")
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }

            Repeater {
                model: page.detected

                delegate: RowLayout {
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: modelData.identity !== "" ? modelData.identity : i18n("(no identity)")
                        font.weight: Font.DemiBold
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }

                    QQC2.Label {
                        text: modelData.entry !== "" ? modelData.entry : i18n("(no desktop entry)")
                        opacity: 0.7
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }

                    QQC2.Button {
                        text: i18n("Use")
                        enabled: pinPlayer.checked
                        onClicked: {
                            page.cfg_pinnedPlayer = modelData.value;
                            playerBox.editText = modelData.value;
                        }
                    }
                }
            }
        }
    }
}
