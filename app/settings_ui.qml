import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: win

    title: "KVeil"
    width: Kirigami.Units.gridUnit * 38
    height: Kirigami.Units.gridUnit * 40
    minimumWidth: Kirigami.Units.gridUnit * 30
    minimumHeight: Kirigami.Units.gridUnit * 28

    readonly property var cfg: backend.settings
    readonly property var st: backend.status
    property int currentTab: 0
    property int unlockSubTab: 0 // 0 = Status & Session, 1 = Face & IR

    function setOpt(key, val) {
        backend.setOption(key, val);
    }

    Connections {
        target: backend
        function onToastRequested(msg) {
            win.showPassiveNotification(msg, 3000);
        }
    }

    header: QQC2.ToolBar {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.ButtonGroup {
                id: tabGroup
            }

            Repeater {
                model: [
                    "Clock && Info",
                    "Status && Unlock",
                    "Appearance && Setup"
                ]

                QQC2.Button {
                    required property int index
                    required property string modelData
                    text: modelData
                    checkable: true
                    checked: win.currentTab === index
                    QQC2.ButtonGroup.group: tabGroup
                    onToggled: if (checked) win.currentTab = index
                }
            }

            Item { Layout.fillWidth: true }

            QQC2.Button {
                icon.name: "view-preview"
                text: "Test Lock Screen"
                onClicked: backend.testLockScreen()
            }
        }
    }

    footer: QQC2.ToolBar {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "document-save"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                opacity: 0.7
            }
            QQC2.Label {
                text: "Changes save automatically and apply on next lock"
                opacity: 0.75
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            QQC2.Button {
                icon.name: "edit-undo"
                text: "Reset Defaults"
                flat: true
                onClicked: resetDialog.open()
            }
        }
    }

    Kirigami.PromptDialog {
        id: resetDialog
        title: "Reset KVeil Settings?"
        subtitle: "This restores all lock screen, clock, and biometric options to their defaults."
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: backend.resetDefaults()
    }

    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    pageStack.initialPage: Kirigami.ScrollablePage {
        id: mainPage
        padding: Kirigami.Units.largeSpacing

        // Tab 0: Clock, Greeting, Weather & Media
        ColumnLayout {
            width: mainPage.width - mainPage.leftPadding - mainPage.rightPadding
            visible: win.currentTab === 0
            spacing: Kirigami.Units.largeSpacing

            Kirigami.FormLayout {
                Layout.fillWidth: true

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Clock"
                }

                QQC2.ComboBox {
                    Kirigami.FormData.label: "Show clock:"
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { label: "Always", value: "always" },
                        { label: "Only when unlock prompt is visible", value: "prompt" },
                        { label: "Never", value: "never" }
                    ]
                    currentIndex: Math.max(0, model.findIndex(item => item.value === (win.cfg.clockVisibility || "always")))
                    onActivated: win.setOpt("clockVisibility", currentValue)
                }

                QQC2.ComboBox {
                    Kirigami.FormData.label: "Time format:"
                    enabled: win.cfg.clockVisibility !== "never"
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { label: "System locale (Auto)", value: "auto" },
                        { label: "24-hour (18:30)", value: "24h" },
                        { label: "12-hour (6:30)", value: "12h" }
                    ]
                    currentIndex: Math.max(0, model.findIndex(item => item.value === (win.cfg.clock24Hour || "auto")))
                    onActivated: win.setOpt("clock24Hour", currentValue)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "AM / PM suffix:"
                    text: "Show AM/PM in 12-hour format"
                    enabled: win.cfg.clockVisibility !== "never" && win.cfg.clock24Hour !== "24h"
                    checked: win.cfg.clockShowAmPm === true
                    onToggled: win.setOpt("clockShowAmPm", checked)
                }

                RowLayout {
                    Kirigami.FormData.label: "Clock size:"
                    enabled: win.cfg.clockVisibility !== "never"
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Slider {
                        id: clockScaleSlider
                        from: 0.70
                        to: 1.35
                        stepSize: 0.05
                        value: win.cfg.clockScale !== undefined ? win.cfg.clockScale : 1.0
                        onMoved: win.setOpt("clockScale", Math.round(value * 20) / 20)
                    }
                    QQC2.Label {
                        text: Math.round(clockScaleSlider.value * 100) + "%"
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                    }
                }

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Greeting & Weather"
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Greeting line:"
                    text: "Show time-of-day greeting under clock"
                    checked: win.cfg.showGreeting === true
                    onToggled: win.setOpt("showGreeting", checked)
                }

                QQC2.TextField {
                    Kirigami.FormData.label: "Custom name:"
                    placeholderText: "Leave empty to use system name"
                    enabled: win.cfg.showGreeting === true
                    text: win.cfg.greetingName || ""
                    onEditingFinished: win.setOpt("greetingName", text.trim())
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Weather:"
                    text: "Show local weather beside greeting"
                    checked: win.cfg.showWeather === true
                    onToggled: win.setOpt("showWeather", checked)
                }

                QQC2.ComboBox {
                    Kirigami.FormData.label: "Temperature unit:"
                    enabled: win.cfg.showWeather === true
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { label: "Celsius (°C)", value: "C" },
                        { label: "Fahrenheit (°F)", value: "F" }
                    ]
                    currentIndex: Math.max(0, model.findIndex(item => item.value === (win.cfg.weatherUnit || "C")))
                    onActivated: {
                        win.setOpt("weatherUnit", currentValue);
                        backend.refreshWeather();
                    }
                }

                RowLayout {
                    Kirigami.FormData.label: "Location override:"
                    enabled: win.cfg.showWeather === true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.TextField {
                        id: weatherLocField
                        placeholderText: "Auto (IP-based)"
                        text: win.cfg.weatherLocation || ""
                        onEditingFinished: win.setOpt("weatherLocation", text.trim())
                    }
                    QQC2.Button {
                        icon.name: "view-refresh"
                        text: "Refresh"
                        onClicked: {
                            win.setOpt("weatherLocation", weatherLocField.text.trim());
                            backend.refreshWeather();
                        }
                    }
                }

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Media"
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Now Playing card:"
                    text: "Show frosted MPRIS media widget"
                    checked: win.cfg.showMediaControls === true
                    onToggled: win.setOpt("showMediaControls", checked)
                }
            }
        }

        // Tab 1: Status & Unlock (with Status & Session | Face & IR subcategories)
        ColumnLayout {
            width: mainPage.width - mainPage.leftPadding - mainPage.rightPadding
            visible: win.currentTab === 1
            spacing: Kirigami.Units.largeSpacing

            // Subcategory selector
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing

                QQC2.ButtonGroup {
                    id: unlockSubGroup
                }

                Repeater {
                    model: [
                        { label: "Status && Session", iconName: "system-lock-screen" },
                        { label: "Face && IR", iconName: "camera-web-symbolic" },
                        { label: "Fingerprint", iconName: "fingerprint-symbolic" }
                    ]

                    QQC2.Button {
                        required property int index
                        required property var modelData
                        text: modelData.label
                        icon.name: modelData.iconName
                        checkable: true
                        checked: win.unlockSubTab === index
                        QQC2.ButtonGroup.group: unlockSubGroup
                        onToggled: if (checked) win.unlockSubTab = index
                    }
                }
            }

            // Subcategory 0: Status Bar, Prompt & Session Actions
            Kirigami.FormLayout {
                Layout.fillWidth: true
                visible: win.unlockSubTab === 0

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Top-Right Status Bar"
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Status bar:"
                    text: "Show status indicators in top-right corner"
                    checked: win.cfg.showStatusBar === true
                    onToggled: win.setOpt("showStatusBar", checked)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Keyboard layout:"
                    text: "Show active keyboard layout"
                    enabled: win.cfg.showStatusBar === true
                    checked: win.cfg.showKeyboardLayout === true
                    onToggled: win.setOpt("showKeyboardLayout", checked)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Battery:"
                    text: "Show battery percentage and charging icon"
                    enabled: win.cfg.showStatusBar === true
                    checked: win.cfg.showBattery === true
                    onToggled: win.setOpt("showBattery", checked)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Network:"
                    text: "Show Wi-Fi / wired connection icon"
                    enabled: win.cfg.showStatusBar === true
                    checked: win.cfg.showNetwork === true
                    onToggled: win.setOpt("showNetwork", checked)
                }

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Unlock Prompt & Session"
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "User avatar:"
                    text: "Show round profile picture and username"
                    checked: win.cfg.showAvatar === true
                    onToggled: win.setOpt("showAvatar", checked)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Idle lock mode:"
                    text: "Hide password box until click or key press"
                    checked: win.cfg.requireInteractionToReveal === true
                    onToggled: win.setOpt("requireInteractionToReveal", checked)
                }

                RowLayout {
                    Kirigami.FormData.label: "Prompt auto-hide:"
                    enabled: win.cfg.requireInteractionToReveal === true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Slider {
                        id: fadeSlider
                        from: 5
                        to: 30
                        stepSize: 1
                        value: win.cfg.idleFadeSeconds !== undefined ? win.cfg.idleFadeSeconds : 10
                        onMoved: win.setOpt("idleFadeSeconds", Math.round(value))
                    }
                    QQC2.Label {
                        text: Math.round(fadeSlider.value) + " s"
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                    }
                }

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Power & Input Buttons"
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Sleep button:"
                    text: "Show Suspend action"
                    checked: win.cfg.showSleepButton === true
                    onToggled: win.setOpt("showSleepButton", checked)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Hibernate button:"
                    text: "Show Hibernate action (when supported)"
                    checked: win.cfg.showHibernateButton === true
                    onToggled: win.setOpt("showHibernateButton", checked)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Shut Down button:"
                    text: "Show Shut Down action (requires 2nd click)"
                    checked: win.cfg.showShutdownButton === true
                    onToggled: win.setOpt("showShutdownButton", checked)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Virtual keyboard:"
                    text: "Show virtual keyboard toggle in bottom-left"
                    checked: win.cfg.showVirtualKeyboard === true
                    onToggled: win.setOpt("showVirtualKeyboard", checked)
                }
            }

            // Subcategory 1: Face Unlock & IR Camera Preview (requires Howdy)
            ColumnLayout {
                Layout.fillWidth: true
                visible: win.unlockSubTab === 1
                spacing: Kirigami.Units.largeSpacing

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: !win.st.howdyPresent
                    type: Kirigami.MessageType.Information
                    text: "Howdy is not installed on this system. Install Howdy and configure it in /etc/pam.d/kde-fingerprint before enabling Face ID status or the IR camera preview."
                    actions: [
                        Kirigami.Action {
                            icon.name: "view-refresh"
                            text: "Re-check"
                            onTriggered: backend.refreshStatus()
                        }
                    ]
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: win.st.howdyPresent && !win.st.howdyPamConfigured
                    type: Kirigami.MessageType.Warning
                    text: "Howdy is installed, but /etc/pam.d/kde-fingerprint does not reference howdy yet. Face unlock on the KDE lock screen requires Howdy in kde-fingerprint."
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: win.st.howdyPresent && win.st.howdyBackend !== "rust" && win.cfg.irPreviewEnabled && !win.st.howdyHookInstalled
                    type: Kirigami.MessageType.Warning
                    text: win.st.howdyHookOutdated === true
                        ? "An updated Howdy preview & face-tracking hook is staged. Copy the staged file with sudo to apply the tracking fixes."
                        : ("Howdy preview emitter is not installed in " + (win.st.howdyComparePath || "/usr/lib/security/howdy/compare.py") + " yet. Copy the staged file with sudo so live IR frames appear.")
                    actions: [
                        Kirigami.Action {
                            icon.name: "edit-copy"
                            text: "Copy sudo command"
                            onTriggered: backend.copyHookCommand()
                        }
                    ]
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: win.st.howdyBackend === "rust" && win.st.howdydServiceInstalled && !win.st.howdydRunning
                    type: Kirigami.MessageType.Information
                    text: "Howdy-rs is active, but the preloaded howdyd service is not running (cold-start mode). Start howdyd for instant lock screen unlock."
                    actions: [
                        Kirigami.Action {
                            icon.name: "system-run"
                            text: "Start howdyd"
                            onTriggered: backend.startHowdyd()
                        }
                    ]
                }

                Kirigami.FormLayout {
                    Layout.fillWidth: true

                    Kirigami.Separator {
                        Kirigami.FormData.isSection: true
                        Kirigami.FormData.label: "Face Recognition Indicator"
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Face ID status badge:"
                        text: "Show \"Looking for you…\" and match feedback"
                        enabled: win.st.howdyPresent === true
                        checked: win.st.howdyPresent === true && win.cfg.faceStatusEnabled === true
                        onToggled: win.setOpt("faceStatusEnabled", checked)
                    }

                    Kirigami.Separator {
                        Kirigami.FormData.isSection: true
                        Kirigami.FormData.label: "IR Camera Preview Pop-up"
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Live IR viewfinder:"
                        text: "Show pop-up preview while Howdy scans"
                        enabled: win.st.howdyPresent === true
                        checked: win.st.howdyPresent === true && win.cfg.irPreviewEnabled === true
                        onToggled: win.setOpt("irPreviewEnabled", checked)
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Face tracking square:"
                        text: "Draw green brackets around detected face"
                        enabled: win.st.howdyPresent === true && win.cfg.irPreviewEnabled === true
                        checked: win.cfg.irPreviewTracking === true
                        onToggled: win.setOpt("irPreviewTracking", checked)
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Mirror preview:"
                        text: "Flip horizontally like a selfie camera"
                        enabled: win.st.howdyPresent === true && win.cfg.irPreviewEnabled === true
                        checked: win.cfg.irPreviewMirror === true
                        onToggled: win.setOpt("irPreviewMirror", checked)
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Scan shimmer:"
                        text: "Subtle sweep animation while scanning"
                        enabled: win.st.howdyPresent === true && win.cfg.irPreviewEnabled === true
                        checked: win.cfg.irPreviewShimmer === true
                        onToggled: win.setOpt("irPreviewShimmer", checked)
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Click to dismiss:"
                        text: "Hide pop-up for current scan when clicked"
                        enabled: win.st.howdyPresent === true && win.cfg.irPreviewEnabled === true
                        checked: win.cfg.irPreviewDismissible === true
                        onToggled: win.setOpt("irPreviewDismissible", checked)
                    }

                    RowLayout {
                        Kirigami.FormData.label: "Pop-up size:"
                        enabled: win.st.howdyPresent === true && win.cfg.irPreviewEnabled === true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Slider {
                            id: irScaleSlider
                            from: 0.75
                            to: 1.40
                            stepSize: 0.05
                            value: win.cfg.irPreviewScale !== undefined ? win.cfg.irPreviewScale : 1.0
                            onMoved: win.setOpt("irPreviewScale", Math.round(value * 20) / 20)
                        }
                        QQC2.Label {
                            text: Math.round(irScaleSlider.value * 100) + "%"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                        }
                    }

                    RowLayout {
                        Kirigami.FormData.label: "Result linger delay:"
                        enabled: win.st.howdyPresent === true && win.cfg.irPreviewEnabled === true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Slider {
                            id: irLingerSlider
                            from: 500
                            to: 2500
                            stepSize: 100
                            value: win.cfg.irPreviewLingerMs !== undefined ? win.cfg.irPreviewLingerMs : 1200
                            onMoved: win.setOpt("irPreviewLingerMs", Math.round(value / 100) * 100)
                        }
                        QQC2.Label {
                            text: (irLingerSlider.value / 1000).toFixed(1) + " s"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                        }
                    }
                }
            }

            // Subcategory 2: Fingerprint Unlock (fprintd)
            ColumnLayout {
                Layout.fillWidth: true
                visible: win.unlockSubTab === 2
                spacing: Kirigami.Units.largeSpacing

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: !win.st.fprintdPresent
                    type: Kirigami.MessageType.Information
                    text: "fprintd is not installed on this system. Install fprintd and enroll a fingerprint (fprintd-enroll) to use Touch ID-style fingerprint unlock."
                    actions: [
                        Kirigami.Action {
                            icon.name: "view-refresh"
                            text: "Re-check"
                            onTriggered: backend.refreshStatus()
                        }
                    ]
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: win.st.fprintdPresent && !win.st.fprintdPamConfigured
                    type: Kirigami.MessageType.Warning
                    text: win.st.howdyPamConfigured
                        ? "/etc/pam.d/kde-fingerprint is currently configured for Howdy face unlock, which shares KDE's fingerprint PAM slot."
                        : "pam_fprintd.so is not active in /etc/pam.d/kde-fingerprint."
                }

                Kirigami.FormLayout {
                    Layout.fillWidth: true

                    Kirigami.Separator {
                        Kirigami.FormData.isSection: true
                        Kirigami.FormData.label: "Fingerprint Unlock (fprintd)"
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Fingerprint indicator:"
                        text: "Show Touch ID-style scan and match feedback"
                        enabled: win.st.fprintdPresent === true
                        checked: win.st.fprintdPresent === true && win.cfg.fingerprintStatusEnabled === true
                        onToggled: win.setOpt("fingerprintStatusEnabled", checked)
                    }
                }
            }
        }

        // Tab 2: Appearance & Environment Diagnostics
        ColumnLayout {
            width: mainPage.width - mainPage.leftPadding - mainPage.rightPadding
            visible: win.currentTab === 2
            spacing: Kirigami.Units.largeSpacing

            Kirigami.FormLayout {
                Layout.fillWidth: true

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Visual Style"
                }

                QQC2.ComboBox {
                    Kirigami.FormData.label: "Text contrast:"
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { label: "Auto (sample wallpaper brightness)", value: "auto" },
                        { label: "Always light text (for dark wallpapers)", value: "lightText" },
                        { label: "Always dark text (for bright wallpapers)", value: "darkText" }
                    ]
                    currentIndex: Math.max(0, model.findIndex(item => item.value === (win.cfg.backdropMode || "auto")))
                    onActivated: win.setOpt("backdropMode", currentValue)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Frosted glass:"
                    text: "Blur wallpaper behind Now Playing and IR preview"
                    checked: win.cfg.frostedGlassEnabled === true
                    onToggled: win.setOpt("frostedGlassEnabled", checked)
                }

                QQC2.Switch {
                    Kirigami.FormData.label: "Text shadows:"
                    text: "Soft contrast halo behind labels and icons"
                    checked: win.cfg.showLegibleShadows === true
                    onToggled: win.setOpt("showLegibleShadows", checked)
                }

                QQC2.ComboBox {
                    Kirigami.FormData.label: "Font family:"
                    textRole: "label"
                    valueRole: "value"
                    model: [
                        { label: win.st.hasSfPro ? "SF Pro Display (Apple)" : "SF Pro Display (if installed)", value: "SF Pro Display" },
                        { label: "Inter", value: "Inter" },
                        { label: "Noto Sans", value: "Noto Sans" },
                        { label: "System Default", value: "" }
                    ]
                    currentIndex: Math.max(0, model.findIndex(item => item.value === (win.cfg.fontFamily !== undefined ? win.cfg.fontFamily : "SF Pro Display")))
                    onActivated: win.setOpt("fontFamily", currentValue)
                }

                QQC2.Button {
                    Kirigami.FormData.label: "Wallpaper:"
                    icon.name: "preferences-desktop-wallpaper"
                    text: "Customize Lock Screen Wallpaper\u2026"
                    onClicked: backend.openWallpaperSettings()
                }

                Kirigami.Separator {
                    Kirigami.FormData.isSection: true
                    Kirigami.FormData.label: "Environment Status"
                }

                QQC2.Label {
                    Kirigami.FormData.label: "Lock screen shell:"
                    text: win.st.shellInstalled
                        ? (win.st.shellActive ? "Installed and active (org.darc.lockscreen)" : "Installed (set PLASMA_DEFAULT_SHELL=org.darc.lockscreen)")
                        : "Not found"
                }

                QQC2.Label {
                    Kirigami.FormData.label: "Howdy face unlock:"
                    text: !win.st.howdyPresent
                        ? "Howdy not installed"
                        : (win.st.howdyBackend === "rust"
                            ? "Howdy-rs (native Rust + built-in IR preview)"
                            : (win.st.howdyHookInstalled
                                ? "Howdy detected + IR preview hook installed"
                                : (win.st.howdyHookOutdated === true
                                    ? "Howdy detected — updated IR preview hook staged (sudo copy needed)"
                                    : (win.st.howdyPamConfigured ? "Howdy detected — IR preview hook not installed yet" : "Howdy installed — not configured in kde-fingerprint"))))
                }

                QQC2.Label {
                    Kirigami.FormData.label: "Howdy-rs daemon:"
                    visible: win.st.howdyRsPresent === true || win.st.howdyBackend === "rust"
                    text: win.st.howdydRunning
                        ? "Active (howdyd models preloaded)"
                        : (win.st.howdydServiceInstalled ? "Inactive (service installed, not running)" : "Not installed (cold-start binary)")
                }

                QQC2.Label {
                    Kirigami.FormData.label: "Fingerprint (fprintd):"
                    text: !win.st.fprintdPresent
                        ? "fprintd not installed"
                        : (win.st.fprintdPamConfigured ? "fprintd detected + active in kde-fingerprint" : "fprintd installed (kde-fingerprint uses Howdy or another module)")
                }

                QQC2.Label {
                    Kirigami.FormData.label: "Weather helper:"
                    text: win.st.weatherBinOk
                        ? (win.st.weatherCached ? "Available (cached)" : "Available (not cached yet)")
                        : "Helper missing (~/.local/bin/lockscreen-weather)"
                }

                QQC2.Label {
                    Kirigami.FormData.label: "Settings file:"
                    text: win.st.configPath || ""
                    opacity: 0.75
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                RowLayout {
                    Kirigami.FormData.label: "Actions:"
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Button {
                        icon.name: "view-refresh"
                        text: "Re-check Status"
                        onClicked: backend.refreshStatus()
                    }
                    QQC2.Button {
                        icon.name: "edit-copy"
                        text: "Copy Howdy Hook Command"
                        visible: win.st.howdyPresent && win.st.howdyBackend !== "rust" && !win.st.howdyHookInstalled
                        onClicked: backend.copyHookCommand()
                    }
                    QQC2.Button {
                        icon.name: "system-run"
                        text: win.st.howdydRunning ? "Restart howdyd" : "Start howdyd"
                        visible: win.st.howdydServiceInstalled === true
                        onClicked: backend.startHowdyd()
                    }
                }
            }
        }
    }
}
