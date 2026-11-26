// Cute frosted pop-up viewfinder showing what the IR camera sees while Howdy scans.
// Frames (frame.jpg) and face bbox + sequence (2x1 face.png) are atomically written by
// Howdy's compare.py to ~/.cache/darc-lockscreen/ir-preview/ when run by kscreenlocker.
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import QtCore

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: root

    // "scanning", "success", "timeout", "dark", "error", or ""
    property string faceState: ""
    property bool lightBackdrop: false
    // Wallpaper item owned by this window (null on secondary screens to avoid Qt cross-window crash)
    property Item backdropItem: null

    // User-configurable preferences
    property bool previewEnabled: true
    property bool previewTracking: true
    property bool mirrorFeed: true
    property bool showShimmer: true
    property real popupScale: 1.0
    property int lingerMs: 1200
    property bool dismissible: true
    property bool frostedGlass: true
    property string fontFamily: ""

    // Override directory for testing in a harness; defaults to ~/.cache/darc-lockscreen/ir-preview
    property string previewDir: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)
                                + "/darc-lockscreen/ir-preview"

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property int bezel: 5
    readonly property int outerRadius: 16
    readonly property int innerRadius: outerRadius - bezel
    readonly property int feedWidth: Math.round(Kirigami.Units.gridUnit * 9 * popupScale)
    readonly property real feedAspect: {
        const img = _useBufferA ? frameA : frameB;
        if (img.status === Image.Ready && img.implicitWidth > 0 && img.implicitHeight > 0) {
            return img.implicitHeight / img.implicitWidth;
        }
        return 400 / 640;
    }
    readonly property int feedHeight: Math.round(feedWidth * feedAspect)

    implicitWidth: feedWidth + bezel * 2
    implicitHeight: feedHeight + bezel * 2
    width: implicitWidth
    height: implicitHeight

    // Internal lifecycle state
    property bool _dismissed: false
    property bool _linger: false
    property bool _hasFrame: false
    property int _pollSeq: 0
    property int _lastFrameSeq: -1
    property int _frameLoadSeq: 0
    property bool _useBufferA: false
    property var _faceBox: null // normalized [x1, y1, x2, y2] in raw frame space
    property var _pendingFaceBox: null
    property real _shakeX: 0

    readonly property bool shouldShow: previewEnabled && !_dismissed && (faceState === "scanning" || _linger)

    visible: opacity > 0.01
    opacity: shouldShow ? 1 : 0
    scale: shouldShow ? 1.0 : 0.84
    transformOrigin: Item.Bottom

    Behavior on opacity {
        NumberAnimation { duration: root.shouldShow ? 180 : 220; easing.type: Easing.InOutQuad }
    }
    Behavior on scale {
        NumberAnimation {
            duration: root.shouldShow ? 280 : 200
            easing.type: root.shouldShow ? Easing.OutBack : Easing.InQuad
            easing.overshoot: 1.35
        }
    }

    onFaceStateChanged: {
        if (faceState === "scanning") {
            _dismissed = false;
            _linger = false;
            _hasFrame = false;
            _faceBox = null;
            _pendingFaceBox = null;
            _lastFrameSeq = -1;
            _frameLoadSeq = 0;
            _useBufferA = false;
            lingerTimer.stop();
            faceLostTimer.stop();
            // Clear stale textures from previous attempt
            frameA.source = "";
            frameB.source = "";
            faceDataCanvas.resetUrl();
            _pollSeq++;
        } else if (faceState === "success") {
            _linger = true;
            faceLostTimer.stop();
            lingerTimer.interval = Math.max(400, root.lingerMs);
            lingerTimer.restart();
        } else if (faceState === "timeout" || faceState === "dark" || faceState === "error") {
            _linger = true;
            faceLostTimer.stop();
            lingerTimer.interval = Math.max(400, root.lingerMs);
            lingerTimer.restart();
            shakeAnim.start();
        } else {
            _linger = false;
            lingerTimer.stop();
            faceLostTimer.stop();
        }
    }

    onOpacityChanged: {
        // Release decoded images once fully hidden
        if (opacity <= 0.01 && !shouldShow) {
            frameA.source = "";
            frameB.source = "";
            faceDataCanvas.resetUrl();
            _hasFrame = false;
            _faceBox = null;
            _pendingFaceBox = null;
            _lastFrameSeq = -1;
        }
    }

    Timer {
        id: lingerTimer
        onTriggered: root._linger = false
    }

    // Hold the tracking square briefly across single missed detections so it never jitters
    Timer {
        id: faceLostTimer
        interval: 220
        onTriggered: {
            root._faceBox = null;
            root._pendingFaceBox = null;
        }
    }

    // Poll tiny 2x1 face.png rapidly until frame 1 lands, then 45 Hz; frame.jpg decodes on seq change
    Timer {
        id: pollTimer
        interval: root._hasFrame ? 22 : 12
        running: root.previewEnabled && root.faceState === "scanning" && !root._dismissed
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._pollSeq++;
            faceDataCanvas.poll(root.previewDir + "/face.png?r=" + root._pollSeq);
        }
    }

    // Decodes 2x1 RGB PNG written by compare.py / howdy-rs:
    // px(0) = (x1*255, y1*255, hasFace ? 255 : 0), px(1) = (x2*255, y2*255, frameSeq)
    // Kept at opacity 1 behind cardContainer with Canvas.Immediate so QtQuick always paints it.
    // Sized 16x4 and sampled at device-pixel edges (0 and devW-1) so HiDPI Canvas scaling never blends px(0) & px(1).
    Canvas {
        id: faceDataCanvas
        x: 20
        y: 20
        width: 16
        height: 4
        renderStrategy: Canvas.Immediate
        property string loadedUrl: ""
        property bool loading: false

        function resetUrl() {
            if (loadedUrl) {
                unloadImage(loadedUrl);
                loadedUrl = "";
            }
            loading = false;
        }
        function poll(url) {
            if (loading) return;
            if (loadedUrl) {
                unloadImage(loadedUrl);
            }
            loading = true;
            loadedUrl = url;
            loadImage(url);
        }

        onImageLoaded: {
            loading = false;
            if (loadedUrl && isImageLoaded(loadedUrl)) {
                requestPaint();
            }
        }
        onPaint: {
            if (!loadedUrl || !isImageLoaded(loadedUrl)) return;
            const dpr = (Window.window && Window.window.devicePixelRatio > 0)
                ? Window.window.devicePixelRatio
                : ((Screen.devicePixelRatio > 0) ? Screen.devicePixelRatio : 1);
            const devW = Math.max(2, Math.floor(width * dpr));
            const ctx = getContext("2d");
            ctx.imageSmoothingEnabled = false;
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(loadedUrl, 0, 0, width, height);
            const row = ctx.getImageData(0, 0, devW, 1).data;
            const p1 = (devW - 1) * 4;
            let box = null;
            if (row[2] > 127) {
                faceLostTimer.stop();
                box = [row[0] / 255.0, row[1] / 255.0, row[p1] / 255.0, row[p1 + 1] / 255.0];
            } else if ((root._faceBox !== null || root._pendingFaceBox !== null) && !faceLostTimer.running) {
                faceLostTimer.start();
            }
            const seq = row[p1 + 2];
            if (seq !== root._lastFrameSeq) {
                root._lastFrameSeq = seq;
                root._pendingFaceBox = box;
                root._frameLoadSeq++;
                const frameUrl = root.previewDir + "/frame.jpg?r=" + root._frameLoadSeq;
                if (root._useBufferA) {
                    frameB.source = frameUrl;
                } else {
                    frameA.source = frameUrl;
                }
            } else if (box !== null) {
                root._pendingFaceBox = box;
                if (root._hasFrame) {
                    root._faceBox = box;
                }
            }
        }
    }

    // Failure shake (matches FaceIdStatus)
    SequentialAnimation {
        id: shakeAnim
        PropertyAnimation { target: root; property: "_shakeX"; to: -5; duration: 45; easing.type: Easing.OutQuad }
        PropertyAnimation { target: root; property: "_shakeX"; to:  5; duration: 45; easing.type: Easing.OutQuad }
        PropertyAnimation { target: root; property: "_shakeX"; to: -3; duration: 45; easing.type: Easing.OutQuad }
        PropertyAnimation { target: root; property: "_shakeX"; to:  3; duration: 45; easing.type: Easing.OutQuad }
        PropertyAnimation { target: root; property: "_shakeX"; to:  0; duration: 45; easing.type: Easing.OutQuad }
    }

    Item {
        id: cardContainer
        anchors.fill: parent
        transform: Translate { x: root._shakeX }

        // Soft drop shadow behind the floating mini-window
        Rectangle {
            id: shadowSource
            anchors.fill: parent
            radius: root.outerRadius
            color: "black"
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            visible: !root.softwareRendering
            source: shadowSource
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.55)
            shadowBlur: 1.0
            blurMax: 24
            shadowVerticalOffset: 6
            autoPaddingEnabled: true
            opacity: 0.75
        }

        // Frosted glass backdrop (mirrors NowPlayingCard approach, safe when backdropItem is null)
        ShaderEffectSource {
            id: glassSource
            anchors.fill: parent
            visible: false
            sourceItem: root.backdropItem
            live: true
            function updateRect() {
                if (root.backdropItem && root.width > 0 && root.height > 0) {
                    sourceRect = cardContainer.mapToItem(root.backdropItem, 0, 0, root.width, root.height);
                }
            }
        }
        Rectangle {
            id: glassMask
            anchors.fill: parent
            radius: root.outerRadius
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            visible: !root.softwareRendering && root.frostedGlass && root.backdropItem !== null
            source: glassSource
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            saturation: 0.25
            brightness: root.lightBackdrop ? 0.25 : -0.35
            maskEnabled: true
            maskSource: glassMask
        }

        Connections {
            target: root
            function onXChanged() { glassSource.updateRect(); }
            function onYChanged() { glassSource.updateRect(); }
            function onWidthChanged() { glassSource.updateRect(); }
            function onHeightChanged() { glassSource.updateRect(); }
            function onBackdropItemChanged() { glassSource.updateRect(); }
            function onShouldShowChanged() { if (root.shouldShow) glassSource.updateRect(); }
        }
        Timer { interval: 250; running: root.shouldShow; onTriggered: glassSource.updateRect() }

        // Frosted bezel shell
        Rectangle {
            anchors.fill: parent
            radius: root.outerRadius
            color: root.lightBackdrop ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(0.08, 0.09, 0.12, 0.48)
            border.width: 1
            border.color: {
                if (root.faceState === "success") return Qt.rgba(0.20, 0.83, 0.60, 0.85);
                if (root.faceState === "timeout" || root.faceState === "dark" || root.faceState === "error")
                    return Qt.rgba(0.97, 0.44, 0.44, 0.75);
                return Qt.rgba(1, 1, 1, root.lightBackdrop ? 0.55 : 0.24);
            }
            Behavior on border.color { ColorAnimation { duration: 180 } }
        }

        // Inner rounded IR viewfinder
        Item {
            id: viewport
            anchors.fill: parent
            anchors.margins: root.bezel
            clip: true

            // Dark lens backing before first frame arrives
            Rectangle {
                anchors.fill: parent
                radius: root.innerRadius
                color: Qt.rgba(0.05, 0.06, 0.08, 0.92)
            }

            // Subtle waking indicator until frame 1 lands
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4
                visible: !root._hasFrame

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: Qt.resolvedUrl("icons/face-id.svg")
                    color: Qt.rgba(1, 1, 1, 0.75)
                    isMask: true

                    SequentialAnimation on opacity {
                        running: root.shouldShow && !root._hasFrame
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.9; to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.3; to: 0.9; duration: 600; easing.type: Easing.InOutSine }
                    }
                }
            }

            // Double-buffered mirrored IR camera feed with gentle 50ms crossfade between frames
            Image {
                id: frameA
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                visible: root.softwareRendering && root._hasFrame && root._useBufferA
                transform: Scale { origin.x: frameA.width / 2; xScale: (root.softwareRendering && root.mirrorFeed) ? -1 : 1 }
                onStatusChanged: {
                    if (status === Image.Ready) {
                        root._hasFrame = true;
                        root._useBufferA = true;
                        if (root._pendingFaceBox !== null) {
                            root._faceBox = root._pendingFaceBox;
                        }
                    }
                }
            }
            Image {
                id: frameB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                visible: root.softwareRendering && root._hasFrame && !root._useBufferA
                transform: Scale { origin.x: frameB.width / 2; xScale: (root.softwareRendering && root.mirrorFeed) ? -1 : 1 }
                onStatusChanged: {
                    if (status === Image.Ready) {
                        root._hasFrame = true;
                        root._useBufferA = false;
                        if (root._pendingFaceBox !== null) {
                            root._faceBox = root._pendingFaceBox;
                        }
                    }
                }
            }
            Rectangle {
                id: feedMask
                width: viewport.width
                height: viewport.height
                radius: root.innerRadius
                visible: false
            }
            OpacityMask {
                id: maskA
                anchors.fill: parent
                z: 0
                visible: !root.softwareRendering && root._hasFrame && frameA.status === Image.Ready
                transform: Scale { origin.x: maskA.width / 2; xScale: root.mirrorFeed ? -1 : 1 }
                source: frameA
                maskSource: feedMask
            }
            OpacityMask {
                id: maskB
                anchors.fill: parent
                z: 1
                visible: !root.softwareRendering && root._hasFrame && opacity > 0.01
                opacity: root._useBufferA ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 25; easing.type: Easing.OutQuad } }
                transform: Scale { origin.x: maskB.width / 2; xScale: root.mirrorFeed ? -1 : 1 }
                source: frameB
                maskSource: feedMask
            }

            // Subtle scanning shimmer sweep while actively scanning
            Rectangle {
                id: scanSweep
                z: 2
                width: parent.width
                height: 22
                visible: root.showShimmer && root.faceState === "scanning" && root._hasFrame
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(0.65, 0.95, 1.0, 0.14) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                SequentialAnimation on y {
                    running: scanSweep.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: -22; to: viewport.height; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { from: viewport.height; to: -22; duration: 1400; easing.type: Easing.InOutSine }
                }
            }

            // Subtle vignette / inner lens edge
            Rectangle {
                z: 2
                anchors.fill: parent
                radius: root.innerRadius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.35)
            }

            // Cute face-tracking corner brackets (mirrors x only when mirrorFeed is enabled)
            Item {
                id: reticle
                z: 3
                readonly property bool hasFace: root.previewTracking && root._faceBox !== null && root._hasFrame
                readonly property real rawX1: hasFace ? (root.mirrorFeed ? (1.0 - root._faceBox[2]) : root._faceBox[0]) : 0
                readonly property real targetW: hasFace
                    ? Math.max(24, Math.min(viewport.width - 8, (root._faceBox[2] - root._faceBox[0]) * viewport.width))
                    : 46
                readonly property real targetH: hasFace
                    ? Math.max(24, Math.min(viewport.height - 8, (root._faceBox[3] - root._faceBox[1]) * viewport.height))
                    : 46
                readonly property real targetX: hasFace
                    ? Math.max(4, Math.min(viewport.width - targetW - 4, rawX1 * viewport.width))
                    : (viewport.width - 46) / 2
                readonly property real targetY: hasFace
                    ? Math.max(4, Math.min(viewport.height - targetH - 4, root._faceBox[1] * viewport.height))
                    : (viewport.height - 46) / 2

                x: targetX
                y: targetY
                width: targetW
                height: targetH
                visible: root.previewTracking && root._hasFrame && (hasFace || root.faceState === "scanning")
                opacity: hasFace ? 0.95 : 0.42

                Behavior on x { NumberAnimation { duration: 35; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 35; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 35; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 35; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 120 } }

                readonly property color bracketColor: root.faceState === "success"
                    ? "#34D399"
                    : ((root.faceState === "timeout" || root.faceState === "dark" || root.faceState === "error")
                        ? "#F87171"
                        : (hasFace ? "#6EE7B7" : Qt.rgba(1, 1, 1, 0.85)))

                Canvas {
                    id: bracketCanvas
                    anchors.fill: parent
                    property color strokeColor: reticle.bracketColor
                    onStrokeColorChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const len = Math.min(10, Math.min(width, height) * 0.28);
                        const r = 4;
                        const p = 1.5;
                        ctx.strokeStyle = strokeColor;
                        ctx.lineWidth = 1.8;
                        ctx.lineCap = "round";
                        ctx.beginPath();
                        // Top-left
                        ctx.moveTo(p, p + len); ctx.lineTo(p, p + r); ctx.quadraticCurveTo(p, p, p + r, p); ctx.lineTo(p + len, p);
                        // Top-right
                        ctx.moveTo(width - p - len, p); ctx.lineTo(width - p - r, p); ctx.quadraticCurveTo(width - p, p, width - p, p + r); ctx.lineTo(width - p, p + len);
                        // Bottom-left
                        ctx.moveTo(p, height - p - len); ctx.lineTo(p, height - p - r); ctx.quadraticCurveTo(p, height - p, p + r, height - p); ctx.lineTo(p + len, height - p);
                        // Bottom-right
                        ctx.moveTo(width - p - len, height - p); ctx.lineTo(width - p - r, height - p); ctx.quadraticCurveTo(width - p, height - p, width - p, height - p - r); ctx.lineTo(width - p, height - p - len);
                        ctx.stroke();
                    }
                }
            }

            // Success wash + crisp checkmark badge
            Rectangle {
                z: 4
                anchors.fill: parent
                radius: root.innerRadius
                color: Qt.rgba(0.10, 0.72, 0.48, 0.22)
                opacity: root.faceState === "success" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Rectangle {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    radius: 15
                    color: "#10B981"
                    scale: root.faceState === "success" ? 1.0 : 0.5
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: Qt.resolvedUrl("icons/checkmark.svg")
                        color: "white"
                        isMask: true
                    }
                }
            }

            // Failure / dark / timeout status overlay pill
            Rectangle {
                z: 4
                anchors.centerIn: parent
                width: failLabel.implicitWidth + 14
                height: failLabel.implicitHeight + 8
                radius: height / 2
                color: Qt.rgba(0.08, 0.08, 0.10, 0.78)
                border.width: 1
                border.color: Qt.rgba(0.97, 0.44, 0.44, 0.55)
                visible: root.faceState === "timeout" || root.faceState === "dark" || root.faceState === "error"

                PlasmaComponents3.Label {
                    id: failLabel
                    anchors.centerIn: parent
                    text: root.faceState === "dark" ? "Too dark"
                          : (root.faceState === "error" ? "Camera error" : "No match")
                    color: "white"
                    font.family: root.fontFamily !== "" ? root.fontFamily : Kirigami.Theme.defaultFont.family
                    font.styleName: root.fontFamily === "SF Pro Text" ? "Semibold" : ""
                    font.weight: Font.DemiBold
                    font.pixelSize: 10
                    textFormat: Text.PlainText
                }
            }

            // Cute top-left "IR" live pill
            Rectangle {
                z: 5
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 6
                height: 16
                width: pillRow.implicitWidth + 10
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.46)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)

                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 4

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: root.faceState === "success" ? "#34D399"
                             : (root.faceState === "scanning" ? "#34D399" : "#F87171")

                        SequentialAnimation on opacity {
                            running: root.faceState === "scanning"
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.25; duration: 550; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.25; to: 1.0; duration: 550; easing.type: Easing.InOutSine }
                            onRunningChanged: if (!running) opacity = 1.0
                        }
                    }

                    PlasmaComponents3.Label {
                        text: "IR"
                        color: Qt.rgba(1, 1, 1, 0.92)
                        font.family: root.fontFamily !== "" ? root.fontFamily : Kirigami.Theme.defaultFont.family
                        font.styleName: root.fontFamily === "SF Pro Text" ? "Semibold" : ""
                        font.weight: Font.DemiBold
                        font.pixelSize: 9
                        textFormat: Text.PlainText
                    }
                }
            }
        }

        // Click to tuck the preview away for the current scan attempt
        MouseArea {
            anchors.fill: parent
            enabled: root.dismissible
            cursorShape: root.dismissible ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.dismissible) root._dismissed = true
        }
    }
}
