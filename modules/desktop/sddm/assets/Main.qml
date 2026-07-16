// =============================================================================
//  ATLAS — SDDM greeter theme
//  B&W word-only identity (2026-07-16). See
//  docs/superpowers/specs/2026-07-16-atlas-bw-identity-design.md.
//
//  Design contract:
//    * Wires real auth: sddm.login(user, password, sessionIndex)
//    * Survives missing sddm / userModel / sessionModel (offline preview safe)
//    * Always renders a usable password field
//    * The functional path (focus/type/submit) is never gated by animation
//    * No bitmap assets, no SddmComponents, no X11 APIs, standard Qt6 imports
// =============================================================================

import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    width: 1920
    height: 1080
    focus: true
    color: "#070707"   // flat, matches boot; no competing texture

    // -------------------------------------------------------------------
    // Palette — black & white, one accent reserved for auth failure only.
    // (Fable spec 2026-07-16.)
    // -------------------------------------------------------------------
    readonly property color cBlock:        "#f2f2f2"   // masthead block glyphs
    readonly property color cShadow:       "#5a5a5a"   // masthead shadow glyphs
    readonly property color cField:        "#0e0e0e"
    readonly property color cBorderRest:   "#2e2e2e"
    readonly property color cBorderFocus:  "#8a8a8a"
    readonly property color cBorderPend:   "#f2f2f2"
    readonly property color cTextPrimary:  "#d6d6d6"
    readonly property color cTextSecond:   "#6a6a6a"
    readonly property color cHover:        "#f2f2f2"
    readonly property color cSessionHover: "#b8b8b8"
    readonly property color cError:        "#e5484d"

    readonly property string fMono: "JetBrainsMono Nerd Font Mono"

    readonly property string masthead:
        " █████╗ ████████╗██╗      █████╗ ███████╗\n" +
        "██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝\n" +
        "███████║   ██║   ██║     ███████║███████╗\n" +
        "██╔══██║   ██║   ██║     ██╔══██║╚════██║\n" +
        "██║  ██║   ██║   ███████╗██║  ██║███████║\n" +
        "╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝"

    // The masthead with every non-block glyph blanked to a space — the white
    // top layer of the two-tone lockup. Same monospace layout as the full
    // string, so it registers exactly over the grey shadow layer.
    function blocksOnly() {
        var s = ""
        for (var i = 0; i < masthead.length; i++) {
            var ch = masthead.charAt(i)
            s += (ch === "█" || ch === "\n") ? ch : " "
        }
        return s
    }

    // -------------------------------------------------------------------
    // Guarded greeter context — every global goes through these gates.
    // If plasmalogin/sddm fails to inject a context property, we degrade
    // to a still-rendering, still-typable form instead of a blank screen.
    // -------------------------------------------------------------------
    readonly property var g:        (typeof sddm         !== "undefined" && sddm)         ? sddm         : null
    readonly property var users:    (typeof userModel    !== "undefined" && userModel)    ? userModel    : null
    readonly property var sessions: (typeof sessionModel !== "undefined" && sessionModel) ? sessionModel : null

    property bool busy: false
    property string errorText: ""

    function initialUser() {
        // Prefer the last logged-in user...
        try {
            if (users && typeof users.lastUser === "string" && users.lastUser.length > 0)
                return users.lastUser
        } catch (e) {}
        // ...else fall back to the first real user in the model (fresh machine /
        // first-ever SDDM login, when no lastUser is recorded yet). NameRole =
        // Qt.UserRole + 1 in SDDM's UserModel.
        try {
            if (users && users.count > 0) {
                var n = users.data(users.index(0, 0), Qt.UserRole + 1)
                if (typeof n === "string" && n.length > 0)
                    return n
            }
        } catch (e) {}
        return ""
    }

    function initialSession() {
        try {
            if (sessions && sessions.lastIndex !== undefined && sessions.lastIndex >= 0)
                return sessions.lastIndex
        } catch (e) {}
        return 0
    }

    function submit() {
        if (busy)
            return
        var u = userField.currentText()
        if (u.length === 0) {
            errorText = "Enter a username"
            userField.startEdit()
            return
        }
        if (!g || typeof g.login !== "function") {
            errorText = "Sign-in unavailable"
            return
        }
        errorText = ""
        busy = true
        busyGuard.restart()
        var sess = (sessionCombo.count > 0) ? Math.max(0, sessionCombo.currentIndex) : 0
        try {
            g.login(u, passField.text, sess)
        } catch (e) {
            busy = false
            busyGuard.stop()
            errorText = "Sign-in failed to start"
        }
    }

    function loginFailedUi(msg) {
        busy = false
        busyGuard.stop()
        errorText = (msg && msg.length > 0) ? msg : "Incorrect password"
        passField.clear()
        triggerShake()
        passField.forceActiveFocus()
    }

    function triggerShake() {
        passWrap.shakeX = 14
        shakeSpring.restart()
    }

    Connections {
        target: root.g
        ignoreUnknownSignals: true
        function onLoginFailed() { root.loginFailedUi("") }
        function onLoginSucceeded() {
            root.busy = false
            busyGuard.stop()
            root.errorText = ""
        }
        function onInformationMessage(message) {
            root.errorText = String(message)
        }
    }

    // If the manager never answers (PAM hang, dropped signal), unfreeze the
    // form so the operator can retry instead of being soft-locked.
    Timer {
        id: busyGuard
        interval: 15000
        onTriggered: {
            if (root.busy) {
                root.busy = false
                root.errorText = "Taking longer than expected — try again"
                passField.forceActiveFocus()
            }
        }
    }

    // "Authenticating…" only appears if verification runs past 400ms —
    // the functional path stays silent and instant otherwise.
    Timer {
        id: authenticatingHint
        interval: 400
        onTriggered: authenticatingLabel.visible = root.busy
    }
    onBusyChanged: {
        if (busy) authenticatingHint.restart()
        else { authenticatingHint.stop(); authenticatingLabel.visible = false }
    }

    Component.onCompleted: {
        if (userField.currentText().length > 0)
            passField.forceActiveFocus()
        else
            userField.startEdit()
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
            root.errorText = ""
            event.accepted = true
        }
    }

    // -------------------------------------------------------------------
    // Wordmark — the ATLAS masthead, SOLID (not ghosted), identical glyphs
    // to boot: white blocks + grey shadow. It crowns the form as one lockup
    // (Fable spec): ~28px, ~690px wide ≈ 1.23x the form, top edge y=290. It
    // reads as identity through solidity + proportion, not size. Ambient
    // breath only, no drift — planted type reads premium.
    // -------------------------------------------------------------------
    Item {
        id: mastheadBox
        width: shadowLayer.implicitWidth
        height: shadowLayer.implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: 290 + riseOffset

        property real riseOffset: 12
        opacity: 0

        // Two-tone via two registered plain-text layers (RichText drops the
        // monospace font on box-drawing glyphs, so we avoid it): grey full
        // masthead underneath, white blocks-only on top. Identical monospace
        // layout => perfect glyph registration, matching the boot bake.
        Text {
            id: shadowLayer
            x: 0; y: 0
            text: root.masthead
            color: root.cShadow
            font.family: root.fMono
            font.pixelSize: 28
            lineHeight: 1.0
        }
        Text {
            id: blockLayer
            x: 0; y: 0
            text: root.blocksOnly()
            color: root.cBlock
            font.family: root.fMono
            font.pixelSize: 28
            lineHeight: 1.0
        }

        Component.onCompleted: mastheadEntrance.start()
        ParallelAnimation {
            id: mastheadEntrance
            NumberAnimation { target: mastheadBox; property: "opacity"; to: 1.0; duration: 450; easing.type: Easing.OutCubic }
            NumberAnimation { target: mastheadBox; property: "riseOffset"; to: 0; duration: 450; easing.type: Easing.OutCubic }
            onFinished: mastheadBreath.start()
        }

        // ambient breath: 1.00 <-> 0.90 over 7s, forever, only after entrance.
        SequentialAnimation {
            id: mastheadBreath
            loops: Animation.Infinite
            NumberAnimation { target: mastheadBox; property: "opacity"; from: 1.0; to: 0.90; duration: 7000; easing.type: Easing.InOutSine }
            NumberAnimation { target: mastheadBox; property: "opacity"; from: 0.90; to: 1.0; duration: 7000; easing.type: Easing.InOutSine }
        }
    }

    // -------------------------------------------------------------------
    // Form — a single centered 560px column. Entrance plays once (this is
    // the one place a login screen earns brief motion); the functional
    // path itself (focus/type/submit) has none.
    // -------------------------------------------------------------------
    Item {
        id: form
        width: 560
        anchors.horizontalCenter: parent.horizontalCenter
        y: 548
        height: formColumn.height

        Column {
            id: formColumn
            width: parent.width
            spacing: 16

            // "OPERATOR" label so the username line is never a mystery.
            Text {
                text: "OPERATOR"
                font.family: root.fMono
                font.pixelSize: 11
                font.letterSpacing: 11 * 0.18
                color: root.cTextSecond
            }

            Item {
                id: userField
                width: parent.width
                height: 26
                opacity: 0
                property real riseOffset: 8

                property string value: root.initialUser()
                property bool editing: false
                function currentText() { return value }
                function startEdit() { editing = true; editInput.text = value; editInput.forceActiveFocus(); editInput.selectAll() }
                function commitEdit() { value = editInput.text; editing = false }

                Text {
                    id: displayText
                    visible: !userField.editing
                    // real username, or a dim placeholder when none is set yet
                    text: userField.value.length > 0 ? userField.value : "username"
                    font.family: root.fMono
                    font.pixelSize: 18
                    color: userField.value.length > 0 ? root.cTextPrimary : root.cTextSecond
                    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: userField.startEdit() }
                }
                TextInput {
                    id: editInput
                    visible: userField.editing
                    width: parent.width
                    font.family: root.fMono
                    font.pixelSize: 18
                    color: root.cTextPrimary
                    selectionColor: root.cBorderFocus
                    onAccepted: { userField.commitEdit(); passField.forceActiveFocus() }
                    onActiveFocusChanged: if (!activeFocus) userField.commitEdit()
                }
                // thin underline, only while editing
                Rectangle {
                    visible: userField.editing
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: "#3a3a3a"
                }

                transform: Translate { y: userField.riseOffset }
                Component.onCompleted: entranceUser.start()
                ParallelAnimation {
                    id: entranceUser
                    NumberAnimation { target: userField; property: "opacity"; to: 1; duration: 350; easing.type: Easing.OutCubic }
                    NumberAnimation { target: userField; property: "riseOffset"; to: 0; duration: 350; easing.type: Easing.OutCubic }
                }
            }

            Item {
                id: passWrap
                width: parent.width
                height: 56
                opacity: 0
                property real riseOffset: 8
                transform: Translate { y: passWrap.riseOffset }

                Rectangle {
                    id: passBg
                    anchors.fill: parent
                    color: root.cField
                    radius: 8
                    border.width: 1
                    border.color: root.busy ? root.cBorderPend
                                : root.errorText.length > 0 ? root.cError
                                : passField.activeFocus ? root.cBorderFocus : root.cBorderRest
                    Behavior on border.color { ColorAnimation { duration: root.errorText.length > 0 ? 0 : 120; easing.type: Easing.OutQuad } }
                }

                property real shakeX: 0
                x: shakeX
                SpringAnimation {
                    id: shakeSpring
                    target: passWrap
                    property: "shakeX"
                    to: 0
                    spring: 4.5
                    damping: 0.15
                    mass: 1.0
                    running: false
                }

                TextInput {
                    id: passField
                    anchors.left: parent.left
                    anchors.right: submitGlyph.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 20
                    anchors.rightMargin: 8
                    font.family: root.fMono
                    font.pixelSize: 18
                    font.letterSpacing: 6
                    color: root.cTextPrimary
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    selectionColor: root.cBorderFocus
                    enabled: !root.busy
                    cursorVisible: false
                    clip: true

                    onAccepted: root.submit()
                    onTextChanged: if (root.errorText.length > 0) root.errorText = ""

                    Rectangle {
                        id: caret
                        width: 2
                        height: 20
                        color: root.cBlock
                        visible: passField.activeFocus && !root.busy
                        x: passField.cursorRectangle.x
                        y: (passField.height - height) / 2
                        // hard-step blink at 530ms — mirrors the boot cursor cadence
                        Timer {
                            interval: 530; running: caret.visible; repeat: true
                            onTriggered: caret.opacity = caret.opacity > 0 ? 0 : 1
                        }
                        onVisibleChanged: if (visible) opacity = 1
                        opacity: 1
                    }
                }

                Text {
                    id: submitGlyph
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 20
                    text: "→"
                    font.family: root.fMono
                    font.pixelSize: 20
                    color: root.cTextSecond
                    opacity: passField.text.length > 0 ? 1 : 0.4
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        enabled: passField.text.length > 0
                        onPressed: submitGlyph.scale = 0.97
                        onReleased: { submitGlyph.scale = 1.0; root.submit() }
                        onCanceled: submitGlyph.scale = 1.0
                    }
                }

                Component.onCompleted: entrancePass.start()
                SequentialAnimation {
                    id: entrancePass
                    PauseAnimation { duration: 120 }
                    ParallelAnimation {
                        NumberAnimation { target: passWrap; property: "opacity"; to: 1; duration: 350; easing.type: Easing.OutCubic }
                        NumberAnimation { target: passWrap; property: "riseOffset"; to: 0; duration: 350; easing.type: Easing.OutCubic }
                    }
                }
            }

            Text {
                id: authenticatingLabel
                visible: false
                text: "Authenticating…"
                font.family: root.fMono
                font.pixelSize: 13
                color: root.cTextSecond
            }

            Text {
                id: errorLabel
                visible: root.errorText.length > 0
                text: root.errorText
                font.family: root.fMono
                font.pixelSize: 13
                color: root.cError
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Item { width: 1; height: 4 }

            Row {
                id: sessionRow
                spacing: 10
                opacity: 0
                property real riseOffset: 8
                transform: Translate { y: sessionRow.riseOffset }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Session"
                    font.family: root.fMono
                    font.pixelSize: 13
                    color: root.cTextSecond
                }

                ComboBox {
                    id: sessionCombo
                    width: 240
                    height: 30
                    enabled: !root.busy
                    model: root.sessions ? root.sessions : []
                    textRole: "name"
                    displayText: count > 0 ? currentText : "Default"
                    font.family: root.fMono
                    font.pixelSize: 13
                    Component.onCompleted: {
                        var li = root.initialSession()
                        if (li >= 0 && li < count) currentIndex = li
                        else if (count > 0) currentIndex = 0
                    }
                    contentItem: Text {
                        leftPadding: 10
                        rightPadding: 22
                        font: sessionCombo.font
                        color: root.cTextPrimary
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: sessionCombo.displayText
                    }
                    indicator: Text {
                        x: sessionCombo.width - width - 10
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: root.fMono
                        font.pixelSize: 10
                        color: root.cTextSecond
                        text: "▾"
                    }
                    background: Rectangle {
                        color: "transparent"
                        border.width: 1
                        border.color: sessionCombo.activeFocus ? root.cBorderFocus : root.cBorderRest
                        radius: 4
                    }
                    delegate: ItemDelegate {
                        id: sessDelegate
                        width: sessionCombo.width
                        highlighted: sessionCombo.highlightedIndex === index
                        contentItem: Text {
                            font.family: root.fMono
                            font.pixelSize: 13
                            color: sessDelegate.highlighted ? root.cHover : root.cTextPrimary
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 10
                            text: (model.name !== undefined) ? model.name : ""
                        }
                        background: Rectangle { color: sessDelegate.highlighted ? "#1c1c1c" : "transparent" }
                    }
                    popup: Popup {
                        y: sessionCombo.height + 4
                        width: sessionCombo.width
                        padding: 1
                        implicitHeight: Math.min(contentItem.implicitHeight + 2, 200)
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: sessionCombo.popup.visible ? sessionCombo.delegateModel : null
                            currentIndex: sessionCombo.highlightedIndex
                        }
                        background: Rectangle { color: "#0c0c0c"; border.width: 1; border.color: root.cBorderRest; radius: 4 }
                    }
                }

                Component.onCompleted: entranceSession.start()
                SequentialAnimation {
                    id: entranceSession
                    PauseAnimation { duration: 240 }
                    ParallelAnimation {
                        NumberAnimation { target: sessionRow; property: "opacity"; to: 1; duration: 350; easing.type: Easing.OutCubic }
                        NumberAnimation { target: sessionRow; property: "riseOffset"; to: 0; duration: 350; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------
    // Power row — text only, bottom-right. No icons, no boxes.
    // -------------------------------------------------------------------
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 40
        anchors.bottomMargin: 36
        spacing: 32

        Repeater {
            model: [
                { label: "Sleep",      visible: true,                         action: function() {} },
                { label: "Restart",    visible: root.g !== null && root.g.canReboot === true,   action: function() { if (root.g) root.g.reboot() } },
                { label: "Shut Down",  visible: root.g !== null && root.g.canPowerOff === true,  action: function() { if (root.g) root.g.powerOff() } }
            ]
            delegate: Text {
                visible: modelData.visible
                text: modelData.label
                font.family: root.fMono
                font.pixelSize: 13
                color: powerArea.containsMouse ? root.cHover : root.cTextSecond
                property real pressScale: 1.0
                scale: pressScale
                MouseArea {
                    id: powerArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    onPressed: parent.pressScale = 0.97
                    onReleased: parent.pressScale = 1.0
                    onCanceled: parent.pressScale = 1.0
                    onClicked: modelData.action()
                }
            }
        }
    }
}
