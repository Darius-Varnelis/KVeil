// Measures how bright the wallpaper is behind each lock screen zone so text and
// icons can switch reliably between light and dark. Grabs a downscaled copy of the
// wallpaper, draws it into a Canvas and computes perceptual luminance per region.
// Results are cached per wallpaper configuration so the right color is ready on frame 0.
// Put it underneath everything else: the Canvas has to be rendered to paint.
import QtQuick
import QtQuick.LocalStorage

Item {
    id: root

    property Item source
    property bool sourceLoading: false
    property string cacheKey: ""
    property bool dynamicWallpaper: false

    function _openDb() {
        return LocalStorage.openDatabaseSync("kveil_backdrop", "1.0", "KVeil backdrop luminance cache", 16384);
    }

    function _readCache(key: string): var {
        if (!key) {
            return null;
        }
        try {
            const db = _openDb();
            let entry = null;
            db.readTransaction(tx => {
                const rs = tx.executeSql(
                    "SELECT clockLuma, infoLuma, statusLuma, bottomLuma FROM backdrop WHERE cacheKey=?",
                    [key]
                );
                if (rs.rows.length > 0) {
                    const row = rs.rows.item(0);
                    const valid = v => typeof v === "number" && v >= 0 && v <= 1 && !isNaN(v);
                    if (valid(row.clockLuma) && valid(row.infoLuma) && valid(row.statusLuma) && valid(row.bottomLuma)) {
                        entry = {
                            clockLuma: row.clockLuma,
                            infoLuma: row.infoLuma,
                            statusLuma: row.statusLuma,
                            bottomLuma: row.bottomLuma
                        };
                    }
                }
            });
            return entry;
        } catch (e) {
            return null;
        }
    }

    function _writeCache(key: string, cl: real, il: real, sl: real, bl: real) {
        if (!key) {
            return;
        }
        try {
            const db = _openDb();
            db.transaction(tx => {
                tx.executeSql(
                    "CREATE TABLE IF NOT EXISTS backdrop(cacheKey TEXT PRIMARY KEY, clockLuma REAL, infoLuma REAL, statusLuma REAL, bottomLuma REAL)"
                );
                tx.executeSql(
                    "INSERT OR REPLACE INTO backdrop(cacheKey, clockLuma, infoLuma, statusLuma, bottomLuma) VALUES(?, ?, ?, ?, ?)",
                    [key, cl, il, sl, bl]
                );
            });
        } catch (e) {
        }
    }

    readonly property var _initialCache: _readCache(cacheKey)

    // Effective relative luminance (0..1) of each zone; cached per wallpaper key or 0.5 until sampled
    property real clockLuma: _initialCache ? _initialCache.clockLuma : 0.5
    property real infoLuma: _initialCache ? _initialCache.infoLuma : 0.5
    property real statusLuma: _initialCache ? _initialCache.statusLuma : 0.5
    property real bottomLuma: _initialCache ? _initialCache.bottomLuma : 0.5
    property bool _sampledForCurrentKey: _initialCache !== null

    // Normalised [x, y, w, h] regions matching the layout in LockScreenUi
    readonly property var clockRegion: [0.30, 0.06, 0.40, 0.17]   // date & clock
    readonly property var infoRegion: [0.26, 0.22, 0.48, 0.18]    // greeting, weather, Now Playing
    readonly property var statusRegion: [0.79, 0.01, 0.20, 0.06]  // top-right status items
    readonly property var bottomRegion: [0.34, 0.72, 0.32, 0.25]  // avatar, name, prompt, actions

    readonly property int sampleWidth: 96
    readonly property int sampleHeight: 60

    function sample() {
        if (!source || !Window.window || !source.Window.window || source.width <= 0 || source.height <= 0) {
            return;
        }
        if (sourceLoading) {
            return;
        }
        source.grabToImage(result => { grabbed.source = result.url; }, Qt.size(sampleWidth, sampleHeight));
    }

    onSourceChanged: if (source && (!_sampledForCurrentKey || dynamicWallpaper)) sample()
    onSourceLoadingChanged: {
        if (!sourceLoading && (!_sampledForCurrentKey || dynamicWallpaper)) {
            sample();
        }
    }
    onCacheKeyChanged: {
        const entry = _readCache(cacheKey);
        if (entry) {
            clockLuma = entry.clockLuma;
            infoLuma = entry.infoLuma;
            statusLuma = entry.statusLuma;
            bottomLuma = entry.bottomLuma;
            _sampledForCurrentKey = true;
            if (dynamicWallpaper) {
                sample();
            }
        } else {
            _sampledForCurrentKey = false;
            sample();
        }
    }
    Connections {
        target: root.source
        function onWidthChanged() {
            if (!root._sampledForCurrentKey || root.dynamicWallpaper) root.sample();
        }
        function onHeightChanged() {
            if (!root._sampledForCurrentKey || root.dynamicWallpaper) root.sample();
        }
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
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(grabbed, 0, 0, width, height);
            const full = ctx.getImageData(0, 0, width, height).data;
            let hasOpaque = false;
            for (let i = 3; i < full.length; i += 4) {
                if (full[i] > 0) {
                    hasOpaque = true;
                    break;
                }
            }
            if (!hasOpaque) {
                return;
            }
            root.clockLuma = regionLuma(ctx, root.clockRegion);
            root.infoLuma = regionLuma(ctx, root.infoRegion);
            root.statusLuma = regionLuma(ctx, root.statusRegion);
            root.bottomLuma = regionLuma(ctx, root.bottomRegion);
            root._sampledForCurrentKey = true;
            root._writeCache(root.cacheKey, root.clockLuma, root.infoLuma, root.statusLuma, root.bottomLuma);
        }
    }

    // Wait for the wallpaper to finish painting before sampling; dynamic plugins also refresh periodically.
    Timer {
        id: sampleTimer
        property int runs: 0
        interval: !root._sampledForCurrentKey ? 400 : 60000
        running: !root._sampledForCurrentKey || root.dynamicWallpaper
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            runs++;
            if (root._sampledForCurrentKey && !root.dynamicWallpaper) {
                return;
            }
            if (!root._sampledForCurrentKey && runs > 15 && !root.dynamicWallpaper) {
                stop();
                return;
            }
            root.sample();
        }
    }
}
