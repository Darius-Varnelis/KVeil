// macOS-style user entry: small round avatar with a semibold name underneath.
// Same properties as org.kde.breeze.components UserDelegate so the model wiring is unchanged.
import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: wrapper

    property bool isCurrent: true

    property string name
    property string userName
    property string avatarPath
    property string iconSource
    property bool needsPassword
    property var vtNumber
    property bool constrainText: true
    property real fontSize: Kirigami.Theme.defaultFont.pointSize + 3
    property real faceSize: Kirigami.Units.gridUnit * 3
    property color textColor: "white"
    property bool lightBackdrop: false
    property string fontFamily: "SF Pro Text"
    property bool showLegibleShadows: true
    signal clicked()

    implicitWidth: Math.max(faceSize, nameLabel.implicitWidth)
    implicitHeight: faceSize + Kirigami.Units.smallSpacing + nameLabel.implicitHeight

    opacity: isCurrent ? 1.0 : 0.6

    Rectangle {
        id: faceFrame
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: wrapper.faceSize
        height: width
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.25)

        Image {
            id: face
            anchors.fill: parent
            source: wrapper.avatarPath
            sourceSize: Qt.size(wrapper.faceSize * Screen.devicePixelRatio, wrapper.faceSize * Screen.devicePixelRatio)
            fillMode: Image.PreserveAspectCrop
            visible: false
        }

        OpacityMask {
            anchors.fill: parent
            source: face
            visible: face.status === Image.Ready
            maskSource: Rectangle {
                width: faceFrame.width
                height: faceFrame.height
                radius: width / 2
                visible: false
            }
        }

        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: wrapper.faceSize * 0.18
            source: wrapper.iconSource
            visible: face.status !== Image.Ready
        }
    }

    PlasmaComponents3.Label {
        id: nameLabel
        anchors.top: faceFrame.bottom
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.horizontalCenter: parent.horizontalCenter
        text: wrapper.name
        textFormat: Text.PlainText
        font.family: wrapper.fontFamily !== "" ? wrapper.fontFamily : Kirigami.Theme.defaultFont.family
        font.styleName: wrapper.fontFamily === "SF Pro Text" ? "Semibold" : ""
        font.weight: Font.DemiBold
        font.pointSize: wrapper.fontSize
        font.underline: wrapper.activeFocus
        color: wrapper.textColor
        elide: Text.ElideRight
        layer.enabled: wrapper.showLegibleShadows
        layer.effect: LegibleShadow { light: wrapper.lightBackdrop }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: wrapper.clicked()
    }

    Keys.onSpacePressed: wrapper.clicked()

    Accessible.name: name
    Accessible.role: Accessible.Button
    function accessiblePressAction() { wrapper.clicked() }
}
