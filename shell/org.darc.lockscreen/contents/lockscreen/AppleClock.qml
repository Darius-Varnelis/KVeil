// macOS Sonoma-style lock screen clock: copy of org.kde.breeze.components Clock.qml
// with SF Pro Display Bold/Semibold and translucent "vibrancy" white text.
// Translucency is in the colour alpha because WallpaperFader forces clock.opacity to 1.
import QtQuick
import QtQuick.Layouts

import org.kde.plasma.clock as PlasmaClock
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    // true when the wallpaper behind the clock is bright -> dark translucent text
    property bool lightBackdrop: false
    property string clock24Hour: "auto" // "auto", "24h", "12h"
    property bool showAmPm: false
    property real clockScale: 1.0
    property string fontFamily: "SF Pro Display"
    readonly property color vibrancy: lightBackdrop ? Qt.rgba(0.05, 0.05, 0.08, 0.84) : Qt.rgba(1, 1, 1, 0.88)

    spacing: 0

    PlasmaComponents3.Label {
        text: Qt.formatDate(timeSource.dateTime, "dddd, MMMM d")
        textFormat: Text.PlainText
        color: root.vibrancy
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
        style: root.softwareRendering ? Text.Outline : Text.Normal
        styleColor: root.softwareRendering ? Kirigami.Theme.backgroundColor : "transparent"
        font.family: root.fontFamily !== "" ? root.fontFamily : Kirigami.Theme.defaultFont.family
        font.styleName: root.fontFamily === "SF Pro Display" ? "Semibold" : ""
        font.weight: Font.DemiBold
        font.pointSize: Math.round(Kirigami.Theme.defaultFont.pointSize * 1.8 * root.clockScale)
        renderType: Text.NativeRendering
        Layout.alignment: Qt.AlignHCenter
    }
    PlasmaComponents3.Label {
        text: {
            const dt = timeSource.dateTime;
            if (root.clock24Hour === "24h") {
                return Qt.formatTime(dt, "HH:mm");
            }
            if (root.clock24Hour === "12h") {
                return root.showAmPm ? Qt.formatTime(dt, "h:mm ap") : Qt.formatTime(dt, "h:mm");
            }
            const formatted = Qt.formatTime(dt, Qt.locale(), Locale.ShortFormat);
            return root.showAmPm ? formatted : formatted.replace(/\s?[AaPp]\.?[Mm]\.?$/, "");
        }
        textFormat: Text.PlainText
        color: root.vibrancy
        Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
        style: root.softwareRendering ? Text.Outline : Text.Normal
        styleColor: root.softwareRendering ? Kirigami.Theme.backgroundColor : "transparent"
        font.family: root.fontFamily !== "" ? root.fontFamily : Kirigami.Theme.defaultFont.family
        font.styleName: root.fontFamily === "SF Pro Display" ? "Bold" : ""
        font.weight: Font.Bold
        font.pointSize: Math.round(Kirigami.Theme.defaultFont.pointSize * 7 * root.clockScale)
        font.letterSpacing: -2.5 * root.clockScale
        font.features: { "tnum": 1 }
        renderType: Text.NativeRendering
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: -Kirigami.Units.largeSpacing
    }

    PlasmaClock.Clock {
        id: timeSource
        trackSeconds: Qt.locale().timeFormat(Locale.ShortFormat).includes("s")
    }
}
