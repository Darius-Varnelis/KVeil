// Greeting + cached weather line and a Now Playing card, shown under the clock.
// Weather comes from ~/.cache/darc-lockscreen/Weather.qml (written by ~/.local/bin/lockscreen-weather,
// since the greeter blocks network access).
import QtQuick
import QtQuick.Layouts
import QtCore

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string userName
    property string greetingName: ""
    property bool showGreeting: true
    property bool showWeather: true
    property bool showMediaControls: true
    property bool frostedGlass: true
    property string fontFamily: "SF Pro Display"
    property bool showLegibleShadows: true
    // item to blur behind the Now Playing card (the wallpaper)
    property Item backdropItem
    property bool lightBackdrop: false
    property color textColor: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.94) : Qt.rgba(1, 1, 1, 0.96)
    Behavior on textColor { ColorAnimation { duration: Kirigami.Units.longDuration } }

    spacing: Kirigami.Units.largeSpacing

    PlasmaClockTimer { id: tick }

    Loader {
        id: weather
        active: root.showWeather
        source: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation) + "/darc-lockscreen/Weather.qml"
        asynchronous: true
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Kirigami.Units.smallSpacing
        visible: root.showGreeting || (root.showWeather && weather.status === Loader.Ready)
        layer.enabled: root.showLegibleShadows
        layer.effect: LegibleShadow { light: root.lightBackdrop }

        PlasmaComponents3.Label {
            visible: root.showGreeting
            text: {
                const hour = tick.hour;
                const part = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
                const rawName = root.greetingName !== "" ? root.greetingName : root.userName;
                const first = rawName ? rawName.split(" ")[0] : "";
                return first ? part + ", " + first : part;
            }
            textFormat: Text.PlainText
            font.family: root.fontFamily !== "" ? root.fontFamily : Kirigami.Theme.defaultFont.family
            font.styleName: root.fontFamily === "SF Pro Display" ? "Semibold" : ""
            font.weight: Font.DemiBold
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            color: root.textColor
        }

        PlasmaComponents3.Label {
            visible: root.showGreeting && root.showWeather && weather.status === Loader.Ready
            text: "·"
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            color: root.textColor
        }

        Kirigami.Icon {
            visible: root.showWeather && weather.status === Loader.Ready
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            source: weather.item ? weather.item.iconName + "-symbolic" : ""
            color: root.textColor
            isMask: true
        }

        PlasmaComponents3.Label {
            visible: root.showWeather && weather.status === Loader.Ready
            text: weather.item ? weather.item.temperature + "  " + weather.item.description : ""
            textFormat: Text.PlainText
            font.family: root.fontFamily !== "" ? root.fontFamily : Kirigami.Theme.defaultFont.family
            font.styleName: root.fontFamily === "SF Pro Display" ? "Semibold" : ""
            font.weight: Font.DemiBold
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            color: root.textColor
        }
    }

    Loader {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.gridUnit
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: item && item.visible ? item.implicitHeight : 0
        active: root.showMediaControls
        source: "NowPlayingCard.qml"
        onLoaded: {
            item.lightBackdrop = Qt.binding(() => root.lightBackdrop);
            item.backdropItem = Qt.binding(() => root.backdropItem);
            item.frostedGlass = Qt.binding(() => root.frostedGlass);
        }
    }

    component PlasmaClockTimer: Timer {
        property int hour: new Date().getHours()
        interval: 60000
        running: true
        repeat: true
        onTriggered: hour = new Date().getHours()
    }
}
