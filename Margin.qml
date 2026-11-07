import Quickshell
import QtQuick
import "components"
import "views"

// margin's window: an ordinary one, tiled or floated like any other app,
// in the shell's look. The side menu (Notes, labels, Archive, Trash), a
// search field, and the notes as cards; a note opens over them to edit.
//
// Keys, vim style, on the grid: h/j/k/l (or the arrows) move, gg/G go to
// the first and last, Enter/o/e open, n makes a note, / searches, p pins, c
// colours, L labels, a archives (or unarchives), d/Delete trashes, u undoes
// the last archive or trash, Tab/Shift+Tab step through the side menu, ?
// shows every key, q/Ctrl+w closes the window. In the trash: r restores, D
// deletes for good, E empties it. Esc clears the search, then goes back to
// Notes. See views/Editor.qml for the editor's keys.
FloatingWindow {
    id: root

    property string pending: ""
    // The last archive or trash, for u: a function putting it back
    property var undo: null

    readonly property var grid: noteGrid
    readonly property var note: noteGrid.current
    readonly property bool inTrash: Notes.view === "trash"

    readonly property var bindings: [["h j k l, arrows", "Move between notes"], ["gg  G", "First and last note"], ["Enter  o  e", "Open the note"], ["n", "New note"], ["/", "Search (Enter or ↓ back to the notes, Esc clears)"], ["p", "Pin or unpin"], ["c", "Colour"], ["L", "Labels"], ["a", "Archive or unarchive"], ["d  Delete", "Move to the trash"], ["u", "Undo the last archive or trash"], ["r  D  E", "In the trash: restore, delete for good, empty it"], ["Tab  Shift+Tab", "Next and previous in the side menu"], ["Esc", "Clear the search, then back to Notes"], ["q  Ctrl+w", "Close the window"], ["Editor: Alt+p c l a d", "Pin, colour, labels, archive, trash"], ["Editor: Ctrl+L", "Add or take off a line's checkbox"], ["Editor: Ctrl+Enter", "Tick or untick the line"], ["Editor", "A note opens to read: p c L a d act on it, i or Enter type, Esc stops typing, then closes (it saves itself)"]]

    function focusGrid() {
        if (editor.open)
            editor.refocus();
        else
            keys.forceActiveFocus();
    }

    function newNote() {
        if (inTrash)
            Notes.show("notes", "");
        editor.showNew(Notes.label ? [Notes.label] : []);
    }

    function openNote(n) {
        if (n) {
            grid.select(n.id);
            editor.show(n);
        }
    }

    function togglePin(n) {
        if (n && !n.trashed)
            Notes.update(n.id, {
                pinned: !n.pinned
            });
    }

    function archive(n) {
        if (!n || n.trashed)
            return;
        const to = !n.archived;
        Notes.update(n.id, {
            archived: to
        });
        archived(n.id, to, n.pinned);
    }

    // After a note was archived or unarchived, here or in the editor
    function archived(id, to, wasPinned) {
        undo = () => Notes.update(id, {
                archived: !to,
                pinned: wasPinned
            });
        snackbar.show(to ? "Note archived  ·  u to undo" : "Note unarchived  ·  u to undo");
    }

    function trash(id) {
        // The trash unpins; undoing pins it again
        const pinned = Notes.notes.find(n => n.id === id)?.pinned ?? false;
        Notes.trash(id);
        undo = () => Notes.restore(id, () => {
                if (pinned)
                    Notes.update(id, {
                        pinned: true
                    });
            });
        snackbar.show("Note moved to the trash  ·  u to undo");
    }

    function restore(n) {
        if (!n?.trashed)
            return;
        Notes.restore(n.id);
        undo = () => Notes.trash(n.id);
        snackbar.show("Note restored  ·  u to undo");
    }

    function pickColor(n) {
        if (!n || n.trashed)
            return;
        colorPicker.ask(n.color, c => Notes.update(n.id, {
                color: c
            }));
    }

    function pickLabels(n) {
        if (!n || n.trashed)
            return;
        labelPicker.ask(n.labels, labels => Notes.update(n.id, {
                labels: labels
            }));
    }

    function handleKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const t = event.text;
        const was = pending;
        pending = "";
        if (ctrl && event.key === Qt.Key_W)
            root.visible = false;
        else if (ctrl && event.key === Qt.Key_D)
            grid.contentY = Math.min(Math.max(0, grid.contentHeight - grid.height), grid.contentY + grid.height / 2);
        else if (ctrl && event.key === Qt.Key_U)
            grid.contentY = Math.max(0, grid.contentY - grid.height / 2);
        else if (ctrl)
            return false;
        else if (t === "j" || event.key === Qt.Key_Down)
            grid.move("down");
        else if (t === "k" || event.key === Qt.Key_Up)
            grid.move("up");
        else if (t === "h" || event.key === Qt.Key_Left)
            grid.move("left");
        else if (t === "l" || event.key === Qt.Key_Right)
            grid.move("right");
        else if (t === "g" && was === "g")
            grid.first();
        else if (t === "g")
            pending = "g";
        else if (t === "G")
            grid.last();
        else if (t === "o" || t === "e" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            openNote(note);
        else if (t === "n")
            newNote();
        else if (t === "/" || t === "i")
            search.forceActiveFocus();
        else if (t === "p")
            togglePin(note);
        else if (t === "c")
            pickColor(note);
        else if (t === "L")
            pickLabels(note);
        else if (t === "a")
            archive(note);
        else if ((t === "d" || event.key === Qt.Key_Delete) && note && !note.trashed)
            trash(note.id);
        else if (t === "u" && undo) {
            undo();
            undo = null;
            snackbar.show("Undone");
        } else if (t === "r" && inTrash)
            restore(note);
        else if (t === "D" && inTrash && note) {
            const id = note.id;
            confirm.ask("Delete this note?", "It goes for good: it can't be restored.", "Delete", () => Notes.remove(id));
        } else if (t === "E" && inTrash && Notes.notes.length > 0)
            emptyTrash();
        // Shift+Tab comes as Backtab, or as Tab with Shift held
        else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))
            sidebar.step(-1);
        else if (event.key === Qt.Key_Tab)
            sidebar.step(1);
        else if (t === "?" || event.key === Qt.Key_F1)
            help.open = true;
        else if (t === "q")
            root.visible = false;
        else if (event.key === Qt.Key_Escape) {
            if (search.text !== "")
                search.text = "";
            else if (Notes.view !== "notes" || Notes.label !== "")
                Notes.show("notes", "");
        } else
            return false;
        return true;
    }

    function emptyTrash() {
        confirm.ask("Empty the trash?", `${Notes.notes.length === 1 ? "The note" : `All ${Notes.notes.length} notes`} in the trash will be deleted for good.`, "Empty trash", () => Notes.emptyTrash());
    }

    title: "Margin"
    implicitWidth: 1180
    implicitHeight: 800
    minimumSize: Qt.size(560, 420)
    color: Theme.surface_container_low
    // Shown by margin-app (shell.qml's IPC), not on starting
    visible: false

    // Loads the notes again on showing: they may have changed meanwhile
    // (the CLI, the menu)
    onVisibleChanged: if (visible) {
        Notes.refresh();
        Qt.callLater(focusGrid);
    }
    Component.onCompleted: Qt.callLater(focusGrid)
    // Closed from outside (Hyprland's close, SUPER+W): hidden, so open
    // shows it again instead of finding it already "visible"
    onClosed: visible = false

    Item {
        id: page

        anchors.fill: parent

        // The grid's keys, while nothing over it has them
        Item {
            id: keys

            focus: true
            Keys.onPressed: event => event.accepted = root.handleKey(event)
        }

        // Clicking the background gives the keys back to the grid
        MouseArea {
            anchors.fill: parent
            onClicked: root.focusGrid()
        }

        Item {
            id: top

            x: 0
            width: parent.width
            height: 76

            Row {
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Icon {
                    name: "sticky_note_2"
                    size: 26
                    color: Theme.primary
                }

                Label {
                    text: "Margin"
                    color: Theme.on_surface
                    font.pixelSize: 24
                    font.weight: Theme.titleWeight
                    roundness: Theme.titleRoundness
                }
            }

            // Search: narrows the notes on show as it's typed
            Rectangle {
                id: searchBox

                anchors.verticalCenter: parent.verticalCenter
                x: sidebar.x + sidebar.width + 16
                width: Math.min(parent.width - x - 28, 720)
                height: 48
                radius: Theme.radius
                color: search.activeFocus ? Theme.surface_container_highest : Theme.surface_container_high

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animFast
                    }
                }

                Icon {
                    x: 18
                    name: "search"
                    size: 20
                    color: Theme.on_surface_variant
                }

                TextInput {
                    id: search

                    anchors.left: parent.left
                    anchors.leftMargin: 52
                    anchors.right: clear.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.on_surface
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.on_primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    clip: true
                    onTextChanged: searchTimer.restart()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            text = "";
                            root.focusGrid();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            Notes.query = text;
                            root.grid.first();
                            root.focusGrid();
                            event.accepted = true;
                        }
                    }

                    Label {
                        anchors.verticalCenter: undefined
                        visible: search.text === ""
                        text: Notes.view === "trash" ? "Search the trash" : Notes.view === "archive" ? "Search the archive" : Notes.label ? `Search ${Notes.label}` : "Search notes"
                        color: Theme.on_surface_variant
                        font: search.font
                    }
                }

                IconButton {
                    id: clear

                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text !== ""
                    icon: "close"
                    iconSize: 16
                    color: Theme.on_surface_variant
                    onClicked: search.text = ""
                }

                Timer {
                    id: searchTimer

                    interval: 150
                    onTriggered: Notes.query = search.text
                }
            }
        }

        Sidebar {
            id: sidebar

            anchors.top: top.bottom
            anchors.bottom: parent.bottom
            x: 8
            width: 252
        }

        Item {
            id: main

            anchors.top: top.bottom
            anchors.bottom: parent.bottom
            anchors.left: sidebar.right
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16

            // The trash's reminder, and its Empty trash
            Item {
                id: trashBar

                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                visible: root.inTrash
                width: Math.min(parent.width, 600)
                height: visible ? 44 : 0

                Label {
                    anchors.left: parent.left
                    anchors.right: emptyButton.left
                    text: "Notes in the trash are deleted after 7 days."
                    color: Theme.on_surface_variant
                    font.weight: Font.Normal
                    font.italic: true
                    elide: Text.ElideRight
                }

                TextButton {
                    id: emptyButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notes.notes.length > 0
                    text: "Empty trash  E"
                    onClicked: root.emptyTrash()
                }
            }

            NoteGrid {
                id: noteGrid

                anchors.top: trashBar.visible ? trashBar.bottom : parent.top
                anchors.topMargin: trashBar.visible ? 24 : 8
                anchors.bottom: parent.bottom
                width: parent.width
                notes: Notes.notes
                onOpened: n => root.openNote(n)
                onToggled: (n, body) => Notes.update(n.id, {
                        body: body
                    })
            }

            // A new note; folds to its icon once the notes scroll
            Fab {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                visible: Notes.view === "notes"
                icon: "edit"
                text: "New note"
                expanded: noteGrid.contentY < 8
                onClicked: root.newNote()
            }

            // Nothing to show
            Column {
                anchors.centerIn: noteGrid
                visible: Notes.loaded && Notes.notes.length === 0
                spacing: 16

                Icon {
                    anchors.verticalCenter: undefined
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: Notes.query ? "search" : Notes.view === "trash" ? "delete" : Notes.view === "archive" ? "archive" : Notes.label ? "label" : "lightbulb"
                    size: 96
                    color: Theme.surface_container_highest
                }

                Label {
                    anchors.verticalCenter: undefined
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Notes.query ? "No matching notes" : Notes.view === "trash" ? "No notes in the trash" : Notes.view === "archive" ? "Your archived notes appear here" : Notes.label ? "No notes with this label yet" : "Notes you add appear here"
                    color: Theme.on_surface_variant
                    font.pixelSize: 18
                    font.weight: Font.Normal
                }
            }
        }

        Editor {
            id: editor

            onClosed: root.focusGrid()
            onPickColor: colorPicker.ask(editor.color, c => {
                editor.color = c;
                editor.changed();
            })
            onPickLabels: labelPicker.ask(editor.labels, labels => {
                editor.labels = labels;
                editor.changed();
            })
            onArchiveNote: (id, to, wasPinned) => root.archived(id, to, wasPinned)
            onCreated: id => root.grid.select(id)
            onTrashNote: id => root.trash(id)
        }

        ColorPicker {
            id: colorPicker

            onFinished: root.focusGrid()
        }

        LabelPicker {
            id: labelPicker

            onFinished: root.focusGrid()
        }

        ConfirmDialog {
            id: confirm

            onOpenChanged: if (open)
                confirmKeys.forceActiveFocus()
            else
                root.focusGrid()

            Item {
                id: confirmKeys

                Keys.onPressed: event => event.accepted = confirm.handleKey(event)
            }
        }

        KeyHelp {
            id: help

            bindings: root.bindings
            onOpenChanged: if (open)
                helpKeys.forceActiveFocus()
            else
                root.focusGrid()

            Item {
                id: helpKeys

                Keys.onPressed: event => event.accepted = help.handleKey(event)
            }
        }

        Snackbar {
            id: snackbar
        }

        // The backend's last error, if it has one
        Snackbar {
            id: errorBar

            Connections {
                target: Notes

                function onErrorChanged() {
                    if (Notes.error)
                        errorBar.show(Notes.error);
                }
            }
        }
    }
}
