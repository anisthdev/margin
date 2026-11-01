import QtQuick
import ".."
import "../components"

// Keep's side menu: Notes, each label, Archive and Trash. The one on show
// is filled; Tab and Shift+Tab on the grid step through them.
Flickable {
    id: root

    // Each a { view, label, icon, text }
    readonly property var entries: [
        {
            view: "notes",
            label: "",
            icon: "lightbulb",
            text: "Notes"
        }
    ].concat(Notes.labels.map(l => ({
                view: "notes",
                label: l.name,
                icon: "label",
                text: l.name,
                count: l.count
            }))).concat([
        {
            view: "archive",
            label: "",
            icon: "archive",
            text: "Archive"
        },
        {
            view: "trash",
            label: "",
            icon: "delete",
            text: "Trash"
        }
    ])
    readonly property int currentIndex: Math.max(0, entries.findIndex(e => e.view === Notes.view && e.label === Notes.label))

    // The entry `step` away from the one on show, round the ends
    function step(step) {
        const e = entries[(currentIndex + step + entries.length) % entries.length];
        Notes.show(e.view, e.label);
    }

    contentHeight: column.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
        id: column

        width: root.width
        spacing: 2

        Repeater {
            model: root.entries

            Rectangle {
                id: entry

                required property var modelData
                required property int index
                readonly property bool current: index === root.currentIndex

                width: parent.width
                height: 48
                radius: height / 2
                color: current ? Theme.secondary_container : hover.containsMouse ? Qt.alpha(Theme.on_surface, 0.06) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animFast
                    }
                }

                Icon {
                    x: 20
                    name: entry.modelData.icon
                    size: 20
                    color: entry.current ? Theme.on_secondary_container : Theme.on_surface_variant
                }

                Label {
                    x: 60
                    width: parent.width - 60 - count.width - 24
                    text: entry.modelData.text
                    color: entry.current ? Theme.on_secondary_container : Theme.on_surface
                    font.weight: entry.current ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                }

                Label {
                    id: count

                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    text: entry.modelData.count ?? ""
                    color: entry.current ? Theme.on_secondary_container : Theme.on_surface_variant
                    font.pixelSize: 12
                }

                MouseArea {
                    id: hover

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notes.show(entry.modelData.view, entry.modelData.label)
                }
            }
        }
    }
}
