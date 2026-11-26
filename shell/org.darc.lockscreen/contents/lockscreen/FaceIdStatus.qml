// Biometric (Howdy Face ID / fprintd Fingerprint) status indicator for the lock screen.
// Shows scanning, success, failure, retry, and timeout states with matching icons and animations.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: root

    property string bioMode: "face" // "face" or "fingerprint"
    property string faceState: "" // "scanning", "success", "timeout", "dark", "error", "mismatch", "retry", or ""
    property bool lightBackdrop: false
    property string fontFamily: "SF Pro Text"
    property bool showLegibleShadows: true
    property color textColor: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.94) : Qt.rgba(1, 1, 1, 0.96)

    Behavior on textColor { ColorAnimation { duration: Kirigami.Units.longDuration } }

    implicitWidth: row.implicitWidth
    implicitHeight: faceState !== "" ? row.implicitHeight : 0
    Behavior on implicitHeight { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad } }

    opacity: faceState !== "" ? 1 : 0
    Behavior on opacity { OpacityAnimator { duration: Kirigami.Units.longDuration } }
    visible: opacity > 0

    layer.enabled: root.showLegibleShadows
    layer.effect: LegibleShadow { light: root.lightBackdrop }

    // Shake offset for failure animation (Translate keeps layout unaffected)
    property real _shakeX: 0

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing
        transform: Translate { x: root._shakeX }

        Kirigami.Icon {
            id: faceIcon
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            source: root.faceState === "success"
                ? Qt.resolvedUrl("icons/checkmark.svg")
                : (root.bioMode === "fingerprint"
                    ? Qt.resolvedUrl("icons/fingerprint.svg")
                    : Qt.resolvedUrl("icons/face-id.svg"))
            color: root.textColor
            isMask: true

            SequentialAnimation on opacity {
                running: root.faceState === "scanning"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.35; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.35; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) faceIcon.opacity = 1
            }
        }

        PlasmaComponents3.Label {
            text: {
                if (root.bioMode === "fingerprint") {
                    switch (root.faceState) {
                        case "scanning": return "Scan your fingerprint\u2026";
                        case "success":  return "Fingerprint recognized";
                        case "retry":    return "Try finger again";
                        case "mismatch":
                        case "timeout":  return "Fingerprint not recognized";
                        case "error":    return "Fingerprint failed";
                        default:         return "";
                    }
                }
                switch (root.faceState) {
                    case "scanning": return "Looking for you\u2026";
                    case "success":  return "Face recognized";
                    case "timeout":  return "Face not recognized";
                    case "dark":     return "Camera too dark";
                    case "error":    return "Face recognition failed";
                    default:         return "";
                }
            }
            color: root.textColor
            font.family: root.fontFamily !== "" ? root.fontFamily : Kirigami.Theme.defaultFont.family
            font.pointSize: Kirigami.Theme.smallFont.pointSize + 1
            font.styleName: root.fontFamily === "SF Pro Text" ? "Medium" : ""
            font.weight: Font.Medium
            textFormat: Text.PlainText
        }
    }

    // Brief shake on failure/timeout/dark states
    SequentialAnimation {
        id: shakeAnim
        PropertyAnimation { target: root; property: "_shakeX"; to: -6; duration: 50; easing.type: Easing.OutQuad }
        PropertyAnimation { target: root; property: "_shakeX"; to:  6; duration: 50; easing.type: Easing.OutQuad }
        PropertyAnimation { target: root; property: "_shakeX"; to: -4; duration: 50; easing.type: Easing.OutQuad }
        PropertyAnimation { target: root; property: "_shakeX"; to:  4; duration: 50; easing.type: Easing.OutQuad }
        PropertyAnimation { target: root; property: "_shakeX"; to:  0; duration: 50; easing.type: Easing.OutQuad }
    }

    onFaceStateChanged: {
        if (faceState === "timeout" || faceState === "dark" || faceState === "error" || faceState === "mismatch" || faceState === "retry") {
            shakeAnim.start();
        }
    }
}
