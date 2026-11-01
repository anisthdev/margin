import QtQuick
import ".."

// Copied from Seedling (f49a017).
// A Material snackbar at the bottom: a short message that goes away by
// itself after a few seconds.
Rectangle {
    id: root

    function show(message) {
        label.text = message;
        shown = true;
        hideTimer.restart();
    }

    property bool shown: false

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: shown ? 24 : -height
    width: Math.min(parent.width - 48, label.implicitWidth + 32)
    height: label.implicitHeight + 28
    radius: Theme.radius
    color: Theme.inverse_surface
    opacity: shown ? 1 : 0

    Behavior on anchors.bottomMargin {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emphasizedDecel
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Theme.animFast
        }
    }

    Label {
        id: label

        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.parent.width - 80)
        color: Theme.inverse_on_surface
        font.weight: Font.Normal
        elide: Text.ElideMiddle
    }

    Timer {
        id: hideTimer

        interval: 4000
        onTriggered: root.shown = false
    }
}
