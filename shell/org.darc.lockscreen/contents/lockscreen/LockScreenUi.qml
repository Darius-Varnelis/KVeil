/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>
    SPDX-FileCopyrightText: 2026 Kristen McWilliam <kristen@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.accessibility
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.workspace.keyboardlayout as Keyboards
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker
import org.kde.ki18n

import org.kde.plasma.private.sessions
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // If we're using software rendering, draw outlines instead of shadows
    // See https://bugs.kde.org/show_bug.cgi?id=398317
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    // Whether we expect a given authenticator to prompt for a credential at all.
    // This is a shortcut around the NoPasswordUnlock.qml screen when dealing with prompt-less authenticators.
    property bool expectingPrompt: false // this is set for real when an authenticator is selected
    // Whether we are expected to visualize the prompt message for the authenticator
    property bool showPrompt: false // this is set for real when an authenticator is selected

    // User settings written by Lock Screen Settings GUI to ~/.cache/darc-lockscreen/Settings.qml
    Loader {
        id: userSettingsLoader
        source: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/darc-lockscreen/Settings.qml"
    }
    function pref(key, fallback) {
        return (userSettingsLoader.item && userSettingsLoader.item[key] !== undefined)
            ? userSettingsLoader.item[key]
            : fallback;
    }

    // Biometric (Howdy Face ID or fprintd Fingerprint) state, driven by intercepted PAM messages.
    // bioMode: "face" or "fingerprint"
    // faceState: "", "scanning", "success", "timeout", "dark", "error", "mismatch", "retry"
    property string bioMode: "face"
    property string faceState: ""

    function setFaceState(state) {
        faceState = state;
        faceStateClearTimer.stop();
        if (state === "success") {
            faceStateClearTimer.interval = 1500;
            faceStateClearTimer.start();
        } else if (state === "timeout" || state === "dark" || state === "error" || state === "mismatch" || state === "retry") {
            faceStateClearTimer.interval = 3500;
            faceStateClearTimer.start();
        }
    }

    Timer {
        id: faceStateClearTimer
        onTriggered: lockScreenUi.faceState = ""
    }

    // reveal = false: show the message without opening the prompt. PAM sends its prompts
    // and Howdy its face detection notices as soon as the greeter starts, and those
    // shouldn't open it; only a failed unlock does.
    function handleMessage(msg, reveal = true) {
        if (!msg) {
            return;
        }
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
        if (reveal) {
            lockScreenRoot.uiVisible = true
        } else if (!lockScreenRoot.uiVisible) {
            notificationRemoveTimer.restart();
        }
    }

    property string pendingPassword

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                if (lockScreenUi.faceState === "scanning" || lockScreenUi.faceState === "retry") {
                    lockScreenUi.setFaceState(lockScreenUi.bioMode === "fingerprint" ? "mismatch" : "timeout");
                }
                return;
            }
            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            root.clearPassword();
            authenticator.startAuthenticating();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded() {
            // This is important. It stops the all pending authentication processes, preventing timeouts etc.
            authenticator.stopAuthenticating()

            if (!lockScreenUi.expectingPrompt) {
                Qt.quit()
            }
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                mainStack.replace(null, Qt.resolvedUrl("NoPasswordUnlock.qml"),
                    {
                        userListModel: users
                    },
                    StackView.Immediate,
                );
                mainStack.forceActiveFocus();
            }
        }

        function onNoninteractiveInfo(kind, noninteractiveAuth) {
            const msg = noninteractiveAuth ? noninteractiveAuth.infoMessage : "";
            if (msg.startsWith("Attempting face")) {
                lockScreenUi.bioMode = "face";
                lockScreenUi.setFaceState("scanning");
                return;
            }
            if (msg.startsWith("Identified face")) {
                lockScreenUi.bioMode = "face";
                lockScreenUi.setFaceState("success");
                return;
            }
            if (kind & ScreenLocker.Authenticator.Fingerprint) {
                lockScreenUi.bioMode = "fingerprint";
                const lower = msg.toLowerCase();
                if (lower.indexOf("again") !== -1 || lower.indexOf("retry") !== -1 || lower.indexOf("center") !== -1) {
                    lockScreenUi.setFaceState("retry");
                } else {
                    lockScreenUi.setFaceState("scanning");
                }
                return;
            }
            lockScreenUi.handleMessage(msg, false);
        }

        function onNoninteractiveError(kind, noninteractiveAuth) {
            const msg = noninteractiveAuth ? noninteractiveAuth.errorMessage : "";
            if (msg.indexOf("Face detection timeout") !== -1) {
                lockScreenUi.bioMode = "face";
                lockScreenUi.setFaceState("timeout");
                return;
            }
            if (msg.indexOf("image too dark") !== -1) {
                lockScreenUi.bioMode = "face";
                lockScreenUi.setFaceState("dark");
                return;
            }
            if (msg.indexOf("face model") !== -1 || msg.startsWith("Face")) {
                lockScreenUi.bioMode = "face";
                lockScreenUi.setFaceState("error");
                return;
            }
            if (kind & ScreenLocker.Authenticator.Fingerprint) {
                lockScreenUi.bioMode = "fingerprint";
                const lower = msg.toLowerCase();
                if (lower.indexOf("timeout") !== -1 || lower.indexOf("timed out") !== -1) {
                    lockScreenUi.setFaceState("timeout");
                } else if (lower.indexOf("match") !== -1 || lower.indexOf("not recognized") !== -1) {
                    lockScreenUi.setFaceState("mismatch");
                } else if (lower.indexOf("again") !== -1 || lower.indexOf("short") !== -1 || lower.indexOf("fast") !== -1 || lower.indexOf("center") !== -1) {
                    lockScreenUi.setFaceState("retry");
                } else {
                    lockScreenUi.setFaceState("error");
                }
                return;
            }
            lockScreenUi.handleMessage(msg, false);
        }

        function onInfoMessageChanged() {
            const msg = authenticator.infoMessage;
            if (msg) {
                if (msg.startsWith("Attempting face")) {
                    lockScreenUi.setFaceState("scanning");
                    return;
                }
                if (msg.startsWith("Identified face")) {
                    lockScreenUi.setFaceState("success");
                    return;
                }
            }
            lockScreenUi.handleMessage(msg, false);
        }

        function onErrorMessageChanged() {
            const msg = authenticator.errorMessage;
            if (msg) {
                if (msg.indexOf("Face detection timeout") !== -1) {
                    lockScreenUi.setFaceState("timeout");
                    return;
                }
                if (msg.indexOf("image too dark") !== -1) {
                    lockScreenUi.setFaceState("dark");
                    return;
                }
                if (msg.indexOf("face model") !== -1 || msg.startsWith("Face")) {
                    lockScreenUi.setFaceState("error");
                    return;
                }
            }
            lockScreenUi.handleMessage(msg, false);
        }

        function onPromptChanged() {
            lockScreenUi.handleMessage(authenticator.prompt, false);
        }
        function onPromptForSecretChanged() {
            mainBlock.showPassword = false;
            mainBlock.mainPasswordBox.forceActiveFocus();
            if (lockScreenUi.showPrompt) {
                lockScreenUi.handleMessage(authenticator.promptForSecret, false);
            }
        }
    }

    SessionManagement {
        id: sessionManagement
    }

    AccessibilityStatus {
        id: accessibilityStatus
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            root.clearPassword();
        }
    }

    RejectPasswordAnimation {
        id: rejectPasswordAnimation
        target: mainBlock
    }

    MouseArea {
        id: lockScreenRoot

        property bool uiVisible: !lockScreenUi.pref("requireInteractionToReveal", true)
        // kscreenlocker hands every screen's view the same `wallpaper` item (it lives in the first
        // window). Using it from another window (ShaderEffectSource, grabToImage) crashes the greeter
        // on teardown since Qt 6.12.0-3, so only the window that owns it gets the blur/brightness.
        readonly property Item ownWallpaper: wallpaper && Window.window && wallpaper.Window.window === Window.window ? wallpaper : null
        property bool seenPositionChange: false
        property bool blockUI: containsMouse && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || Keyboards.KWinVirtualKeyboard.visible)

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        // Moving the mouse only shows the cursor so the lock screen can be looked at;
        // clicking or typing opens the prompt.
        property bool cursorShown: false
        cursorShape: uiVisible || cursorShown ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: {
            cursorShown = seenPositionChange;
            seenPositionChange = true;
            cursorHideTimer.restart();
        }
        Timer {
            id: cursorHideTimer
            interval: 3000
            onTriggered: lockScreenRoot.cursorShown = false
        }
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
            }

            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            authenticator.startAuthenticating();
        }

        Timer { // heart beat keeping the backend active for as long as we are in visible state
            interval: 1000
            running: !authenticator.unlocked && parent.uiVisible
            repeat: true
            onTriggered: authenticator.startAuthenticating()
        }

        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        ScreenLocker.ActiveScreenMonitor {
            id: activeScreenMonitor
            lockscreenState: ScreenLocker.LockscreenState
            window: lockScreenRoot.Window.window
            onActiveChanged: {
                if(!active) {
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Keys.onEscapePressed: {
            // If the escape key is pressed, kscreenlocker will turn off the screen.
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                if (Keyboards.KWinVirtualKeyboard.visible) {
                    Keyboards.KWinVirtualKeyboard.active = false;
                }
                root.clearPassword();
            }
        }
        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: Math.max(3, lockScreenUi.pref("idleFadeSeconds", 10)) * 1000
            onTriggered: {
                if (!lockScreenRoot.blockUI && lockScreenUi.pref("requireInteractionToReveal", true)) {
                    mainBlock.mainPasswordBox.showPassword = false;
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: root.notification = ""
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.veryLongDuration * 2
        }

        Component.onCompleted: launchAnimation.start();

        // Wallpaper brightness behind the text, for picking light or dark text. Kept first so
        // everything else covers it. When the UI is shown WallpaperFader darkens the wallpaper
        // ((c * 0.8 + 0.1) * 0.7 in sRGB), so account for that.
        AppleBackdrop {
            id: backdrop
            source: lockScreenRoot.ownWallpaper
            function effective(luma: real): bool {
                let l = luma;
                if (lockScreenRoot.uiVisible) {
                    const s = Math.pow(l, 1 / 2.2);
                    l = Math.pow((s * 0.8 + 0.1) * 0.7, 2.2);
                }
                // WCAG equal-contrast crossover between white and near-black text is L = 0.179
                return l > 0.18;
            }
            function resolveLight(luma: real): bool {
                const mode = lockScreenUi.pref("backdropMode", "auto");
                if (mode === "darkText") return true;
                if (mode === "lightText") return false;
                return effective(luma);
            }
            readonly property bool clockLight: resolveLight(clockLuma)
            readonly property bool infoLight: resolveLight(infoLuma)
            readonly property bool statusLight: resolveLight(statusLuma)
            readonly property bool bottomLight: resolveLight(bottomLuma)
        }

        // WallpaperFader hides mainStack when idle; give it a stand-in so the avatar stays visible.
        // AppleSessionScreen fades the prompts itself.
        Item {
            id: idleFadeProxy
        }

        WallpaperFader {
            anchors.fill: parent
            state: lockScreenRoot.uiVisible ? "on" : "off"
            source: wallpaper
            mainStack: idleFadeProxy
            footer: footer
            clock: clock
            alwaysShowClock: lockScreenUi.pref("clockVisibility", "always") === "always"
                             && config.alwaysShowClock && !config.hideClockWhenIdle
        }

        DropShadow {
            id: clockShadow
            anchors.fill: clock
            source: clock
            visible: !lockScreenUi.softwareRendering && !backdrop.clockLight && lockScreenUi.pref("clockVisibility", "always") !== "never" && config.alwaysShowClock
            radius: 14
            verticalOffset: 1.5
            samples: 29
            spread: 0.22
            color: Qt.rgba(0, 0, 0, 0.48)
            opacity: lockScreenRoot.uiVisible ? 0.35 : 1
            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.veryLongDuration * 2
                    easing.type: Easing.InOutQuad
                }
            }
        }

        AppleClock {
            id: clock
            property Item shadow: clockShadow
            visible: y > 0 && lockScreenUi.pref("clockVisibility", "always") !== "never" && config.alwaysShowClock
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.07)
            lightBackdrop: backdrop.clockLight
            clock24Hour: lockScreenUi.pref("clock24Hour", "auto")
            showAmPm: lockScreenUi.pref("clockShowAmPm", false)
            clockScale: lockScreenUi.pref("clockScale", 1.0)
            fontFamily: lockScreenUi.pref("fontFamily", "SF Pro Display")
            Layout.alignment: Qt.AlignBaseline
        }

        // Greeting, weather and Now Playing under the clock
        AppleInfo {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: clock.visible ? clock.bottom : parent.top
            anchors.topMargin: clock.visible ? Kirigami.Units.largeSpacing : Math.round(parent.height * 0.09)
            visible: lockScreenUi.pref("showGreeting", true) || lockScreenUi.pref("showWeather", true) || lockScreenUi.pref("showMediaControls", true)
            userName: kscreenlocker_userName
            greetingName: lockScreenUi.pref("greetingName", "")
            showGreeting: lockScreenUi.pref("showGreeting", true)
            showWeather: lockScreenUi.pref("showWeather", true)
            showMediaControls: lockScreenUi.pref("showMediaControls", true) && config.showMediaControls
            frostedGlass: lockScreenUi.pref("frostedGlassEnabled", true)
            fontFamily: lockScreenUi.pref("fontFamily", "SF Pro Display")
            showLegibleShadows: lockScreenUi.pref("showLegibleShadows", true)
            lightBackdrop: backdrop.infoLight
            backdropItem: lockScreenRoot.ownWallpaper
        }

        // Keyboard layout, battery and Wi-Fi in the top-right corner
        AppleStatusBar {
            visible: lockScreenUi.pref("showStatusBar", true)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.largeSpacing * 2
            lightBackdrop: backdrop.statusLight
            showKeyboardLayout: lockScreenUi.pref("showKeyboardLayout", true)
            showBattery: lockScreenUi.pref("showBattery", true)
            showNetwork: lockScreenUi.pref("showNetwork", true)
            showLegibleShadows: lockScreenUi.pref("showLegibleShadows", true)
        }

        ListModel {
            id: users

            Component.onCompleted: {
                users.append({
                    name: kscreenlocker_userName,
                    realName: kscreenlocker_userName,
                    icon: kscreenlocker_userImage !== ""
                          ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
                          : "",
                })
            }
        }

        Connections {
            target: authenticator
            function onPamTimeoutChanged(): void {
                if (!authenticator.pamTimeout && lockScreenUi.pendingPassword.length > 0) {
                    authenticator.respond(lockScreenUi.pendingPassword);
                    lockScreenUi.pendingPassword = "";
                    mainBlock.enabled = true;
                }
            }
        }

        StackView {
            id: mainStack
            anchors {
                left: parent.left
                right: parent.right
            }
            height: lockScreenRoot.height
            focus: true //StackView is an implicit focus scope, so we need to give this focus so the item inside will have it

            // this isn't implicit, otherwise items still get processed for the scenegraph
            visible: opacity > 0

            initialItem: MainBlock {
                id: mainBlock
                lockScreenUiVisible: lockScreenRoot.uiVisible
                lightBackdrop: backdrop.bottomLight
                backdropItem: lockScreenRoot.ownWallpaper
                bioMode: lockScreenUi.bioMode
                faceState: lockScreenUi.faceState
                showAvatar: lockScreenUi.pref("showAvatar", true)
                faceStatusEnabled: lockScreenUi.pref("faceStatusEnabled", true)
                fingerprintStatusEnabled: lockScreenUi.pref("fingerprintStatusEnabled", true)
                irPreviewEnabled: lockScreenUi.pref("irPreviewEnabled", true)
                irPreviewTracking: lockScreenUi.pref("irPreviewTracking", true)
                irPreviewMirror: lockScreenUi.pref("irPreviewMirror", true)
                irPreviewShimmer: lockScreenUi.pref("irPreviewShimmer", true)
                irPreviewScale: lockScreenUi.pref("irPreviewScale", 1.0)
                irPreviewLingerMs: lockScreenUi.pref("irPreviewLingerMs", 1200)
                irPreviewDismissible: lockScreenUi.pref("irPreviewDismissible", true)
                frostedGlass: lockScreenUi.pref("frostedGlassEnabled", true)
                fontFamily: lockScreenUi.pref("fontFamily", "SF Pro Display") === "SF Pro Display"
                            ? "SF Pro Text"
                            : lockScreenUi.pref("fontFamily", "SF Pro Display")
                showLegibleShadows: lockScreenUi.pref("showLegibleShadows", true)

                // stock rule hides the list when it sits at y=0, which is always true in the bottom-aligned AppleSessionScreen
                showUserList: true

                StackView.onStatusChanged: {
                    // prepare for presenting again to the user
                    if (StackView.status === StackView.Activating) {
                        mainPasswordBox.clear();
                        mainPasswordBox.focus = true;
                        root.notification = "";
                    }
                }
                userListModel: users

                authenticationTypeItem: RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    visible: authenticationTypeRepeater.count > 1

                    Repeater {
                        id: authenticationTypeRepeater
                        model: ScreenLocker.AuthenticatorModel

                        delegate: PlasmaComponents3.Button {
                            required property int type
                            required property string iconName
                            required property bool passwordField
                            required property bool expectingPrompt
                            required property string tooltip
                            required property bool showPrompt
                            required property bool functional

                            onFunctionalChanged: {
                                if (functional) {
                                    return
                                }
                                root.notification = ""
                                mainBlock.passwordInputVisible = false
                                lockScreenUi.handleMessage(KI18n.i18ndc(
                                    "plasma_shell_org.kde.plasma.desktop",
                                    "@info:status",
                                    "This authentication method is not functioning correctly. Please try another method, and check your system configuration."), false)
                            }

                            // Be careful if you remove this to ensure defunct handling is present in all scenarios (e.g. onClicked)
                            enabled: functional
                            icon.name: iconName
                            icon.color: functional ? undefined : Kirigami.Theme.negativeTextColor
                            checked: authenticator.authenticator === type
                            onClicked: {
                                authenticator.authenticator = type
                                root.notification = ""
                                mainBlock.passwordInputVisible = passwordField
                                lockScreenUi.expectingPrompt = expectingPrompt
                                lockScreenUi.showPrompt = showPrompt
                            }

                            PlasmaComponents3.ToolTip.text: tooltip
                            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                            PlasmaComponents3.ToolTip.visible: hovered

                            Component.onCompleted: {
                                if (checked) {
                                    clicked()
                                }
                            }
                        }
                    }
                }

                notificationMessage: {
                    const parts = [];
                    if (capsLockState.locked) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on"));
                    }
                    if (accessibilityStatus.slowKeysEnabled) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Slow Keys are enabled"));
                    }
                    if (root.notification) {
                        parts.push(root.notification);
                    }
                    return parts.join(" • ");
                }

                onPasswordResult: password => {
                    if (authenticator.pamTimeout) {
                        lockScreenUi.pendingPassword = password
                        mainBlock.enabled = false
                    } else {
                        authenticator.respond(password)
                    }
                }

                actionItems: [
                    AppleActionButton {
                        lightBackdrop: mainBlock.lightBackdrop
                        showLegibleShadows: lockScreenUi.pref("showLegibleShadows", true)
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Slee&p")
                        icon.name: "system-suspend"
                        onClicked: sessionManagement.suspend()
                        visible: lockScreenUi.pref("showSleepButton", true) && sessionManagement.canSuspend
                    },
                    AppleActionButton {
                        lightBackdrop: mainBlock.lightBackdrop
                        showLegibleShadows: lockScreenUi.pref("showLegibleShadows", true)
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "&Hibernate")
                        icon.name: "system-suspend-hibernate"
                        onClicked: sessionManagement.hibernate()
                        visible: lockScreenUi.pref("showHibernateButton", true) && sessionManagement.canHibernate
                    },
                    // Shut Down (replaces Switch User). Needs a second click within 4s so a stray
                    // click can't power off; skips the logout dialog, which would open hidden behind the locker.
                    AppleActionButton {
                        id: shutdownButton
                        property bool armed: false
                        lightBackdrop: mainBlock.lightBackdrop
                        showLegibleShadows: lockScreenUi.pref("showLegibleShadows", true)
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                        text: armed ? i18n("Click to confirm") : i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button", "Shut Down")
                        icon.name: "system-shutdown"
                        onClicked: {
                            if (armed) {
                                sessionManagement.requestShutdown(0); // ConfirmationMode::Skip
                            } else {
                                armed = true;
                                shutdownDisarmTimer.restart();
                            }
                        }
                        visible: lockScreenUi.pref("showShutdownButton", true) && sessionManagement.canShutdown
                        Timer {
                            id: shutdownDisarmTimer
                            interval: 4000
                            onTriggered: shutdownButton.armed = false
                        }
                    }
                ]
            }
        }

        Loader {
            z: 2
            active: root.viewVisible
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }

        // Note: Containment masks stretch clickable area of their buttons to
        // the screen edges, essentially making them adhere to Fitts's law.
        // Due to virtual keyboard button having an icon, buttons may have
        // different heights, so fillHeight is required.
        //
        // Note for contributors: Keep this in sync with SDDM Main.qml footer.
        RowLayout {
            id: footer
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                id: virtualKeyboardButton
                visible: lockScreenUi.pref("showVirtualKeyboard", true)

                focusPolicy: Qt.TabFocus
                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to show/hide virtual keyboard", "Virtual Keyboard")
                icon.name: Keyboards.KWinVirtualKeyboard.visible ? "input-keyboard-virtual-on" : "input-keyboard-virtual-off"
                display: PlasmaComponents3.AbstractButton.IconOnly
                onClicked: {
                    if (Keyboards.KWinVirtualKeyboard.visible) {
                        Keyboards.KWinVirtualKeyboard.active = false;
                    } else {
                        // Otherwise the password field loses focus and on-screen keyboard
                        // keystrokes get eaten
                        mainBlock.mainPasswordBox.forceActiveFocus();
                        Keyboards.KWinVirtualKeyboard.forceActivate();
                    }
                }

                Layout.fillHeight: true
                containmentMask: Item {
                    parent: virtualKeyboardButton
                    anchors.fill: parent
                    anchors.leftMargin: -footer.anchors.margins
                    anchors.bottomMargin: -footer.anchors.margins
                }
            }

        }
    }
}
