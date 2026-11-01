import QtQuick
import ".."

// A note's colour: Keep's twelve as swatches in a card over a scrim. h/l
// (or the arrows, Tab) move, Enter or Space picks, a number picks directly
// (0 the default), Esc or q cancels. It takes the keyboard while open.
Item {
    id: root

    property bool open: false
    property int index: 0
    property var done: null

    signal finished

    // Asks for a colour, starting at `current`; `picked` gets the name
    function ask(current, picked) {
        index = Math.max(0, NoteColors.names.indexOf(current));
        done = picked;
        open = true;
        keys.forceActiveFocus();
    }

    function close(name) {
        open = false;
        const action = done;
        done = null;
        if (name !== undefined && action)
            action(name);
        finished();
    }

    anchors.fill: parent
    visible: open || scrim.opacity > 0

    Item {
        id: keys

        Keys.onPressed: event => {
            event.accepted = true;
            const count = NoteColors.names.length;
            if (event.text === "h" || event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)
                root.index = (root.index + count - 1) % count;
            else if (event.text === "l" || event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
                root.index = (root.index + 1) % count;
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                root.close(NoteColors.names[root.index]);
            else if (/^[0-9]$/.test(event.text))
                root.close(NoteColors.names[parseInt(event.text)]);
            else if (event.key === Qt.Key_Escape || event.text === "q")
                root.close();
        }
    }

    Rectangle {
        id: scrim

        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: content.implicitWidth + 48
        height: content.implicitHeight + 48
        radius: 28
        color: Theme.surface_container_high
        opacity: scrim.opacity
        scale: 0.94 + 0.06 * scrim.opacity

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content

            anchors.centerIn: parent
            spacing: 16

            Label {
                anchors.verticalCenter: undefined
                text: "Colour"
                color: Theme.on_surface
                font.pixelSize: 24
                font.weight: Font.Normal
                roundness: Theme.titleRoundness
            }

            Row {
                spacing: 10

                Repeater {
                    model: NoteColors.names

                    Item {
                        id: swatch

                        required property string modelData
                        required property int index
                        readonly property bool current: index === root.index

                        width: 40
                        height: 40

                        Rectangle {
                            anchors.centerIn: parent
                            width: swatch.current ? 40 : 34
                            height: width
                            radius: width / 2
                            color: NoteColors.fill(swatch.modelData)
                            border.width: swatch.current ? 2 : swatch.modelData === "" ? 1 : 0
                            border.color: swatch.current ? Theme.primary : Theme.outline

                            Behavior on width {
                                NumberAnimation {
                                    duration: Theme.animFast
                                }
                            }
                        }

                        Icon {
                            anchors.centerIn: parent
                            visible: swatch.modelData === ""
                            name: "format_color_reset"
                            size: 18
                            color: Theme.on_surface_variant
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.index = swatch.index
                            onClicked: root.close(swatch.modelData)
                        }
                    }
                }
            }

            Label {
                anchors.verticalCenter: undefined
                text: NoteColors.titles[NoteColors.names[root.index]] + (root.index < 10 ? `  ·  ${root.index}` : "")
                color: Theme.on_surface_variant
                font.weight: Font.Normal
            }
        }
    }
}
