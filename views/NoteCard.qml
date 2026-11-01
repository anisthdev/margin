import QtQuick
import ".."
import "../components"

// One note in the grid, as Keep's cards: its pictures across the top, its
// title, its body (long ones cut off with a fade), its labels as chips. The keyboard's current card is
// lifted a little and lightened, rather than ringed.
Rectangle {
    id: root

    required property var note
    property bool current: false
    // Set by the grid's layout pass
    property int column: 0

    signal clicked
    signal opened
    signal toggled(string body)

    readonly property bool empty: note.title === "" && note.body.trim() === "" && note.images.length === 0
    readonly property bool textless: note.title === "" && note.body.trim() === "" && note.labels.length === 0

    height: (pictures.visible ? pictures.height + 6 : 0) + (textless && pictures.visible ? 6 : content.height + 32)
    radius: Theme.cardRadius
    color: NoteColors.fill(note.color)
    border.width: note.color === "" ? 1 : 0
    border.color: Theme.outline_variant
    scale: current ? 1.02 : 1
    z: current ? 1 : 0

    Behavior on x {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emphasizedDecel
        }
    }
    Behavior on y {
        NumberAnimation {
            duration: Theme.animNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emphasizedDecel
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: Theme.animFast
        }
    }
    Behavior on color {
        ColorAnimation {
            duration: Theme.animNormal
        }
    }

    // State layer: hover, and the keyboard's current card
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.on_surface
        opacity: root.current ? 0.1 : mouse.containsMouse ? 0.05 : 0

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
        onDoubleClicked: root.opened()
    }

    Icon {
        anchors.verticalCenter: undefined
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 17
        visible: root.note.pinned
        name: "keep"
        size: 16
        color: Theme.on_surface_variant
    }

    // The first picture as it is (up to a height), the rest in a row of
    // squares under it, as Keep's cards
    Column {
        id: pictures

        readonly property var images: root.note.images
        readonly property real rest: images.length - 1

        x: 6
        y: 6
        width: parent.width - 12
        spacing: 4
        visible: images.length > 0

        Picture {
            id: first

            width: parent.width
            height: Math.min(260, width * aspect)
            path: pictures.images[0]?.path ?? ""
        }

        Row {
            spacing: 4
            visible: pictures.rest > 0

            Repeater {
                model: pictures.images.slice(1, 4)

                Picture {
                    required property var modelData

                    width: (pictures.width - 8) / 3
                    height: width
                    path: modelData.path
                }
            }
        }
    }

    Label {
        anchors.verticalCenter: undefined
        anchors.right: pictures.right
        anchors.rightMargin: 10
        anchors.bottom: pictures.bottom
        anchors.bottomMargin: 8
        visible: pictures.images.length > 4
        text: `+${pictures.images.length - 4}`
        color: "white"
        font.pixelSize: 13
        font.weight: Font.DemiBold
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.5)
    }

    Column {
        id: content

        x: 16
        y: pictures.visible ? pictures.height + 6 + 12 : 16
        visible: !(root.textless && pictures.visible)
        width: parent.width - 32
        spacing: 10

        Item {
            width: parent.width
            height: title.implicitHeight
            visible: root.note.title !== ""

            Label {
                id: title

                anchors.verticalCenter: undefined
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: root.note.pinned ? 22 : 0
                text: root.note.title
                color: Theme.on_surface
                font.pixelSize: 16
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

        }

        // The body, cut off past maxHeight with a fade into the card
        Item {
            readonly property real maxHeight: 300

            width: parent.width
            height: Math.min(body.implicitHeight, maxHeight)
            visible: root.note.body.trim() !== ""
            clip: true

            NoteBody {
                id: body

                // Clear of the pin when there's no title to sit beside it
                width: parent.width - (root.note.pinned && root.note.title === "" ? 22 : 0)
                body: root.note.body
                interactive: !root.note.trashed
                onToggled: text => root.toggled(text)
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 40
                visible: body.implicitHeight > parent.maxHeight
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.alpha(root.color, 0)
                    }
                    GradientStop {
                        position: 1
                        color: root.color
                    }
                }
            }
        }

        Label {
            anchors.verticalCenter: undefined
            visible: root.empty
            text: "Empty note"
            color: Theme.on_surface_variant
            font.pixelSize: 16
            font.weight: Font.Normal
        }

        Flow {
            width: parent.width
            spacing: 6
            visible: root.note.labels.length > 0

            Repeater {
                model: root.note.labels

                Chip {
                    required property string modelData

                    text: modelData
                }
            }
        }
    }
}
