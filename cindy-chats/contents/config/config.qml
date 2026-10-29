import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root
    Layout.fillWidth: true

    Kirigami.FormData.label: i18n("Database path")
    PlasmaComponents.TextField {
        Layout.fillWidth: true
        text: plasmoid.configuration.cindyDbPath
        placeholderText: "/home/holty/.config/CindyGlobal/cindy-cmvsyhcia10i9yw01rst1i34s.db"
        onTextChanged: plasmoid.configuration.cindyDbPath = text
    }

    Kirigami.FormData.label: i18n("Poll interval (seconds)")
    PlasmaComponents.SpinBox {
        Layout.fillWidth: true
        minimum: 1
        maximum: 300
        value: plasmoid.configuration.pollInterval
        onValueChanged: plasmoid.configuration.pollInterval = value
    }

    Kirigami.FormData.label: i18n("Show idle chats in panel")
    PlasmaComponents.CheckBox {
        text: i18n("Show green idle dot in compact view")
        checked: !plasmoid.configuration.hideIdle
        onToggled: plasmoid.configuration.hideIdle = !checked
    }

    Kirigami.FormData.label: i18n("Request attention when waiting")
    PlasmaComponents.CheckBox {
        text: i18n("Highlight panel when chats are waiting for you")
        checked: plasmoid.configuration.attentionOnWaiting
        onToggled: plasmoid.configuration.attentionOnWaiting = checked
    }
}