/*
    Atlas KSplash — startup splash between login and desktop (RFC-0037).

    STAGE CONTRACT (do not change the shape of this): copied structurally from
    the reference KSplash theme shipped with this system —
    /usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/splash/Splash.qml
    ksplashqml drives a single root item with a `property int stage` that it
    increments 1→6 as startup phases complete (kded, ksmserver, kcminit, etc.);
    the theme reacts via `onStageChanged`. The reference starts a fade-in at
    stage 2 and starts a fade-out (of its busy indicator) at stage 5. Atlas
    mirrors that exact pattern: content fades in at stage 2, and the reticle
    brackets + hairline progress lock to "complete" by stage 5, with the whole
    scene fading out as ksplashqml tears down. There is no qmllint/qml6 in the
    environment that built this file, so it could not be executed or
    type-checked before shipping — see modules/desktop/lockscreen/README.md's
    honesty note, which applies here too. A bad splash theme falls back to the
    default KSplash theme; it never blocks startup.

    VISUAL DESIGN: deep navy gradient ground + faint grid (matches the
    lock-screen HUD and the Plymouth boot ignition's END state, so
    boot -> splash -> desktop reads as one continuous instrument power-on),
    the Orbital-A identity mark centered, the #57e5ff live node, and a thin
    hairline progress indicator plus reticle corner-brackets that lock as
    `stage` advances — restrained, ~1s on screen, no heavy animation. Colors
    are the Atlas HUD tokens (modules/desktop/identity/tokens.env), inlined
    here since QML cannot source a shell env file.
*/
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    // --- Atlas HUD tokens (modules/desktop/identity/tokens.env) ----------------
    readonly property color atlasNavy900: "#0a0e14"
    readonly property color atlasNavy800: "#0d1420"
    readonly property color atlasNavy400: "#243247"
    readonly property color atlasInk: "#e6edf3"
    readonly property color atlasDim: "#7d8aa0"
    readonly property color atlasCyan: "#57e5ff"

    color: atlasNavy900

    // ksplashqml increments this 1 (earliest) through 6 (session ready) as
    // startup phases complete. Mirrors org.kde.breeze.desktop exactly.
    property int stage

    onStageChanged: {
        if (stage == 2) {
            introAnimation.running = true;
        } else if (stage == 5) {
            // Startup is nearly done: lock the reticle brackets closed and
            // finish the hairline sweep, same beat as the reference theme's
            // busy-indicator fade-out at stage 5.
            reticleLock.running = true;
            progressFill.targetProgress = 1.0;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        // --- Ground: deep navy gradient + faint grid, echoes the lock HUD ------
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: root.atlasNavy800 }
                GradientStop { position: 1.0; color: root.atlasNavy900 }
            }

            Canvas {
                id: gridCanvas
                anchors.fill: parent
                opacity: 0.05
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = root.atlasInk;
                    ctx.lineWidth = 1;
                    const step = 64;
                    for (let x = 0; x < width; x += step) {
                        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
                    }
                    for (let y = 0; y < height; y += step) {
                        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                    }
                }
            }
        }

        // --- Orbital-A identity mark, centered ----------------------------------
        Item {
            id: markBlock
            anchors.centerIn: parent
            readonly property real size: Kirigami.Units.gridUnit * 8
            width: size
            height: size

            Image {
                id: mark
                anchors.centerIn: parent
                asynchronous: true
                source: "images/atlas-mark.png"
                sourceSize.width: markBlock.size
                sourceSize.height: markBlock.size
                smooth: true
            }

            // Reticle corner-brackets around the mark: closed (locked) once
            // startup nears completion (stage 5), echoing the lock-screen HUD's
            // reveal and the Plymouth boot ignition's bracket lock-on.
            component ReticleCorner: Shape {
                id: corner
                required property int corner // 0=TL 1=TR 2=BL 3=BR
                width: 20
                height: 20
                property real reveal: 0
                opacity: reveal
                ShapePath {
                    strokeColor: root.atlasCyan
                    strokeWidth: 2
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    startX: corner.corner % 2 === 0 ? 0 : corner.width
                    startY: corner.corner < 2 ? corner.height * corner.reveal : corner.height * (1 - corner.reveal)
                    PathLine {
                        x: corner.corner % 2 === 0 ? 0 : corner.width
                        y: corner.corner < 2 ? 0 : corner.height
                    }
                    PathLine {
                        x: corner.corner % 2 === 0 ? corner.width * corner.reveal : corner.width * (1 - corner.reveal)
                        y: corner.corner < 2 ? 0 : corner.height
                    }
                }
            }

            readonly property real bracketInset: markBlock.size * 0.62
            ReticleCorner { id: cornerTl; corner: 0; x: -markBlock.bracketInset; y: -markBlock.bracketInset }
            ReticleCorner { id: cornerTr; corner: 1; x: markBlock.bracketInset - width; y: -markBlock.bracketInset }
            ReticleCorner { id: cornerBl; corner: 2; x: -markBlock.bracketInset; y: markBlock.bracketInset - height }
            ReticleCorner { id: cornerBr; corner: 3; x: markBlock.bracketInset - width; y: markBlock.bracketInset - height }

            ParallelAnimation {
                id: reticleLock
                running: false
                NumberAnimation { target: cornerTl; property: "reveal"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: cornerTr; property: "reveal"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: cornerBl; property: "reveal"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: cornerBr; property: "reveal"; to: 1; duration: 260; easing.type: Easing.OutCubic }
            }
        }

        // --- Thin hairline progress, tied to stage ------------------------------
        Item {
            id: progressBlock
            width: Math.min(parent.width * 0.22, 280)
            height: 1
            anchors.horizontalCenter: parent.horizontalCenter
            y: markBlock.y + markBlock.height + Kirigami.Units.gridUnit * 3

            Rectangle {
                id: progressTrack
                anchors.fill: parent
                color: root.atlasNavy400
            }

            Rectangle {
                id: progressFill
                property real targetProgress: 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: root.atlasCyan
                width: parent.width * targetProgress

                Behavior on width {
                    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                }
            }

            // The live node — the ONE scarce cyan glow, riding the fill's edge.
            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: root.atlasCyan
                anchors.verticalCenter: progressFill.verticalCenter
                x: progressFill.width - width / 2
                visible: progressFill.width > 0
            }
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: Kirigami.Units.veryLongDuration * 2
        easing.type: Easing.InOutQuad
    }
}
