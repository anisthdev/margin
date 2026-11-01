import QtQuick
import ".."

// Copied from Seedling (f49a017).
// Material 3 standard icon button: one of our icons with a circular state
// layer on hover and press.
Item {
    id: root

    property string icon
    property real iconSize: 14
    property real iconRotation: 0
    property color color: Theme.on_surface

    signal clicked

    implicitWidth: 32
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.color
        opacity: mouse.pressed ? 0.16 : mouse.containsMouse ? 0.08 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.iconSize
        rotation: root.iconRotation
        color: root.color
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
