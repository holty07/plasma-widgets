import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_visualiserMode: "strip"
    property alias cfg_barThickness: barThickness.value
    property alias cfg_barGap: barGap.value
    property alias cfg_framerate: framerate.value
    property alias cfg_mirrorBars: mirrorBars.checked
    property alias cfg_autoManageCava: autoManageCava.checked
    property alias cfg_cavaService: cavaService.text

    readonly property var modes: ["strip", "background", "off"]

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.ComboBox {
            id: modeBox
            Kirigami.FormData.label: i18n("Draw bars:")
            model: [
                i18n("As a strip above the controls"),
                i18n("Across the background"),
                i18n("Don't draw them")
            ]
            currentIndex: Math.max(0, page.modes.indexOf(page.cfg_visualiserMode))
            onActivated: page.cfg_visualiserMode = page.modes[currentIndex]
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Bar width:")
            enabled: page.cfg_visualiserMode !== "off"

            QQC2.SpinBox {
                id: barThickness
                from: 1
                to: 24
            }
            QQC2.Label { text: i18n("px") }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Gap between bars:")
            enabled: page.cfg_visualiserMode !== "off"

            QQC2.SpinBox {
                id: barGap
                from: 0
                to: 16
            }
            QQC2.Label { text: i18n("px") }
        }

        QQC2.CheckBox {
            id: mirrorBars
            Kirigami.FormData.label: i18n("Style:")
            text: i18n("Mirror the bars")
            enabled: page.cfg_visualiserMode !== "off"
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Poll rate:")
            enabled: page.cfg_visualiserMode !== "off"

            QQC2.SpinBox {
                id: framerate
                from: 5
                to: 30
                stepSize: 1
            }
            QQC2.Label { text: i18n("polls per second") }
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.Label {
            text: i18n("Each poll runs a short command, so this is capped at 30. Bars interpolate between polls, so 20 already looks smooth.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: autoManageCava
            Kirigami.FormData.label: i18n("Helper service:")
            text: i18n("Start and stop cava with playback")
        }

        QQC2.TextField {
            id: cavaService
            Kirigami.FormData.label: i18n("Service name:")
            enabled: autoManageCava.checked
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        }

        QQC2.Label {
            text: i18n("Bars only move while cava-plasmoid-bridge is running. Leaving this on keeps it off when nothing is playing.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        }
    }
}
