// macOS-style replacement for org.kde.breeze.components SessionManagementScreen.
// Keeps its API (MainBlock/LockScreenUi rely on it) but lays everything out at the
// bottom of the screen: avatar, name, then a hint that turns into the password pill.
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

FocusScope {
    id: root

    property alias notificationMessage: notificationsLabel.text
    property alias actionItems: actionItemsLayout.children
    property alias actionItemsVisible: actionItemsLayout.visible
    property alias userListModel: userListView.model
    property alias userListCurrentIndex: userListView.currentIndex
    property alias userListCurrentItem: userListView.currentItem
    property bool showUserList: true
    property alias userList: userListView
    property real fontSize: Kirigami.Theme.defaultFont.pointSize + 2
    property Item authenticationTypeItem: null

    // Biometric (Howdy Face ID or fprintd Fingerprint) status
    property string bioMode: "face" // "face" or "fingerprint"
    property string faceState: ""
    readonly property bool _bioIndicatorEnabled: bioMode === "fingerprint" ? fingerprintStatusEnabled : faceStatusEnabled
    // Stays true once biometric recognition has failed/timed out
    property bool _faceFailed: false
    onFaceStateChanged: {
        if (faceState === "timeout" || faceState === "dark" || faceState === "error" || faceState === "mismatch")
            _faceFailed = true;
        else if (faceState === "scanning" || faceState === "success")
            _faceFailed = false;
    }

    // When false only the hint is shown; the prompts fade in when this turns true
    property bool promptVisible: true
    property string hintText
    // User-configurable lock screen preferences
    property bool showAvatar: true
    property bool faceStatusEnabled: true
    property bool fingerprintStatusEnabled: true
    property bool irPreviewEnabled: true
    property bool irPreviewTracking: true
    property bool irPreviewMirror: true
    property bool irPreviewShimmer: true
    property real irPreviewScale: 1.0
    property int irPreviewLingerMs: 1200
    property bool irPreviewDismissible: true
    property bool frostedGlass: true
    property string fontFamily: "SF Pro Text"
    property bool showLegibleShadows: true

    // true when the wallpaper behind the block is bright -> dark text, lighter pill
    property bool lightBackdrop: false
    // wallpaper item owned by this window (for frosted glass on the IR camera popup)
    property Item backdropItem: null
    property color textColor: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.95) : "white"
    property color textColorDim: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.88) : Qt.rgba(1, 1, 1, 0.92)
    Behavior on textColor { ColorAnimation { duration: Kirigami.Units.longDuration } }
    Behavior on textColorDim { ColorAnimation { duration: Kirigami.Units.longDuration } }

    default property alias _children: innerLayout.children

    signal userSelected()

    function playHighlightAnimation() {
        bounceAnimation.start();
    }

    // Floating IR camera preview pop-up above the user avatar while Howdy scans
    IrCameraPopup {
        id: irPopup
        anchors.horizontalCenter: column.horizontalCenter
        anchors.bottom: column.top
        anchors.bottomMargin: Kirigami.Units.largeSpacing
        faceState: root.bioMode === "face" ? root.faceState : ""
        lightBackdrop: root.lightBackdrop
        backdropItem: root.backdropItem
        previewEnabled: root.irPreviewEnabled && root.bioMode === "face"
        previewTracking: root.irPreviewTracking
        mirrorFeed: root.irPreviewMirror
        showShimmer: root.irPreviewShimmer
        popupScale: root.irPreviewScale
        lingerMs: root.irPreviewLingerMs
        dismissible: root.irPreviewDismissible
        frostedGlass: root.frostedGlass
        fontFamily: root.fontFamily
    }

    ColumnLayout {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: actionItemsLayout.top
        anchors.bottomMargin: Kirigami.Units.gridUnit
        width: Math.min(parent.width, Kirigami.Units.gridUnit * 16)
        spacing: Kirigami.Units.smallSpacing

        ListView {
            id: userListView
            visible: root.showAvatar && root.showUserList
            Layout.fillWidth: true
            Layout.preferredHeight: currentItem ? currentItem.implicitHeight : Kirigami.Units.gridUnit * 4
            orientation: ListView.Horizontal
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: width / 2 - Kirigami.Units.gridUnit * 4
            preferredHighlightEnd: preferredHighlightBegin
            interactive: count > 1
            activeFocusOnTab: true

            signal userSelected()
            onUserSelected: root.userSelected()
            Keys.onEscapePressed: userSelected()

            delegate: AppleUserDelegate {
                required property int index
                required property string icon
                required property string realName
                required property var model
                width: Kirigami.Units.gridUnit * 8
                height: implicitHeight
                avatarPath: icon || ""
                iconSource: model.iconName || "user-identity"
                name: realName || model.name
                userName: model.name
                needsPassword: model.needsPassword !== undefined ? model.needsPassword : true
                isCurrent: ListView.isCurrentItem
                textColor: root.textColor
                lightBackdrop: root.lightBackdrop
                fontFamily: root.fontFamily
                showLegibleShadows: root.showLegibleShadows
                onClicked: {
                    ListView.view.currentIndex = index;
                    ListView.view.userSelected();
                }
            }
        }

        // Biometric status (Howdy Face ID or fprintd Fingerprint): icon + label between avatar and password
        FaceIdStatus {
            visible: root._bioIndicatorEnabled && opacity > 0
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing
            bioMode: root.bioMode
            faceState: root._bioIndicatorEnabled ? root.faceState : ""
            lightBackdrop: root.lightBackdrop
            fontFamily: root.fontFamily
            showLegibleShadows: root.showLegibleShadows
        }

        // Hint and prompts share one slot and cross-fade, like the macOS lock screen
        Item {
            Layout.fillWidth: true
            Layout.topMargin: (root._bioIndicatorEnabled && root.faceState !== "") ? Kirigami.Units.smallSpacing : 0
            implicitHeight: root.promptVisible ? innerLayout.implicitHeight
                                               : ((root._bioIndicatorEnabled && root.faceState !== "") ? 0 : hintLabel.implicitHeight)
            Behavior on implicitHeight { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad } }

            PlasmaComponents3.Label {
                id: hintLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                text: root.hintText
                textFormat: Text.PlainText
                font.family: root.fontFamily !== "" ? root.fontFamily : Kirigami.Theme.defaultFont.family
                font.styleName: root.fontFamily === "SF Pro Text" ? "Medium" : ""
                font.weight: Font.Medium
                color: root.textColorDim
                opacity: (root.promptVisible || (root._bioIndicatorEnabled && root.faceState !== "")) ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
                layer.enabled: root.showLegibleShadows
                layer.effect: LegibleShadow { light: root.lightBackdrop }
            }

            ColumnLayout {
                id: innerLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                opacity: root.promptVisible ? 1 : 0
                enabled: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
            }
        }

        PlasmaComponents3.Label {
            id: notificationsLabel
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.pointSize: Kirigami.Theme.smallFont.pointSize + 1
            color: root.textColorDim
            opacity: text.length > 0 ? 1 : 0
            layer.enabled: true
            layer.effect: LegibleShadow { light: root.lightBackdrop }

            SequentialAnimation {
                id: bounceAnimation
                PropertyAnimation { target: notificationsLabel; property: "scale"; from: 1.0; to: 1.1; duration: Kirigami.Units.longDuration; easing.type: Easing.OutQuad }
                PropertyAnimation { target: notificationsLabel; property: "scale"; from: 1.1; to: 1.0; duration: Kirigami.Units.longDuration; easing.type: Easing.InQuad }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 0
            visible: root.authenticationTypeItem !== null && root.promptVisible
            children: [root.authenticationTypeItem]
        }
    }

    // Small round action buttons (Sleep, Switch User, ...) along the bottom edge
    RowLayout {
        id: actionItemsLayout
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.gridUnit * 2
        spacing: 0
        opacity: root.promptVisible ? 1 : 0
        enabled: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
    }
}
