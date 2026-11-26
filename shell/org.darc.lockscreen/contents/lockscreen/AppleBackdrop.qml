// Measures how bright the wallpaper is behind each lock screen zone so text and
// icons can switch reliably between light and dark. Grabs a downscaled copy of the
// wallpaper, draws it into a Canvas and computes perceptual luminance per region.
// Put it underneath everything else: the Canvas has to be rendered to paint.
import QtQuick

Item {
    id: root

    property Item source
    // Effective relative luminance (0..1) of each zone; 0.5 until the first sample
    property real clockLuma: 0.5
    property real infoLuma: 0.5
    property real statusLuma: 0.5
    property real bottomLuma: 0.5

    // Normalised [x, y, w, h] regions matching the layout in LockScreenUi
    readonly property var clockRegion: [0.30, 0.06, 0.40, 0.17]   // date & clock
    readonly property var infoRegion: [0.26, 0.22, 0.48, 0.18]    // greeting, weather, Now Playing
    readonly property var statusRegion: [0.79, 0.01, 0.20, 0.06]  // top-right status items
    readonly property var bottomRegion: [0.34, 0.72, 0.32, 0.25]  // avatar, name, prompt, actions

    readonly property int sampleWidth: 96
    readonly property int sampleHeight: 60

    function sample() {
        if (!source || source.width <= 0 || source.height <= 0) {
            return;
        }
        source.grabToImage(result => { grabbed.source = result.url; }, Qt.size(sampleWidth, sampleHeight));
    }

    onSourceChanged: if (source) sample()
    Connections {
        target: root.source
        function onWidthChanged() { root.sample(); }
        function onHeightChanged() { root.sample(); }
    }

    width: sampleWidth
    height: sampleHeight

    Image {
        id: grabbed
        visible: false
        cache: false
        onStatusChanged: if (status === Image.Ready) canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Immediate

        function regionLuma(ctx, r) {
            const x = Math.round(r[0] * width), y = Math.round(r[1] * height);
            const w = Math.max(1, Math.round(r[2] * width)), h = Math.max(1, Math.round(r[3] * height));
            const d = ctx.getImageData(x, y, w, h).data;
            const lumas = [];
            let sumSrgb = 0;
            for (let i = 0; i < d.length; i += 4) {
                const sr = d[i] / 255, sg = d[i + 1] / 255, sb = d[i + 2] / 255;
                // Perceptual luma in sRGB avoids linear averaging over-weighting sparse darks/brights
                const sLuma = 0.2126 * sr + 0.7152 * sg + 0.0722 * sb;
                sumSrgb += sLuma;
                const lin = c => c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
                lumas.push(0.2126 * lin(sr) + 0.7152 * lin(sg) + 0.0722 * lin(sb));
            }
            lumas.sort((a, b) => a - b);
            const p60 = lumas[Math.min(lumas.length - 1, Math.floor(lumas.length * 0.60))];
            const meanS = sumSrgb / lumas.length;
            const meanFromSrgb = meanS <= 0.04045 ? meanS / 12.92 : Math.pow((meanS + 0.055) / 1.055, 2.4);
            return 0.5 * meanFromSrgb + 0.5 * p60;
        }

        onPaint: {
            if (grabbed.status !== Image.Ready) {
                return;
            }
            const ctx = getContext("2d");
            ctx.drawImage(grabbed, 0, 0, width, height);
            root.clockLuma = regionLuma(ctx, root.clockRegion);
            root.infoLuma = regionLuma(ctx, root.infoRegion);
            root.statusLuma = regionLuma(ctx, root.statusRegion);
            root.bottomLuma = regionLuma(ctx, root.bottomRegion);
        }
    }

    // The wallpaper (e.g. picture of the day) loads asynchronously, so sample a few times early on
    Timer {
        id: sampleTimer
        property int runs: 0
        interval: runs < 6 ? 800 : 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { runs++; root.sample(); }
    }
}
