/*
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.breeze.components

AppleSessionScreen {
    id: sessionManager

    // macOS-style: show only the hint until the user wakes the lock screen or starts typing
    promptVisible: lockScreenUiVisible || passwordBox.text.length > 0
    hintText: {
        if (_faceFailed) {
            return i18nc("@info:usagetip", "Enter password");
        }
        if (bioMode === "face" && faceStatusEnabled) {
            return i18nc("@info:usagetip", "Look at camera or enter password");
        }
        if ((bioMode === "fingerprint" || (authenticator.authenticatorTypes & ScreenLocker.Authenticator.Fingerprint)) && fingerprintStatusEnabled) {
            return i18nc("@info:usagetip", "Scan fingerprint or enter password");
        }
        return i18nc("@info:usagetip", "Enter password");
    }

    property alias passwordInputVisible: passwordLayout.visible
    readonly property alias mainPasswordBox: passwordBox
    property bool lockScreenUiVisible: false
    property alias showPassword: passwordBox.showPassword

    //the y position that should be ensured visible when the on screen keyboard is visible
    property int visibleBoundary: mapFromItem(loginButton, 0, 0).y
    onHeightChanged: visibleBoundary = mapFromItem(loginButton, 0, 0).y + loginButton.height + Kirigami.Units.smallSpacing
    /*
     * Login has been requested with the following username and password
     * If username field is visible, it will be taken from that, otherwise from the "name" property of the currentIndex
     */
    signal passwordResult(string password)

    onUserSelected: {
        const nextControl = (passwordBox.visible ? passwordBox : loginButton);
        // Don't startLogin() here, because the signal is connected to the
        // Escape key as well, for which it wouldn't make sense to trigger
        // login. Using TabFocusReason, so that the loginButton gets the
        // visual highlight.
        nextControl.forceActiveFocus(Qt.TabFocusReason);
    }

    function startLogin() {
        const password = passwordBox.text

        // This is partly because it looks nicer, but more importantly it
        // works round a Qt bug that can trigger if the app is closed with a
        // TextField focused.
        //
        // See https://bugreports.qt.io/browse/QTBUG-55460
        loginButton.forceActiveFocus();
        passwordResult(password);
    }

    RowLayout {
        id: passwordLayout
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing

        // balances the unlock button on the right so the pill stays centred
        Item {
            Layout.preferredWidth: loginButton.Layout.preferredWidth
        }

        PlasmaExtras.PasswordField {
            id: passwordBox
            Layout.preferredWidth: Kirigami.Units.gridUnit * 11
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.8
            leftPadding: Kirigami.Units.gridUnit * 0.8
            verticalAlignment: TextInput.AlignVCenter
            text: PasswordSync.password

            // rounded, frosted pill
            color: sessionManager.textColor
            placeholderTextColor: sessionManager.textColorDim
            Kirigami.Theme.inherit: false
            Kirigami.Theme.textColor: sessionManager.textColor
            background: Rectangle {
                readonly property real baseAlpha: sessionManager.lightBackdrop ? 0.45 : 0.18
                radius: height / 2
                color: Qt.rgba(1, 1, 1, passwordBox.activeFocus ? baseAlpha + 0.06 : baseAlpha)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, sessionManager.lightBackdrop ? 0.5 : 0.22)
            }

            placeholderText: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:placeholder in text field", "Enter Password")
            focus: true

            cursorVisible: visible

            onAccepted: {
                if (sessionManager.lockScreenUiVisible) {
                    sessionManager.startLogin();
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left && !text) {
                    sessionManager.userList.decrementCurrentIndex();
                    event.accepted = true
                }
                if (event.key === Qt.Key_Right && !text) {
                    sessionManager.userList.incrementCurrentIndex();
                    event.accepted = true
                }
            }

            Connections {
                target: root
                function onClearPassword() {
                    passwordBox.forceActiveFocus()
                    passwordBox.text = "";
                    passwordBox.text = Qt.binding(() => PasswordSync.password);
                }
                function onNotificationRepeated() {
                    sessionManager.playHighlightAnimation();
                }
            }
        }
        Binding {
            target: PasswordSync
            property: "password"
            value: passwordBox.text
        }

        // round arrow button, only shown once something is typed
        PlasmaComponents3.Button {
            id: loginButton
            Accessible.name: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button accessible only", "Unlock")
            Layout.preferredHeight: passwordBox.Layout.preferredHeight
            Layout.preferredWidth: Layout.preferredHeight
            opacity: passwordBox.text.length > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

            icon.name: LayoutMirroring.enabled ? "go-previous-symbolic" : "go-next-symbolic"
            icon.color: sessionManager.textColor
            display: PlasmaComponents3.AbstractButton.IconOnly
            background: Rectangle {
                readonly property real baseAlpha: sessionManager.lightBackdrop ? 0.45 : 0.22
                radius: width / 2
                color: Qt.rgba(1, 1, 1, loginButton.pressed ? baseAlpha + 0.13 : baseAlpha)
                border.width: loginButton.visualFocus ? 2 : 0
                border.color: Kirigami.Theme.highlightColor
            }

            onClicked: sessionManager.startLogin()
            Keys.onEnterPressed: clicked()
            Keys.onReturnPressed: clicked()
        }
    }

    component FailableLabel : PlasmaComponents3.Label {
        id: _failableLabel
        required property int kind
        required property string label

        visible: (authenticator.authenticatorTypes & kind) && text !== label
        text: label
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true

        RejectPasswordAnimation {
            id: _rejectAnimation
            target: _failableLabel
            onFinished: _timer.restart()
        }

        Connections {
            target: authenticator
            function onNoninteractiveError(kind, authenticator) {
                if (kind & _failableLabel.kind) {
                    _failableLabel.text = Qt.binding(() => authenticator.errorMessage)
                    _rejectAnimation.start()
                }
            }
        }
        Timer {
            id: _timer
            interval: Kirigami.Units.humanMoment
            onTriggered: {
                _failableLabel.text = Qt.binding(() => _failableLabel.label)
            }
        }
    }

    FailableLabel {
        visible: false // Replaced by FaceIdStatus (Howdy runs in the fingerprint PAM slot)
        kind: ScreenLocker.Authenticator.Fingerprint
        label: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your fingerprint on the reader)")
    }
    FailableLabel {
        kind: ScreenLocker.Authenticator.Smartcard
        label: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your smartcard)")
    }
}
