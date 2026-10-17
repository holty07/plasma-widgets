import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_herdrBinary: binaryField.text
    property alias cfg_pollInterval: intervalBox.value
    property alias cfg_hideIdle: hideIdleBox.checked
    property alias cfg_attentionOnBlocked: attentionBox.checked

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.TextField {
            id: binaryField
            Kirigami.FormData.label: i18n("herdr binary:")
            Layout.fillWidth: true
            placeholderText: "herdr"
        }

        QQC2.Label {
            text: i18n("Use an absolute path such as ~/.local/bin/herdr if plasmashell cannot find it on PATH.")
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: intervalBox
            Kirigami.FormData.label: i18n("Poll every:")
            from: 1
            to: 60
            textFromValue: function(value) { return i18np("%1 second", "%1 seconds", value) }
            valueFromText: function(text) { return parseInt(text) || 3 }
        }

        QQC2.CheckBox {
            id: hideIdleBox
            Kirigami.FormData.label: i18n("Panel:")
            text: i18n("Hide the idle count")
        }

        QQC2.CheckBox {
            id: attentionBox
            text: i18n("Draw attention when an agent is blocked")
        }
    }
}
