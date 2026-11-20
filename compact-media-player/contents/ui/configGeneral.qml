import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_textScale: textScale.value
    property alias cfg_showAlbum: showAlbum.checked
    property alias cfg_showTimes: showTimes.checked
    property alias cfg_scrollTitle: scrollTitle.checked
    property alias cfg_volumeOnWheel: volumeOnWheel.checked
    property alias cfg_showBackdrop: showBackdrop.checked
    property alias cfg_backdropOpacity: backdropOpacity.value
    property alias cfg_useAlbumColours: useAlbumColours.checked

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        RowLayout {
            Kirigami.FormData.label: i18n("Text size:")

            QQC2.Slider {
                id: textScale
                from: 60
                to: 220
                stepSize: 10
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            }

            QQC2.Label {
                text: i18n("%1%", textScale.value)
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
            }
        }

        QQC2.Label {
            text: i18n("Sizes follow the widget; this scales them all.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showAlbum
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("Album name")
        }

        QQC2.CheckBox {
            id: showTimes
            text: i18n("Elapsed and total time")
        }

        QQC2.CheckBox {
            id: scrollTitle
            text: i18n("Scroll long titles")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: showBackdrop
            Kirigami.FormData.label: i18n("Album art backdrop:")
            text: i18n("Blur the cover behind the widget")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Backdrop strength:")
            enabled: showBackdrop.checked

            QQC2.Slider {
                id: backdropOpacity
                from: 0
                to: 80
                stepSize: 5
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            }

            QQC2.Label {
                text: i18n("%1%", backdropOpacity.value)
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
            }
        }

        QQC2.CheckBox {
            id: useAlbumColours
            Kirigami.FormData.label: i18n("Accent colour:")
            text: i18n("Pick it from the album art")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.CheckBox {
            id: volumeOnWheel
            Kirigami.FormData.label: i18n("Mouse:")
            text: i18n("Scroll wheel changes volume")
        }

        QQC2.Label {
            text: i18n("Middle click plays or pauses.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }
    }
}
