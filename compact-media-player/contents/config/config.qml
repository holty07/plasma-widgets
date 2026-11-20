import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Player")
        icon: "audio-headphones"
        source: "configPlayer.qml"
    }
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-theme"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Visualiser")
        icon: "media-playback-start"
        source: "configVisualiser.qml"
    }
}
