import QtQuick
import QtQuick.Effects
import ".."

// Copied from Seedling (f49a017).
// A white SVG from icons/ (or any image, given an absolute path as `name`)
// tinted to any colour. Colourising keeps the icon's own alpha, so partly
// transparent parts (like the unlit bars of the Wi-Fi icon) stay dimmed.
// Icons keep their aspect ratio; `size` is the height.
Item {
    id: root

    property string name
    property color color: Theme.on_surface
    property real size: 18

    implicitWidth: Math.ceil(image.implicitWidth)
    implicitHeight: size
    anchors.verticalCenter: parent?.verticalCenter

    Image {
        id: image

        anchors.verticalCenter: parent.verticalCenter
        source: !root.name ? "" : root.name.startsWith("/") ? `file://${root.name}` : Qt.resolvedUrl(`../icons/${root.name}.svg`)
        sourceSize.height: Math.ceil(root.size)
        smooth: true
        opacity: root.color.a
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 1)

            Behavior on colorizationColor {
                ColorAnimation {
                    duration: Theme.animNormal
                }
            }
        }
    }
}
