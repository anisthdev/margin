import QtQuick
import ".."

// A note's labels, as Keep's "Label note": a field filtering every label in
// use, each with a box showing whether the note has it, and a row to make
// the typed one when there's no such label. Up/Down (Ctrl+j/k, Tab) move,
// Enter ticks or unticks the current row (or makes the label), Esc closes.
// Each change goes to `changed` straight away. It takes the keyboard while
// open.
Item {
    id: root

    property bool open: false
    // The note's labels, as they stand
    property var picked: []
    property var onChange: null
    property int index: 0

    signal finished

    readonly property string typed: field.text.trim()
    readonly property var rows: {
        const all = Notes.labels.map(l => l.name);
        for (const l of picked)
            if (!all.some(a => a.toLowerCase() === l.toLowerCase()))
                all.push(l);
        const q = typed.toLowerCase();
        const out = all.filter(l => l.toLowerCase().includes(q)).map(l => ({
                    name: l,
                    create: false
                }));
        if (typed !== "" && !all.some(l => l.toLowerCase() === q))
            out.push({
                name: typed,
                create: true
            });
        return out;
    }

    // Shows the labels of a note that has `labels`; `changed` gets the new
    // list on each tick
    function ask(labels, changed) {
        picked = labels.slice();
        onChange = changed;
        field.text = "";
        index = 0;
        open = true;
        field.forceActiveFocus();
    }

    function close() {
        open = false;
        onChange = null;
        finished();
    }

    function has(name) {
        return picked.some(l => l.toLowerCase() === name.toLowerCase());
    }

    function toggle(row) {
        if (!row)
            return;
        picked = has(row.name) ? picked.filter(l => l.toLowerCase() !== row.name.toLowerCase()) : picked.concat([row.name]);
        if (row.create)
            field.text = "";
        onChange?.(picked);
    }

    onRowsChanged: index = Math.min(index, Math.max(0, rows.length - 1))

    anchors.fill: parent
    visible: open || scrim.opacity > 0

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
        width: 340
        height: Math.min(parent.height - 48, content.implicitHeight + 40)
        radius: 28
        color: Theme.surface_container_high
        opacity: scrim.opacity
        scale: 0.94 + 0.06 * scrim.opacity
        clip: true

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content

            x: 20
            y: 20
            width: parent.width - 40
            spacing: 12

            Label {
                anchors.verticalCenter: undefined
                leftPadding: 4
                text: "Labels"
                color: Theme.on_surface
                font.pixelSize: 24
                font.weight: Font.Normal
                roundness: Theme.titleRoundness
            }

            Rectangle {
                width: parent.width
                height: 44
                radius: Theme.radius
                color: Theme.surface_container_highest

                Icon {
                    x: 14
                    name: "search"
                    size: 18
                    color: Theme.on_surface_variant
                }

                TextInput {
                    id: field

                    anchors.left: parent.left
                    anchors.leftMargin: 42
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    clip: true
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N)) {
                            root.index = Math.min(root.rows.length - 1, root.index + 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P)) {
                            root.index = Math.max(0, root.index - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.toggle(root.rows[root.index]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        }
                    }

                    Label {
                        anchors.verticalCenter: undefined
                        visible: field.text === ""
                        text: "Find or make a label"
                        color: Theme.on_surface_variant
                        font: field.font
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.rows

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool current: index === root.index

                        width: parent.width
                        height: 40
                        radius: 10
                        color: current ? Theme.secondary_container : "transparent"

                        Icon {
                            x: 12
                            name: row.modelData.create ? "add" : root.has(row.modelData.name) ? "check_box" : "check_box_outline_blank"
                            size: 18
                            color: row.current ? Theme.on_secondary_container : Theme.on_surface_variant
                        }

                        Label {
                            x: 42
                            width: parent.width - 54
                            text: row.modelData.create ? `Make “${row.modelData.name}”` : row.modelData.name
                            color: row.current ? Theme.on_secondary_container : Theme.on_surface
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.index = row.index
                            onClicked: root.toggle(row.modelData)
                        }
                    }
                }
            }

            Label {
                anchors.verticalCenter: undefined
                leftPadding: 4
                visible: root.rows.length === 0
                text: "No labels yet: type one to make it"
                color: Theme.on_surface_variant
                font.weight: Font.Normal
            }
        }
    }
}
