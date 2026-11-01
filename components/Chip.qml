import QtQuick
import ".."

// A note's label as a small pill, as Keep shows them on cards. With
// `removable`, an × to take it off.
Rectangle {
    id: root

    property string text
    property bool removable: false

    signal removed

    implicitWidth: label.implicitWidth + (removable ? 36 : 20)
    implicitHeight: 24
    radius: height / 2
    color: Qt.alpha(Theme.on_surface, 0.08)

    Label {
        id: label

        x: 10
        text: root.text
        color: Theme.on_surface
        font.pixelSize: 12
    }

    Icon {
        anchors.right: parent.right
        anchors.rightMargin: 6
        visible: root.removable
        name: "close"
        size: 12
        color: Theme.on_surface_variant

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removed()
        }
    }
}
