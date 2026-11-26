// Frosted rounded Now Playing card (macOS lock-screen widget style), based on MediaControls.qml.
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris
import QtCore
import QtQuick.Effects

Item {
    id: card
    visible: instantiator.count > 0
    implicitHeight: Kirigami.Units.gridUnit * 4

    property bool lightBackdrop: false
    property bool frostedGlass: true
    property string fontFamily: ""
    // the wallpaper; a blurred copy of it fills the card (frosted glass)
    property Item backdropItem
    readonly property color fg: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.9) : "white"
    readonly property color fgDim: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.6) : Qt.rgba(1, 1, 1, 0.7)
    // album art is mirrored to ~/.cache/kveil/art/<md5(url)>.img by ~/.local/bin/lockscreen-mpris-art,
    // because the greeter blocks network requests
    readonly property string artCache: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/kveil/art/"
    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: fg

    // Soft drop shadow behind the card (helps the light frosted pill separate from bright skies)
    Rectangle {
        id: shadowSource
        anchors.fill: parent
        radius: Kirigami.Units.gridUnit
        color: "black"
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: shadowSource
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, card.lightBackdrop ? 0.14 : 0.28)
        shadowBlur: 1.0
        blurMax: 16
        shadowVerticalOffset: 3
        autoPaddingEnabled: true
        opacity: 0.65
    }

    // Frosted glass: blurred, tinted copy of the wallpaper area behind the card
    ShaderEffectSource {
        id: glassSource
        anchors.fill: parent
        visible: false
        sourceItem: card.backdropItem
        live: true
        function updateRect() {
            if (card.backdropItem && card.width > 0 && card.height > 0) {
                sourceRect = card.mapToItem(card.backdropItem, 0, 0, card.width, card.height);
            }
        }
    }
    Rectangle {
        id: glassMask
        anchors.fill: parent
        radius: Kirigami.Units.gridUnit
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        visible: card.frostedGlass && card.backdropItem !== null
        source: glassSource
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: card.lightBackdrop ? 0.35 : 0.15
        brightness: card.lightBackdrop ? 0.05 : -0.32
        maskEnabled: true
        maskSource: glassMask
    }
    // re-map after layout settles (mapToItem isn't a reactive binding)
    onXChanged: glassSource.updateRect()
    onYChanged: glassSource.updateRect()
    onWidthChanged: glassSource.updateRect()
    onHeightChanged: glassSource.updateRect()
    onVisibleChanged: if (visible) glassRefreshTimer.restart()
    onBackdropItemChanged: glassSource.updateRect()
    Component.onCompleted: glassRefreshTimer.restart()
    Timer { id: glassRefreshTimer; interval: 250; running: true; onTriggered: glassSource.updateRect() }

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.gridUnit
        color: card.lightBackdrop ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.22)
        border.width: 1
        border.color: card.lightBackdrop ? Qt.rgba(0, 0, 0, 0.10) : Qt.rgba(1, 1, 1, 0.08)
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
        Behavior on border.color { ColorAnimation { duration: Kirigami.Units.longDuration } }
    }

    Repeater {
        id: instantiator
        model: Mpris.MultiplexerModel { }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            enabled: model.canControl

            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: height

                Rectangle {
                    id: artPlaceholder
                    anchors.fill: parent
                    radius: Kirigami.Units.smallSpacing * 2
                    color: card.lightBackdrop ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.14)
                    border.width: 1
                    border.color: card.lightBackdrop ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.08)
                    visible: albumArt.status !== Image.Ready

                    Kirigami.Icon {
                        id: placeholderIcon
                        anchors.centerIn: parent
                        width: parent.width * 0.5
                        height: width
                        source: "emblem-music-symbolic"
                        fallback: ""
                        color: card.fgDim
                        isMask: true
                    }
                }
                Image {
                    id: albumArt
                    // bumped to retry while the art helper is still downloading a new cover
                    property int retry: 0
                    readonly property string url: model.artUrl ? String(model.artUrl) : ""
                    anchors.fill: parent
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    source: url.length > 0
                            ? (url.startsWith("http")
                                ? card.artCache + Qt.md5(url) + ".img?r=" + retry
                                : url)
                            : ""
                    onUrlChanged: retry = 0
                    onStatusChanged: if (status === Image.Error && url.startsWith("http") && retry < 15) retryTimer.restart()
                    Timer {
                        id: retryTimer
                        interval: 1000
                        onTriggered: albumArt.retry++
                    }
                    sourceSize.height: height * Screen.devicePixelRatio
                    visible: false
                }
                OpacityMask {
                    anchors.fill: parent
                    source: albumArt
                    visible: albumArt.status === Image.Ready
                    maskSource: Rectangle {
                        width: albumArt.width
                        height: albumArt.height
                        radius: Kirigami.Units.smallSpacing * 2
                        visible: false
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: card.fontFamily !== "" ? card.fontFamily : Kirigami.Theme.defaultFont.family
                    font.styleName: (card.fontFamily === "SF Pro Display" || card.fontFamily === "SF Pro Text") ? "Semibold" : ""
                    font.weight: Font.DemiBold
                    maximumLineCount: 1
                    color: card.fg
                    text: model.track.length > 0
                            ? model.track
                            : (model.playbackStatus > Mpris.PlaybackStatus.Stopped
                                ? i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "No title")
                                : i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "No media playing"))
                    textFormat: Text.PlainText
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: card.fontFamily !== "" ? card.fontFamily : Kirigami.Theme.defaultFont.family
                    maximumLineCount: 1
                    color: card.fgDim
                    text: model.artist || model.identity
                    textFormat: Text.PlainText
                }
            }

            component MediaButton: PlasmaComponents3.ToolButton {
                id: mbtn
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                Layout.preferredHeight: Layout.preferredWidth
                focusPolicy: Qt.TabFocus
                contentItem: Kirigami.Icon {
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                    source: mbtn.icon.name
                    color: mbtn.enabled ? card.fg : card.fgDim
                    isMask: true
                }
            }

            MediaButton {
                visible: model.canGoBack || model.canGoNext
                enabled: model.canGoPrevious
                icon.name: LayoutMirroring.enabled ? "media-skip-forward" : "media-skip-backward"
                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button Accessible only", "Previous track")
                onClicked: { fadeoutTimer.running = false; model.container.Previous() }
            }
            MediaButton {
                icon.name: model.playbackStatus === Mpris.PlaybackStatus.Playing ? "media-playback-pause" : "media-playback-start"
                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button Accessible only", "Play or Pause media")
                onClicked: { fadeoutTimer.running = false; model.container.PlayPause() }
            }
            MediaButton {
                visible: model.canGoBack || model.canGoNext
                enabled: model.canGoNext
                icon.name: LayoutMirroring.enabled ? "media-skip-backward" : "media-skip-forward"
                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@action:button Accessible only", "Next track")
                onClicked: { fadeoutTimer.running = false; model.container.Next() }
            }
        }
    }
}
