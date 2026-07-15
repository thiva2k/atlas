/*
    Atlas lock-screen HUD — entry point.

    Structure copied verbatim from the reference kscreenlocker greeter package
    (org.kde.plasma.desktop, contents/lockscreen/LockScreen.qml): kscreenlocker_greet
    loads exactly this file and expects the "magical" properties/signals below
    (viewVisible, clearPassword(), notificationRepeated(), notification) to exist
    on the root Item. Do not rename them.
*/
import QtQuick

Item {
    id: root
    property bool debug: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()

    // These are magical properties that kscreenlocker looks for.
    property bool viewVisible: false

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    implicitWidth: 800
    implicitHeight: 600

    LockScreenUi {
        anchors.fill: parent
    }
}
