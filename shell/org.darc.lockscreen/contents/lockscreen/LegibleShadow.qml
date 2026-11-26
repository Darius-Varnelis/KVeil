// Soft drop shadow behind light lock screen text so it stays readable on busy dark/mid wallpapers.
// Disabled on bright backdrops (dark text needs no white glow). Use as `layer.effect`.
import QtQuick
import QtQuick.Effects

MultiEffect {
    property bool light: false

    shadowEnabled: !light
    shadowColor: Qt.rgba(0, 0, 0, 0.98)
    shadowOpacity: light ? 0.0 : 1.0
    shadowBlur: 1.0
    blurMax: 12
    shadowScale: 1.0
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 0.8
    autoPaddingEnabled: true
}
