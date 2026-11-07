import Quickshell
import Quickshell.Wayland
import QtQuick
import "components"
import "views"

// margin as one of the shell's menus, for a quick look or a quick note
// without the window: a panel at the bottom centre that springs open
// upwards, as quickbar's menus and Seedling do. It lists the notes (pinned
// first, then the latest); the field, there only while searching, filters
// them as it's typed. A note opens in place, in the window's editor made
// compact.
//
// Keys, vim style, in two modes. It opens in command mode, where single
// keys act on the current note: j/k (or the arrows) move, gg/G go to the
// first and last, Enter/o/l open, p pins, c colours, L labels, a archives,
// d trashes, u undoes the last archive or trash, n starts a note, and Esc
// or q close the menu. i or / bring up the field and type in it: Up/Down
// (Ctrl+j/k) move, Enter opens the note (or, with nothing matching, starts
// one with what's typed), Ctrl+Enter saves what's typed as a new note and
// stays, Ctrl+n starts a note, Ctrl+o opens the note (else the list) in the
// window, Ctrl+w closes, and Esc goes back to command mode, the filter
// kept. In a note, Esc stops typing, to the same keys for that note, and
// Esc again goes back to the list; see views/Editor.qml.
Scope {
    id: menu

    property bool open: false
    property var notes: []
    property int index: 0
    readonly property var current: notes[index] ?? null
    // Not typing in the field: single keys act on the current note
    property bool command: false
    property string pending
    // The last archive or trash, for u: a function putting it back
    property var undo: null
    // A note to select once the list is in again (what undo put back)
    property string follow
    property string loadedQuery

    // The window, for Ctrl+o
    required property var window

    function show() {
        load();
        open = true;
        field.text = "";
        index = 0;
        commandMode();
    }

    // The keys back to the list, in whichever mode it was in
    function refocus() {
        if (editor.open)
            editor.refocus();
        else if (command)
            listKeys.forceActiveFocus();
        else
            field.forceActiveFocus();
    }

    function commandMode() {
        command = true;
        listKeys.forceActiveFocus();
    }

    function typeMode() {
        command = false;
        field.forceActiveFocus();
    }

    function togglePin(n) {
        if (n)
            Notes.update(n.id, {
                pinned: !n.pinned
            });
    }

    function archive(n) {
        if (!n)
            return;
        Notes.update(n.id, {
            archived: true
        });
        undo = () => {
            follow = n.id;
            Notes.update(n.id, {
                archived: false,
                pinned: n.pinned
            });
        };
        snackbar.show("Note archived  ·  u to undo");
    }

    function trash(n) {
        if (!n)
            return;
        Notes.trash(n.id);
        // The trash unpins; undoing pins it again
        undo = () => {
            follow = n.id;
            Notes.restore(n.id, () => {
                if (n.pinned)
                    Notes.update(n.id, {
                        pinned: true
                    });
            });
        };
        snackbar.show("Note moved to the trash  ·  u to undo");
    }

    // Command mode's keys
    function commandKey(event) {
        const t = event.text;
        const was = pending;
        pending = "";
        const n = current;
        if (event.modifiers & Qt.ControlModifier)
            return fieldKey(event);
        if (event.key === Qt.Key_Escape || t === "q")
            hide();
        else if (t === "j" || event.key === Qt.Key_Down)
            move(1);
        else if (t === "k" || event.key === Qt.Key_Up)
            move(-1);
        else if (t === "g" && was === "g")
            move(-notes.length);
        else if (t === "g")
            pending = "g";
        else if (t === "G")
            move(notes.length);
        else if (t === "o" || t === "l" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            openCurrent();
        else if (t === "i" || t === "/")
            typeMode();
        else if (t === "n")
            editor.showNew([]);
        else if (t === "p")
            togglePin(n);
        else if (t === "c" && n)
            colorPicker.ask(n.color, c => Notes.update(n.id, {
                    color: c
                }));
        else if (t === "L" && n)
            labelPicker.ask(n.labels, labels => Notes.update(n.id, {
                    labels: labels
                }));
        else if (t === "a")
            archive(n);
        else if (t === "d" || event.key === Qt.Key_Delete)
            trash(n);
        else if (t === "u" && undo) {
            undo();
            undo = null;
            snackbar.show("Undone");
        } else
            return false;
        return true;
    }

    // On a new note (IPC `capture`)
    function showNew() {
        show();
        Qt.callLater(() => editor.showNew([]));
    }

    function hide() {
        editor.close();
        open = false;
    }

    function load() {
        const query = field.text.trim();
        Notes.fetch(query, result => {
            if (field.text.trim() !== query)
                return; // typed past it
            // The note asked for (by undo), else the current one; gone, the
            // one now in its place; a new search starts at the top
            const id = follow || current?.id;
            follow = "";
            const searched = query !== loadedQuery;
            loadedQuery = query;
            notes = result;
            const keep = notes.findIndex(n => n.id === id);
            index = searched ? 0 : keep >= 0 ? keep : Math.max(0, Math.min(index, notes.length - 1));
            // A new model resets the list's own current index (and its
            // highlight), so it's set again
            list.currentIndex = index;
        });
    }

    function move(step) {
        index = Math.max(0, Math.min(notes.length - 1, index + step));
        list.currentIndex = index;
    }

    function openCurrent() {
        if (current)
            editor.show(current);
        else if (field.text.trim() !== "")
            editor.showNew([], field.text.trim());
    }

    // What's typed, saved as a note without opening it
    function capture() {
        const text = field.text.trim();
        if (text === "")
            return;
        Notes.create({
            body: text
        }, () => snackbar.show("Note saved"));
        field.text = "";
    }

    // Hands over to the window, on the note picked
    function toWindow() {
        const note = editor.open ? null : current;
        hide();
        window.visible = true;
        if (note)
            window.openNote(note);
    }

    function fieldKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        if (event.key === Qt.Key_Down || ctrl && event.key === Qt.Key_J)
            move(1);
        else if (event.key === Qt.Key_Up || ctrl && event.key === Qt.Key_K)
            move(-1);
        else if (ctrl && enter)
            capture();
        else if (enter)
            openCurrent();
        else if (ctrl && event.key === Qt.Key_N)
            editor.showNew([], field.text.trim());
        else if (ctrl && event.key === Qt.Key_O)
            toWindow();
        else if (ctrl && event.key === Qt.Key_W)
            hide();
        else if (event.key === Qt.Key_Escape)
            commandMode();
        else
            return false;
        return true;
    }

    // The first line with text, and what's under it, for a row
    function summary(n) {
        const lines = n.body.split("\n").map(l => l.trim()).filter(l => l !== "");
        const items = lines.filter(l => /^[-*+] \[[ xX]\]/.test(l));
        // Without list markers, Markdown's emphasis and code marks, and links
        // as their text
        const strip = l => l.replace(/^([-*+] (\[[ xX]\] )?|\d+[.)] |#+ |> )/, "").replace(/\[([^\]]+)\]\([^)\s]+\)/g, "$1").replace(/(\*\*|__|\*|`|~~)(.+?)\1/g, "$2");
        const title = n.title || (lines.length ? strip(lines.shift()) : "Empty note");
        let detail;
        if (items.length) {
            const done = items.filter(l => /\[[xX]\]/.test(l)).length;
            const next = items.find(l => /\[ \]/.test(l));
            detail = `${done} of ${items.length} done` + (next ? ` · ${strip(next)}` : "");
        } else
            detail = lines.map(strip).join("  ·  ");
        return {
            title: title,
            detail: detail
        };
    }

    Connections {
        target: Notes

        function onChanged() {
            if (menu.open)
                reload.restart();
        }
    }

    // Loads again a moment after a change, so typing in a note doesn't
    // reload the list at every save
    Timer {
        id: reload

        interval: 200
        onTriggered: menu.load()
    }

    PanelWindow {
        id: surface

        // Spring open upwards, fold back quicker, as the shell's menus
        property real reveal: 0

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // Mapped from opening until the fold-away has finished
        visible: false
        // Its own name, for the compositor's rules: blur it like the shell's
        // menus, and leave out a layer slide (the surface covers the screen)
        WlrLayershell.namespace: "margin"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: menu.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Connections {
            target: menu

            function onOpenChanged() {
                if (menu.open) {
                    closeAnim.stop();
                    surface.visible = true;
                    openAnim.restart();
                } else {
                    openAnim.stop();
                    closeAnim.restart();
                }
            }
        }

        NumberAnimation {
            id: openAnim

            target: surface
            property: "reveal"
            to: 1
            duration: 320
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
        }

        NumberAnimation {
            id: closeAnim

            target: surface
            property: "reveal"
            to: 0
            duration: 150
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.emphasizedAccel
            onFinished: surface.visible = false
        }

        // A click anywhere else closes it
        MouseArea {
            anchors.fill: parent
            onClicked: menu.hide()
        }

        Rectangle {
            id: panel

            // Room for the list or the note, up to most of the screen
            // Up to seven rows; the rest scroll
            readonly property real listHeight: 26 + header.height + fieldBox.height + 12 + Math.min(Math.max(list.contentHeight, 120), 7 * 62 - 2) + 20
            readonly property real noteHeight: 12 + Math.max(editor.wanted, 220) + 12
            readonly property real pickerHeight: colorPicker.open || labelPicker.open ? 420 : 0
            property real fullHeight: Math.min(surface.height - 32 - 60, Math.max(editor.open ? noteHeight : listHeight, pickerHeight))

            // Bottom centre, where the shell's menus open, growing upwards
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: Math.min(640, surface.width - 32)
            height: Math.max(0, fullHeight * surface.reveal)
            radius: Theme.cardRadius
            // See-through, as the shell's menus (the theme here is opaque,
            // for the window)
            color: Qt.alpha(Theme.surface_container, 0.85)
            clip: true

            Behavior on fullHeight {
                enabled: menu.open && !openAnim.running
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.emphasizedDecel
                }
            }

            // Swallow clicks on the panel itself
            MouseArea {
                anchors.fill: parent
            }

            // Laid out at full height, so folding only uncovers it
            Item {
                width: parent.width
                height: panel.fullHeight

                // The list: a title, the field, the notes
                Item {
                    id: page

                    // The launcher's padding
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    anchors.topMargin: 26
                    anchors.bottomMargin: 20
                    opacity: editor.open ? 0 : 1
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animFast
                        }
                    }

                    Item {
                        id: header

                        width: parent.width
                        height: 34

                        Label {
                            x: 2
                            text: "Notes"
                            color: Theme.primary
                            // rofi's 20 pt
                            font.pixelSize: 26
                            font.weight: Theme.titleWeight
                            roundness: Theme.titleRoundness
                        }

                        Label {
                            anchors.right: parent.right
                            text: menu.command ? "Enter open   p pin   c colour   L labels   a archive   d trash   / search" : "Esc commands   Ctrl+Enter save   Ctrl+o window"
                            color: Theme.on_surface_variant
                            font.pixelSize: 12
                            font.weight: Font.Normal
                        }
                    }

                    // The field, while searching: i or / bring it up, and a
                    // filter left in it keeps it
                    Item {
                        id: fieldBox

                        readonly property bool shown: !menu.command || field.text !== ""

                        anchors.top: header.bottom
                        width: parent.width
                        height: shown ? 14 + 48 : 0
                        clip: true

                        Behavior on height {
                            NumberAnimation {
                                duration: Theme.animFast
                                easing.type: Easing.OutCubic
                            }
                        }

                        Rectangle {
                            y: 14
                            width: parent.width
                            height: 48
                            radius: Theme.radius
                            color: Qt.alpha(Theme.surface_container_high, 0.85)
                            border.width: field.activeFocus && !menu.command ? 2 : 0
                            border.color: Theme.primary

                            Icon {
                                x: 18
                                name: "search"
                                size: 20
                                color: Theme.on_surface_variant
                            }

                            TextInput {
                                id: field

                                anchors.left: parent.left
                                anchors.leftMargin: 52
                                anchors.right: parent.right
                                anchors.rightMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.on_surface
                                selectionColor: Theme.primary
                                selectedTextColor: Theme.on_primary
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                clip: true
                                onTextChanged: search.restart()
                                Keys.onPressed: event => event.accepted = menu.fieldKey(event)
                                // A click in it types again
                                onActiveFocusChanged: if (activeFocus)
                                    menu.command = false

                                Label {
                                    anchors.verticalCenter: undefined
                                    visible: field.text === ""
                                    text: "Search, or type a new note"
                                    color: Theme.on_surface_variant
                                    font: field.font
                                }
                            }

                            Timer {
                                id: search

                                interval: 120
                                onTriggered: menu.load()
                            }
                        }
                    }

                    // The rows, grouped as the launcher's: 2 apart, rounder
                    // at the ends
                    ListView {
                        id: list

                        anchors.top: fieldBox.bottom
                        anchors.topMargin: 12
                        anchors.bottom: parent.bottom
                        width: parent.width
                        model: menu.notes
                        spacing: 2
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        // Keeps the current row in view as the keys move it
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: 0
                        preferredHighlightEnd: height
                        // The pick's fill slides from row to row, as the
                        // launcher's: above the rows' backgrounds (on a layer
                        // of their own, below) and under their text
                        highlightFollowsCurrentItem: false
                        highlight: Rectangle {
                            id: pickFill

                            // Not to slide in from the top on opening
                            property bool settled: false

                            Component.onCompleted: Qt.callLater(() => settled = true)

                            y: list.currentItem?.y ?? 0
                            width: list.width
                            height: list.currentItem?.height ?? 0
                            radius: Theme.radius
                            color: Theme.secondary_container

                            Behavior on y {
                                enabled: pickFill.settled
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        delegate: Item {
                            id: row

                            required property var modelData
                            required property int index
                            readonly property bool current: index === menu.index
                            readonly property var text: menu.summary(modelData)
                            readonly property bool first: index === 0
                            readonly property bool last: index === menu.notes.length - 1

                            width: list.width
                            height: 60

                            // The row's background, moved under the list's
                            // highlight; it stays as the pick slides over it
                            Rectangle {
                                parent: list.contentItem
                                z: -1
                                x: row.x
                                y: row.y
                                width: row.width
                                height: row.height
                                topLeftRadius: row.first ? 10 : 3
                                topRightRadius: row.first ? 10 : 3
                                bottomLeftRadius: row.last ? 10 : 3
                                bottomRightRadius: row.last ? 10 : 3
                                color: Qt.alpha(Theme.surface_container_high, 0.85)
                            }

                            // The note's colour, as a stripe
                            Rectangle {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4
                                height: 28
                                radius: 2
                                visible: row.modelData.color !== ""
                                color: NoteColors.fill(row.modelData.color)
                            }

                            Column {
                                x: 18
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 18 - (thumb.visible ? thumb.width + 14 : 0) - (pin.visible ? 44 : 18)
                                spacing: 2

                                Label {
                                    anchors.verticalCenter: undefined
                                    width: parent.width
                                    text: row.text.title
                                    color: row.current ? Theme.on_secondary_container : Theme.on_surface
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                }

                                Label {
                                    anchors.verticalCenter: undefined
                                    width: parent.width
                                    visible: text !== ""
                                    text: row.text.detail
                                    color: row.current ? Theme.on_secondary_container : Theme.on_surface_variant
                                    font.pixelSize: 12
                                    font.weight: Font.Normal
                                    elide: Text.ElideRight
                                }
                            }

                            // The first picture, small
                            Picture {
                                id: thumb

                                anchors.right: pin.visible ? pin.left : parent.right
                                anchors.rightMargin: pin.visible ? 12 : 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                height: 44
                                radius: 8
                                visible: row.modelData.images.length > 0
                                path: row.modelData.images[0]?.path ?? ""
                            }

                            Icon {
                                id: pin

                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                visible: row.modelData.pinned
                                name: "keep"
                                size: 16
                                color: row.current ? Theme.on_secondary_container : Theme.on_surface_variant
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    menu.index = row.index;
                                    list.currentIndex = row.index;
                                    menu.openCurrent();
                                }
                            }
                        }
                    }

                    Label {
                        anchors.horizontalCenter: list.horizontalCenter
                        anchors.verticalCenter: undefined
                        anchors.top: list.top
                        anchors.topMargin: 40
                        visible: menu.notes.length === 0
                        text: field.text.trim() === "" ? (menu.command ? "No notes yet: n starts one" : "No notes yet: type one, then Ctrl+Enter") : "Nothing matches. Enter starts a note with it, Ctrl+Enter saves it."
                        color: Theme.on_surface_variant
                        font.weight: Font.Normal
                    }
                }

                Editor {
                    id: editor

                    anchors.fill: parent
                    anchors.margins: 12
                    compact: true
                    onClosed: {
                        if (menu.open)
                            menu.refocus();
                        menu.load();
                    }
                    onPickColor: colorPicker.ask(editor.color, c => {
                        editor.color = c;
                        editor.changed();
                    })
                    onPickLabels: labelPicker.ask(editor.labels, labels => {
                        editor.labels = labels;
                        editor.changed();
                    })
                    onArchiveNote: (id, to) => snackbar.show(to ? "Note archived" : "Note unarchived")
                    onTrashNote: id => {
                        Notes.trash(id);
                        snackbar.show("Note moved to the trash");
                    }
                }

                ColorPicker {
                    id: colorPicker

                    onFinished: menu.refocus()
                }

                LabelPicker {
                    id: labelPicker

                    onFinished: menu.refocus()
                }

                // Command mode's keys, while the field isn't typing
                Item {
                    id: listKeys

                    Keys.onPressed: event => event.accepted = menu.commandKey(event)
                }

                Snackbar {
                    id: snackbar
                }
            }
        }
    }
}
