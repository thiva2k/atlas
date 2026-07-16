/*
    Atlas KSplash — startup splash between login and desktop (RFC-0037).
    B&W word-only identity (2026-07-16): the ATLAS masthead over a thin
    hairline progress, on flat near-black — so boot → login → splash → desktop
    reads as one continuous power-on of the same wordmark. No logo, no navy,
    no reticle (superseded by the B&W word-only direction).

    STAGE CONTRACT (do not change the shape of this): copied structurally from
    the reference KSplash theme shipped with this system —
    /usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/splash/Splash.qml
    ksplashqml drives a single root item with a `property int stage` that it
    increments 1→6 as startup phases complete (kded, ksmserver, kcminit, etc.);
    the theme reacts via `onStageChanged`. The reference starts a fade-in at
    stage 2 and finishes by stage 5. Atlas mirrors that: content fades in at
    stage 2, the hairline progress fills to complete by stage 5, and the scene
    fades out as ksplashqml tears down. There is no qmllint/qml6 in the
    environment that built this file, so it could not be executed or
    type-checked before shipping — see modules/desktop/lockscreen/README.md's
    honesty note, which applies here too. A bad splash theme falls back to the
    default KSplash theme; it never blocks startup.
*/
import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    readonly property color cBg:     "#070707"
    readonly property color cBlock:  "#f2f2f2"
    readonly property color cShadow: "#5a5a5a"
    readonly property color cTrack:  "#232323"
    readonly property color cFill:   "#e8e8e8"
    readonly property string fMono: "JetBrainsMono Nerd Font Mono"

    readonly property string masthead:
        " █████╗ ████████╗██╗      █████╗ ███████╗\n" +
        "██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝\n" +
        "███████║   ██║   ██║     ███████║███████╗\n" +
        "██╔══██║   ██║   ██║     ██╔══██║╚════██║\n" +
        "██║  ██║   ██║   ███████╗██║  ██║███████║\n" +
        "╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝"

    function blocksOnly() {
        var s = ""
        for (var i = 0; i < masthead.length; i++) {
            var ch = masthead.charAt(i)
            s += (ch === "█" || ch === "\n") ? ch : " "
        }
        return s
    }

    color: cBg

    // ksplashqml increments this 1 (earliest) through 6 (session ready).
    property int stage

    onStageChanged: {
        if (stage == 2) {
            introAnimation.running = true;
        } else if (stage == 5) {
            progressFill.targetProgress = 1.0;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        // ATLAS masthead — two-tone, identical to boot/login/lock.
        Item {
            id: mastheadBox
            width: mShadow.implicitWidth
            height: mShadow.implicitHeight
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Kirigami.Units.gridUnit * 2
            Text {
                id: mShadow
                x: 0; y: 0
                text: root.masthead
                color: root.cShadow
                font.family: root.fMono
                font.pixelSize: 28
                lineHeight: 1.0
            }
            Text {
                x: 0; y: 0
                text: root.blocksOnly()
                color: root.cBlock
                font.family: root.fMono
                font.pixelSize: 28
                lineHeight: 1.0
            }
        }

        // Thin hairline progress, tied to stage — matches the boot progress bar.
        Item {
            width: mastheadBox.width
            height: 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: mastheadBox.bottom
            anchors.topMargin: Kirigami.Units.gridUnit * 3

            Rectangle {
                anchors.fill: parent
                color: root.cTrack
            }
            Rectangle {
                id: progressFill
                property real targetProgress: 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: root.cFill
                width: parent.width * targetProgress
                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
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
