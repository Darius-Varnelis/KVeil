// Small frosted round icon button with the action name underneath (macOS login-window style).
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

QQC2.AbstractButton {
    id: button

    property bool lightBackdrop: false
    property bool showLegibleShadows: true
    readonly property color fg: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.85) : "white"

    focusPolicy: Qt.TabFocus
    // fixed width so the circles are evenly spaced and the row stays centred regardless of label length
    implicitWidth: Kirigami.Units.gridUnit * 5
    padding: 0
    implicitHeight: circle.height + Kirigami.Units.smallSpacing + label.implicitHeight

    Accessible.name: text.replace("&", "")

    contentItem: Item {
        Rectangle {
            id: circle
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: Kirigami.Units.gridUnit * 2
            height: width
            radius: width / 2
            readonly property real baseAlpha: button.lightBackdrop ? 0.45 : 0.18
            color: Qt.rgba(1, 1, 1, button.pressed ? baseAlpha + 0.17 : (button.hovered ? baseAlpha + 0.1 : baseAlpha))
            border.width: button.visualFocus ? 2 : 0
            border.color: Kirigami.Theme.highlightColor
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.small
                height: width
                source: button.icon.name
                color: button.fg
                isMask: true
            }
        }

        PlasmaComponents3.Label {
            id: label
            anchors.top: circle.bottom
            anchors.topMargin: Kirigami.Units.smallSpacing
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: button.text.replace("&", "")
            textFormat: Text.PlainText
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: button.fg
            layer.enabled: button.showLegibleShadows
            layer.effect: LegibleShadow { light: button.lightBackdrop }
        }
    }
    background: null
}
