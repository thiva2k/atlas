/*
    Atlas lock-screen HUD — main UI. B&W word-only identity (2026-07-16),
    the same lockup as the SDDM login (docs/superpowers/specs/2026-07-16-
    atlas-bw-identity-design.md): the ATLAS masthead crowning a clock and a
    single password field, on flat near-black. Lock is even more restrained
    than login (Fable spec): NO entrance animation (it is seen many times a
    day), a large clock as the focal element, password only — no username or
    session — and an idle-settle after 20s untouched.

    AUTH WIRING (do not change the shape of this): copied structurally from the
    reference kscreenlocker greeter package shipped with this system —
    /usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml
    and MainBlock.qml. kscreenlocker_greet injects a context property named
    `authenticator` (org.kde.kscreenlocker's ScreenLocker.Authenticator) and a
    root Item (see LockScreen.qml) with clearPassword()/notification/viewVisible.
    The unlock call is `authenticator.respond(password)` — NOT `tryUnlock()`, and
    the listened signals are `authenticator.succeeded`/`failed`/
    `infoMessageChanged`/`errorMessageChanged`/`promptChanged`/
    `promptForSecretChanged`, wired via a single Connections{ target: authenticator }
    block exactly like the reference. On success with a prompt, the reference calls
    Qt.quit() to let kscreenlocker tear the greeter down; that call is preserved.
*/
import QtQml
import QtQuick
import QtQuick.Controls as QQC2

import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.plasma.private.sessions
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // --- Atlas B&W palette (Fable spec 2026-07-16) -----------------------------
    readonly property color cBg:          "#070707"
    readonly property color cBlock:       "#f2f2f2"   // masthead block glyphs
    readonly property color cShadow:      "#5a5a5a"   // masthead shadow glyphs
    readonly property color cField:       "#0e0e0e"
    readonly property color cBorderRest:  "#2e2e2e"
    readonly property color cBorderFocus: "#8a8a8a"
    readonly property color cTextPrimary: "#d6d6d6"
    readonly property color cTextSecond:  "#6a6a6a"
    readonly property color cClock:       "#e8e8e8"
    readonly property color cError:       "#e5484d"

    readonly property string fMono: "JetBrainsMono Nerd Font Mono"
    readonly property string fClock: "JetBrainsMono Nerd Font"

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

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

    // Time source for the clock (plain Date, refreshed by a timer — no
    // external clock module that could fail to import).
    property var now: new Date()
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: lockScreenUi.now = new Date()
    }

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
            lockScreenUi.handleMessage("Unlocking failed");
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            wrongPasswordShake.restart();
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
        onPositionChanged: idleSettle.wake()
        onClicked: idleSettle.wake()

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

        // --- Flat near-black ground ---------------------------------------------
        Rectangle {
            anchors.fill: parent
            color: lockScreenUi.cBg
        }

        // --- Idle-settle: after 20s untouched, dim the interactive lockup to
        // 25% (clock stays); any input restores instantly and the keystroke
        // still lands (restraint never taxes input). -----------------------------
        Item {
            id: idleSettle
            property bool settled: false
            function wake() {
                settled = false
                idleTimer.restart()
            }
            Timer { id: idleTimer; interval: 20000; running: true; onTriggered: idleSettle.settled = true }
        }

        // --- The lockup: ATLAS masthead, clock, password ------------------------
        Item {
            id: interactiveLockup
            anchors.fill: parent
            opacity: idleSettle.settled ? 0.25 : 1.0
            Behavior on opacity { NumberAnimation { duration: idleSettle.settled ? 600 : 0; easing.type: Easing.OutQuad } }

            // ATLAS wordmark — two-tone (white blocks + grey shadow), same as login.
            Item {
                id: mastheadBox
                width: mShadow.implicitWidth
                height: mShadow.implicitHeight
                anchors.horizontalCenter: parent.horizontalCenter
                y: 150
                Text {
                    id: mShadow
                    x: 0; y: 0
                    text: lockScreenUi.masthead
                    color: lockScreenUi.cShadow
                    font.family: lockScreenUi.fMono
                    font.pixelSize: 26
                    lineHeight: 1.0
                }
                Text {
                    x: 0; y: 0
                    text: lockScreenUi.blocksOnly()
                    color: lockScreenUi.cBlock
                    font.family: lockScreenUi.fMono
                    font.pixelSize: 26
                    lineHeight: 1.0
                }
            }

            // Clock — the lock screen's focal element. Time comes from plain
            // JS Date (no clock-module import that could fail to resolve and
            // silently drop the whole theme); a Timer refreshes it.
            Text {
                id: clockLabel
                anchors.horizontalCenter: parent.horizontalCenter
                y: 430
                text: Qt.formatTime(lockScreenUi.now, "hh:mm")
                color: lockScreenUi.cClock
                font.family: lockScreenUi.fClock
                font.weight: Font.ExtraLight
                font.pixelSize: 128
                font.letterSpacing: -2.6
                renderType: Text.NativeRendering
                font.features: ({ "tnum": 1 })   // tabular figures: clock never jitters
            }

            Text {
                id: dateLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: clockLabel.bottom
                anchors.topMargin: 8
                text: Qt.formatDate(lockScreenUi.now, "dddd, d MMMM").toUpperCase()
                color: lockScreenUi.cTextSecond
                font.family: lockScreenUi.fMono
                font.pixelSize: 14
                font.letterSpacing: 3
            }

            // --- Password field: bordered box, matching login -------------------
            Item {
                id: passWrap
                width: 480
                height: 56
                anchors.horizontalCenter: parent.horizontalCenter
                y: 660

                property real shakeX: 0
                x: shakeX
                SpringAnimation {
                    id: wrongPasswordShake
                    target: passWrap
                    property: "shakeX"
                    to: 0
                    spring: 4.5
                    damping: 0.15
                    mass: 1.0
                    running: false
                    function restart() { passWrap.shakeX = 14; wrongPasswordShake.running = true }
                }

                Rectangle {
                    anchors.fill: parent
                    color: lockScreenUi.cField
                    radius: 8
                    border.width: 1
                    border.color: root.notification.length > 0 ? lockScreenUi.cError
                                : passwordBox.activeFocus ? lockScreenUi.cBorderFocus : lockScreenUi.cBorderRest
                    Behavior on border.color { ColorAnimation { duration: root.notification.length > 0 ? 0 : 120 } }
                }

                QQC2.TextField {
                    id: passwordBox
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    leftPadding: 0
                    rightPadding: 0
                    background: Item {}   // no frame; the wrapper Rectangle IS the chrome
                    color: lockScreenUi.cTextPrimary
                    font.family: lockScreenUi.fMono
                    font.pixelSize: 18
                    font.letterSpacing: 6
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    placeholderText: "Password"
                    placeholderTextColor: lockScreenUi.cTextSecond
                    selectionColor: lockScreenUi.cBorderFocus
                    cursorVisible: activeFocus
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                    enabled: !authenticator.graceLocked
                    focus: true

                    onAccepted: lockScreenUi.startLogin()
                    onTextChanged: idleSettle.wake()

                    Keys.onPressed: event => {
                        idleSettle.wake();
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
            }

            // Caps-lock + failure messaging, below the field.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: passWrap.bottom
                anchors.topMargin: 14
                horizontalAlignment: Text.AlignHCenter
                text: {
                    const parts = [];
                    if (capsLockState.locked) parts.push("Caps Lock is on");
                    if (root.notification) parts.push(root.notification);
                    return parts.join("  •  ");
                }
                visible: text.length > 0
                color: root.notification.length > 0 ? lockScreenUi.cError : lockScreenUi.cTextSecond
                font.family: lockScreenUi.fMono
                font.pixelSize: 13
            }
        }
    }

    function startLogin() {
        authenticator.respond(passwordBox.text);
    }
}
