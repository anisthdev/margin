import QtQuick
import ".."

// Material 3 extended FAB: an icon and a label on primary_container, 56
// tall with 16 corners. With `expanded` off it folds to the icon alone, as
// M3's does while the content under it scrolls.
Rectangle {
    id: root

    property string icon
    property string text
    property bool expanded: true

    signal clicked

    implicitWidth: expanded ? 16 + 24 + 12 + label.implicitWidth + 20 : 56
    implicitHeight: 56
    radius: 16
    color: Theme.primary_container
    clip: true

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emphasizedDecel
        }
    }

    // A soft shadow, as the FAB's level 3 elevation
    Rectangle {
        z: -1
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: -3
        radius: parent.radius
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    // State layer
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.on_primary_container
        opacity: mouse.pressed ? 0.12 : mouse.containsMouse ? 0.08 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }
    }

    Icon {
        x: 16
        name: root.icon
        size: 24
        color: Theme.on_primary_container
    }

    Label {
        id: label

        x: 16 + 24 + 12
        text: root.text
        color: Theme.on_primary_container
        font.pixelSize: 15
        font.weight: Font.DemiBold
        opacity: root.expanded ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
