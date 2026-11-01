import Quickshell.Widgets
import QtQuick
import ".."

// A note's picture, cropped to its box with rounded corners. `aspect` is
// the picture's own height over its width once loaded, for a box to take
// its shape.
ClippingRectangle {
    id: root

    property string path
    readonly property real aspect: image.implicitWidth > 0 ? image.implicitHeight / image.implicitWidth : 0.6
    readonly property bool ready: image.status === Image.Ready

    radius: 12
    color: Qt.alpha(Theme.on_surface, 0.06)

    Image {
        id: image

        anchors.fill: parent
        source: root.path ? `file://${root.path}` : ""
        sourceSize.width: Math.ceil(root.width * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: root.ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }
    }
}
