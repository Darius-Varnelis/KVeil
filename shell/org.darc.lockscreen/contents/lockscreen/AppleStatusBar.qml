// macOS-style status items in the top-right corner: keyboard layout, battery %, Wi-Fi.
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.battery
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property bool lightBackdrop: false
    property bool showKeyboardLayout: true
    property bool showBattery: true
    property bool showNetwork: true
    property bool showLegibleShadows: true
    property color textColor: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.92) : Qt.rgba(1, 1, 1, 0.96)
    Behavior on textColor { ColorAnimation { duration: Kirigami.Units.longDuration } }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: textColor
    readonly property int iconSize: Kirigami.Units.iconSizes.small

    spacing: Kirigami.Units.largeSpacing * 2
    layer.enabled: root.showLegibleShadows
    layer.effect: LegibleShadow { light: root.lightBackdrop }

    PW.KeyboardLayoutSwitcher {
        id: layoutSwitcher
        Layout.preferredWidth: layoutRow.implicitWidth
        Layout.preferredHeight: layoutRow.implicitHeight
        visible: root.showKeyboardLayout && layoutSwitcher.layoutNames.shortName !== ""
        Accessible.description: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to change keyboard layout", "Switch layout")

        RowLayout {
            id: layoutRow
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: layoutSwitcher.layoutNames.displayName || layoutSwitcher.layoutNames.shortName.toUpperCase()
                textFormat: Text.PlainText
                font.styleName: "Semibold"
                color: root.textColor
            }
            Kirigami.Icon {
                Layout.preferredWidth: root.iconSize
                Layout.preferredHeight: root.iconSize
                // Bundled Breeze SVG so icon-theme overrides and non-Arch icon paths work reliably
                source: Qt.resolvedUrl("icons/globe-symbolic.svg")
                color: root.textColor
                isMask: true
            }
        }
    }

    RowLayout {
        visible: root.showBattery && batteryControl.hasInternalBatteries
        spacing: Kirigami.Units.smallSpacing

        BatteryControlModel {
            id: batteryControl
        }

        PlasmaComponents3.Label {
            text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "%1%", batteryControl.percent)
            textFormat: Text.PlainText
            font.styleName: "Semibold"
            color: root.textColor
            Accessible.name: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Battery at %1%", batteryControl.percent)
        }
        // monochrome bundled Breeze battery so it can follow the light/dark text colour (PW.BatteryIcon can't)
        Kirigami.Icon {
            readonly property string level: String(Math.min(100, Math.round(batteryControl.percent / 10) * 10)).padStart(3, "0")
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            source: Qt.resolvedUrl("icons/battery-" + level
                    + (batteryControl.pluggedIn && level !== "100" ? "-charging" : "") + "-symbolic.svg")
            color: root.textColor
            isMask: true
        }
    }

    PlasmaNM.ConnectionIcon {
        id: connectionIcon
    }

    Kirigami.Icon {
        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        source: connectionIcon.connectionIcon
        visible: root.showNetwork && source !== ""
        color: root.textColor
        isMask: true
    }
}
