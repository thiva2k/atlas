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
