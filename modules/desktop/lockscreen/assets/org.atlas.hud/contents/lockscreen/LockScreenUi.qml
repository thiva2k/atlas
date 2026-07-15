/*
    Atlas lock-screen HUD — main UI.

    AUTH WIRING (do not change the shape of this): copied structurally from the
    reference kscreenlocker greeter package shipped with this system —
    /usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml
    and MainBlock.qml (same directory). kscreenlocker_greet injects a context
    property named `authenticator` (org.kde.kscreenlocker's ScreenLocker.Authenticator)
    and a root Item (see LockScreen.qml) with clearPassword()/notification/viewVisible.
    The unlock call is `authenticator.respond(password)` — NOT `tryUnlock()`, and the
    listened signals are `authenticator.succeeded`/`failed`/`infoMessageChanged`/
    `errorMessageChanged`/`promptChanged`/`promptForSecretChanged`, wired via a single
    Connections{ target: authenticator } block exactly like the reference. On success
    with a prompt, the reference calls Qt.quit() to let kscreenlocker tear the greeter
    down; that call is preserved verbatim below.

    VISUAL DESIGN (Fable's brief, restrained): deep navy ground, a faint grid, a large
    off-center armillary that drifts at constant linear velocity (one revolution per
    ATLAS_MOTION_AMBIENT ms), a giant thin clock framed by four reticle corner-brackets
    that play a lock-on animation once on wake, and a bare hairline-underline password
    field (no boxed TextField, no frosted panel, no avatar ring). Colors are the Atlas
    HUD tokens (modules/desktop/identity/tokens.env), inlined here since QML cannot
    source a shell env file.
*/
import QtQml
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Shapes

import org.kde.plasma.clock as PlasmaClock
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.plasma.private.sessions
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // --- Atlas HUD tokens (modules/desktop/identity/tokens.env) ----------------
    readonly property color atlasNavy900: "#0a0e14"
    readonly property color atlasNavy800: "#0d1420"
    readonly property color atlasNavy400: "#243247"
    readonly property color atlasInk: "#e6edf3"
    readonly property color atlasDim: "#7d8aa0"
    readonly property color atlasCyan: "#57e5ff"
    readonly property color atlasWarm: "#ff6b5a"
    readonly property int atlasMotionFast: 180
    readonly property int atlasMotionAmbient: 240000 // one armillary revolution, linear

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

    function handleMessage(msg) {
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    // --- Auth wiring: copied structurally from the reference greeter -----------
    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            const msg = "Unlocking failed";
            lockScreenUi.handleMessage(msg);
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            wrongPasswordFlash.start();
        }

        function onSucceeded() {
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                passwordBox.enabled = false;
            }
        }

        function onInfoMessageChanged() {
            lockScreenUi.handleMessage(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            lockScreenUi.handleMessage(authenticator.errorMessage);
        }

        function onPromptChanged(msg) {
            lockScreenUi.handleMessage(authenticator.prompt);
        }
        function onPromptForSecretChanged(msg) {
            passwordBox.echoMode = TextInput.Password;
            passwordBox.forceActiveFocus();
        }
    }

    SessionManagement {
        id: sessionManagement
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            root.clearPassword();
        }
    }

    MouseArea {
        id: lockScreenRoot
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor

        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: root.notification = ""
        }
        Timer {
            id: graceLockTimer
            interval: 3000
            onTriggered: {
                root.clearPassword();
                authenticator.startAuthenticating();
            }
        }

        Component.onCompleted: authenticator.startAuthenticating();

        // --- Ground: deep navy gradient + faint grid ----------------------------
        Rectangle {
            id: ground
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: lockScreenUi.atlasNavy800 }
                GradientStop { position: 1.0; color: lockScreenUi.atlasNavy900 }
            }

            Canvas {
                id: gridCanvas
                anchors.fill: parent
                opacity: 0.05
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = lockScreenUi.atlasInk;
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

        // --- Armillary: 3 tilted ellipses + a node, constant-velocity drift -----
        // Restraint: this is the ONLY element that keeps moving after wake; the
        // reticle lock-on (below) plays once and then holds still.
        Item {
            id: armillary
            width: Math.min(parent.width, parent.height) * 0.9
            height: width
            x: parent.width * 0.62
            y: parent.height * 0.18

            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: lockScreenUi.atlasMotionAmbient
                loops: Animation.Infinite
                easing.type: Easing.Linear
                running: true
            }

            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    width: armillary.width * (0.55 + index * 0.18)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: lockScreenUi.atlasNavy400
                    border.width: 1
                    opacity: 0.55
                    rotation: index * 55
                    transform: Scale { origin.x: width / 2; origin.y: height / 2; yScale: 0.42 }
                }
            }

            Rectangle {
                id: armillaryNode
                width: 8
                height: 8
                radius: 4
                color: lockScreenUi.atlasCyan
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.02
                opacity: 0.9
            }
        }

        // --- Giant clock, thin weight, tabular figures, reticle brackets --------
        Item {
            id: clockBlock
            anchors.centerIn: parent
            width: clockLabel.implicitWidth + 96
            height: clockLabel.implicitHeight + 48

            PlasmaClock.Clock {
                id: timeSource
                trackSeconds: false
            }

            Text {
                id: clockLabel
                anchors.centerIn: parent
                text: Qt.formatTime(timeSource.dateTime, "hh:mm")
                color: lockScreenUi.atlasInk
                font.family: "Inter"
                font.weight: Font.Thin
                font.pixelSize: 180
                font.hintingPreference: Font.PreferNoHinting
                renderType: Text.NativeRendering
                // Tabular figures: Inter supports the OpenType "tnum" feature so
                // digit glyphs are fixed-width and the clock does not jitter as
                // digits change. font.features is available on QQuickText since Qt 6.7.
                font.features: ({ "tnum": 1 })
            }

            // Reticle corner-brackets: an L-shaped stroke per corner that plays a
            // lock-on reveal once on wake, then holds still (restraint: only the
            // armillary keeps moving after this).
            component ReticleCorner: Shape {
                id: corner
                required property int corner // 0=TL 1=TR 2=BL 3=BR
                width: 28
                height: 28
                property real reveal: 0
                opacity: reveal
                ShapePath {
                    strokeColor: lockScreenUi.atlasCyan
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

                SequentialAnimation {
                    running: true
                    PauseAnimation { duration: 220 }
                    NumberAnimation { target: corner; property: "reveal"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
                }
            }

            ReticleCorner { corner: 0; anchors.top: parent.top; anchors.left: parent.left }
            ReticleCorner { corner: 1; anchors.top: parent.top; anchors.right: parent.right }
            ReticleCorner { corner: 2; anchors.bottom: parent.bottom; anchors.left: parent.left }
            ReticleCorner { corner: 3; anchors.bottom: parent.bottom; anchors.right: parent.right }
        }

        // --- Password field: bare hairline underline, no box, no frame ---------
        Item {
            id: passwordArea
            width: Math.min(parent.width * 0.32, 420)
            height: 56
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: clockBlock.bottom
            anchors.topMargin: 64

            // warm flash + shake react to a wrong-password onFailed
            property real shakeOffset: 0
            transform: Translate { x: passwordArea.shakeOffset }

            SequentialAnimation {
                id: wrongPasswordFlash
                ScriptAction { script: underlineFlash.color = lockScreenUi.atlasWarm }
                SequentialAnimation {
                    loops: 1
                    NumberAnimation { target: passwordArea; property: "shakeOffset"; to: -6; duration: 40 }
                    NumberAnimation { target: passwordArea; property: "shakeOffset"; to: 6; duration: 80 }
                    NumberAnimation { target: passwordArea; property: "shakeOffset"; to: 0; duration: 40 }
                }
                PauseAnimation { duration: 260 }
                ScriptAction { script: underlineFlash.color = lockScreenUi.atlasNavy400 }
                // single satellite pulse on the armillary node, once
                ScriptAction { script: satellitePulse.start() }
            }

            SequentialAnimation {
                id: satellitePulse
                NumberAnimation { target: armillaryNode; property: "scale"; to: 2.2; duration: 160; easing.type: Easing.OutQuad }
                NumberAnimation { target: armillaryNode; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.InQuad }
            }

            QQC2.TextField {
                id: passwordBox
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: underline.top
                anchors.bottomMargin: 8

                background: Item {} // no frame, no box — the design refuses a boxed TextField
                color: lockScreenUi.atlasInk
                font.family: "Inter"
                font.pixelSize: 22
                echoMode: TextInput.Password
                placeholderText: "Password"
                placeholderTextColor: lockScreenUi.atlasDim
                selectionColor: lockScreenUi.atlasCyan
                cursorVisible: activeFocus
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                enabled: !authenticator.graceLocked
                focus: true

                onAccepted: lockScreenUi.startLogin()

                Keys.onPressed: event => {
                    if (event.matches(StandardKey.Undo)) {
                        event.accepted = true; // security: no undo in a password field
                    }
                }

                Connections {
                    target: root
                    function onClearPassword() {
                        passwordBox.forceActiveFocus();
                        passwordBox.text = "";
                    }
                }
            }

            // Hairline underline — the ENTIRE visual chrome of the field.
            Rectangle {
                id: underline
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: underlineFlash.color
            }
            // separate object so the flash animation can retarget its color
            QtObject {
                id: underlineFlash
                property color color: lockScreenUi.atlasNavy400
            }

            // Focus-sweep: a short cyan sweep across the hairline on focus-in.
            Rectangle {
                id: focusSweep
                height: 1
                anchors.bottom: parent.bottom
                color: lockScreenUi.atlasCyan
                width: 0
                x: 0
                Behavior on width {
                    NumberAnimation { duration: lockScreenUi.atlasMotionFast; easing.type: Easing.OutCubic }
                }
            }
            Connections {
                target: passwordBox
                function onActiveFocusChanged() {
                    focusSweep.width = passwordBox.activeFocus ? passwordArea.width : 0;
                    underlineFlash.color = passwordBox.activeFocus ? lockScreenUi.atlasCyan : lockScreenUi.atlasNavy400;
                }
            }

            Text {
                anchors.top: underline.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    const parts = [];
                    if (capsLockState.locked) parts.push("Caps Lock is on");
                    if (root.notification) parts.push(root.notification);
                    return parts.join(" • ");
                }
                visible: text.length > 0
                color: lockScreenUi.atlasDim
                font.family: "Inter"
                font.pixelSize: 13
            }
        }
    }

    function startLogin() {
        authenticator.respond(passwordBox.text);
    }
}
