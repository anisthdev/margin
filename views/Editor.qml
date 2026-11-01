import Quickshell
import Quickshell.Io
import QtQuick
import ".."
import "../components"

// An open note, over the grid as Keep opens one: its title, its Markdown
// body, its labels and a toolbar. Changes save themselves a moment after
// typing stops, and on closing. A new note isn't made until it has some
// text, so opening one and closing it leaves nothing behind. Notes in the
// trash open read-only.
//
// In the body, Enter on a list line (`- `, `- [ ] `, `1. `) starts the
// next item, and on an empty item ends the list. Ctrl+L adds or takes off a
// line's checkbox, Ctrl+Enter ticks it. Alt+p/c/l/a/d pin, colour, label,
// archive and trash, as p/c/L/a/d do on the grid. Ctrl+click on a link
// opens it.
//
// Esc stops typing, vim style, into command mode (the toolbar lists its
// keys): p pins, c colours, L labels, a archives, d trashes, i or Enter
// type in the body again, t in the title, and Esc or q close the note. A
// click in the text types again too.
//
// Pictures: Ctrl+V with one on the clipboard, or files dropped on the
// card, attach them (making the note first, if it's new). They show across
// the top; a click opens one, its × takes it off.
//
// `compact` is the menu's: no scrim, the card filling the editor's space
// rather than floating over it.
Item {
    id: root

    property bool open: false
    property bool compact: false
    // Not typing: single keys act on the note (see keys)
    property bool command: false
    // Where typing goes back to, after command mode or a picker
    property Item lastField: body
    // The card's height for its content, for the menu to make room
    readonly property real wanted: column.implicitHeight + toolbar.height + 16
    // "" until a new note is first saved
    property string noteId
    property string color
    property var labels: []
    property bool pinned: false
    property bool archived: false
    property bool trashed: false
    property real updated: 0
    // A save is waiting, or a create is in flight
    property bool dirty: false
    property bool creating: false
    // What waits on a note being made: functions given its id
    property var waiting: []
    property var images: []

    // Asked of the window, which owns the pickers and the snackbar
    signal pickColor
    signal pickLabels
    signal archiveNote(string id, bool archived, bool wasPinned)
    signal created(string id)
    signal trashNote(string id)
    signal closed

    function show(note) {
        noteId = note.id;
        title.text = note.title;
        body.text = note.body;
        color = note.color;
        labels = note.labels;
        images = note.images;
        pinned = note.pinned;
        archived = note.archived;
        trashed = note.trashed;
        updated = note.updated;
        dirty = false;
        command = false;
        open = true;
        Qt.callLater(() => {
            if (trashed)
                keys.forceActiveFocus();
            else {
                body.forceActiveFocus();
                body.cursorPosition = body.length;
            }
        });
    }

    // A new note, with these labels (the label being shown) and, from the
    // menu's field, this body
    function showNew(labels, text) {
        noteId = "";
        title.text = "";
        body.text = text ?? "";
        color = "";
        root.labels = labels ?? [];
        images = [];
        pinned = false;
        archived = false;
        trashed = false;
        updated = 0;
        dirty = false;
        command = false;
        open = true;
        dirty = body.text !== "";
        Qt.callLater(() => {
            if (body.text === "")
                title.forceActiveFocus();
            else {
                body.forceActiveFocus();
                body.cursorPosition = body.length;
            }
        });
    }

    function fields() {
        return {
            title: title.text.trim(),
            body: body.text.replace(/\s+$/, ""),
            color: color,
            labels: labels,
            pinned: pinned,
            archived: archived
        };
    }

    function changed() {
        if (trashed)
            return;
        dirty = true;
        saveTimer.restart();
    }

    function save() {
        saveTimer.stop();
        if (!dirty || trashed)
            return;
        if (creating)
            return; // saved again once the create is back
        const f = fields();
        if (noteId === "") {
            if (f.title === "" && f.body === "") {
                dirty = false;
                return;
            }
            creating = true;
            dirty = false;
            Notes.create(f, made);
        } else {
            dirty = false;
            Notes.update(noteId, f, note => updated = note.updated);
        }
    }

    // A new note, back from the backend
    function made(note) {
        creating = false;
        noteId = note.id;
        updated = note.updated;
        created(note.id);
        const later = waiting;
        waiting = [];
        later.forEach(f => f(note.id));
        if (dirty)
            save();
    }

    // Runs `action` with the note's id, making the note first if it's new
    // (even empty: a picture is enough)
    function withNote(action) {
        if (noteId !== "") {
            action(noteId);
            return;
        }
        waiting = waiting.concat([action]);
        if (creating)
            return;
        saveTimer.stop();
        creating = true;
        dirty = false;
        Notes.create(fields(), made);
    }

    function attach(path, temporary) {
        if (trashed)
            return;
        withNote(id => Notes.attach(id, path, temporary, note => {
                images = note.images;
                updated = note.updated;
            }));
    }

    // Takes a picture off; here, not in its delegate, which is gone by the
    // time the answer comes back
    function detach(imageId) {
        images = images.filter(i => i.id !== imageId);
        Notes.detach(imageId, note => {
            images = note.images;
            updated = note.updated;
        });
    }

    // Ctrl+V: a picture on the clipboard is attached, anything else pasted
    // as text into `field`
    function paste(field) {
        clipboardTypes.field = field;
        clipboardTypes.running = true;
    }

    // The link (Markdown's or bare) at a place in the body, else ""
    function linkAt(pos) {
        const re = /https?:\/\/[^\s<>()\[\]]+/g;
        let m;
        while ((m = re.exec(body.text)) !== null)
            if (pos >= m.index && pos <= m.index + m[0].length)
                return m[0].replace(/[.,;:!?'"]+$/, "");
        return "";
    }

    function close() {
        if (!open)
            return;
        save();
        open = false;
        closed();
    }

    // The line the cursor is on: [start, end]
    function currentLine() {
        const pos = body.cursorPosition;
        const start = body.text.lastIndexOf("\n", pos - 1) + 1;
        let end = body.text.indexOf("\n", pos);
        if (end < 0)
            end = body.text.length;
        return [start, end];
    }

    function replaceLine(start, end, line, cursorFromEnd) {
        const old = body.text.slice(start, end);
        const keep = body.cursorPosition - start;
        body.remove(start, end);
        body.insert(start, line);
        body.cursorPosition = cursorFromEnd !== undefined ? start + line.length - cursorFromEnd : start + Math.max(0, Math.min(line.length, keep + line.length - old.length));
    }

    // Enter on a list line: the next item, or the end of the list on an
    // empty one. False when the line isn't one.
    function continueList() {
        const [start, end] = currentLine();
        const line = body.text.slice(start, end);
        const m = /^(\s*)([-*+] \[[ xX]\] |[-*+] |(\d+)([.)]) )(.*)$/.exec(line);
        if (!m || body.cursorPosition < start + m[1].length + m[2].length)
            return false;
        if (m[5].trim() === "") {
            replaceLine(start, end, "", 0);
            return true;
        }
        let marker = m[2];
        if (/\[[xX]\]/.test(marker))
            marker = marker.replace(/\[[xX]\]/, "[ ]");
        if (m[3] !== undefined)
            marker = `${parseInt(m[3]) + 1}${m[4]} `;
        body.insert(body.cursorPosition, "\n" + m[1] + marker);
        return true;
    }

    // Ctrl+L: a plain line or bullet gets a checkbox, a checkbox loses it
    function toggleCheckbox() {
        const [start, end] = currentLine();
        const line = body.text.slice(start, end);
        let m = /^(\s*)[-*+] \[[ xX]\] (.*)$/.exec(line);
        if (m) {
            replaceLine(start, end, m[1] + m[2]);
            return;
        }
        m = /^(\s*)(?:[-*+] )?(.*)$/.exec(line);
        replaceLine(start, end, `${m[1]}- [ ] ${m[2]}`);
    }

    // Ctrl+Enter: ticks or unticks the line's box
    function toggleChecked() {
        const [start, end] = currentLine();
        const line = body.text.slice(start, end);
        if (/^\s*[-*+] \[[ xX]\]/.test(line))
            replaceLine(start, end, line.replace(/\[([ xX])\]/, (_, c) => c === " " ? "[x]" : "[ ]"));
    }

    // Alt+letter, as the grid's letters; true when it was one
    function action(event) {
        if (!(event.modifiers & Qt.AltModifier) || trashed)
            return false;
        switch (event.key) {
        case Qt.Key_P:
            togglePin();
            return true;
        case Qt.Key_C:
            pickColor();
            return true;
        case Qt.Key_L:
            pickLabels();
            return true;
        case Qt.Key_A:
            archive();
            return true;
        case Qt.Key_D:
            trash();
            return true;
        }
        return false;
    }

    // As Keep: pinning an archived note brings it back, archiving unpins
    function togglePin() {
        pinned = !pinned;
        if (pinned)
            archived = false;
        changed();
    }

    function archive() {
        const wasPinned = pinned;
        archived = !archived;
        if (archived)
            pinned = false;
        dirty = true;
        const id = noteId;
        close();
        if (id !== "")
            archiveNote(id, archived, wasPinned);
    }

    function trash() {
        save();
        const id = noteId;
        open = false;
        closed();
        if (id !== "")
            trashNote(id);
    }

    // Focus back after a picker
    function refocus() {
        if (open)
            (trashed || command ? keys : lastField).forceActiveFocus();
    }

    // Esc while typing: the note's keys instead (saving what's typed)
    function commandMode() {
        save();
        command = true;
        keys.forceActiveFocus();
    }

    // Back to typing, in `field` (the body or the title)
    function edit(field) {
        command = false;
        field.forceActiveFocus();
    }

    function edited(ms) {
        if (!ms)
            return "";
        const d = new Date(ms), now = new Date();
        const time = d.toLocaleTimeString(Qt.locale(), "h:mm AP");
        if (d.toDateString() === now.toDateString())
            return `Edited ${time}`;
        const yesterday = new Date(now.getTime() - 86400000);
        if (d.toDateString() === yesterday.toDateString())
            return `Edited yesterday, ${time}`;
        return `Edited ${d.toLocaleDateString(Qt.locale(), d.getFullYear() === now.getFullYear() ? "MMM d" : "MMM d, yyyy")}`;
    }

    anchors.fill: parent
    visible: open || scrim.opacity > 0

    Process {
        id: clipboardTypes

        property var field: null

        command: ["wl-paste", "--list-types"]
        stdout: StdioCollector {
            onStreamFinished: {
                const types = text.split("\n");
                const image = ["image/png", "image/jpeg", "image/webp", "image/gif"].find(t => types.includes(t));
                if (image) {
                    clipboardImage.command = ["sh", "-c", 'f=$(mktemp -p "${XDG_RUNTIME_DIR:-/tmp}" margin-paste-XXXXXX) && wl-paste --type "$1" > "$f" && printf %s "$f"', "sh", image];
                    clipboardImage.running = true;
                } else
                    clipboardTypes.field?.paste();
            }
        }
    }

    // The clipboard's picture, into a temporary file the backend moves in
    Process {
        id: clipboardImage

        stdout: StdioCollector {
            onStreamFinished: if (text !== "")
                root.attach(text, true)
        }
    }

    Timer {
        id: saveTimer

        interval: 600
        onTriggered: root.save()
    }

    Rectangle {
        id: scrim

        anchors.fill: parent
        color: root.compact ? "transparent" : Qt.rgba(0, 0, 0, 0.5)
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animFast
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !root.compact
            onClicked: root.close()
        }
    }

    // Command mode's keys, and a read-only note's
    Item {
        id: keys

        Keys.onPressed: event => {
            event.accepted = true;
            const t = event.text;
            if (event.key === Qt.Key_Escape || t === "q")
                root.close();
            else if (root.trashed || event.modifiers & Qt.ControlModifier)
                event.accepted = false;
            else if (t === "i" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                root.edit(body);
            else if (t === "t")
                root.edit(title);
            else if (t === "p")
                root.togglePin();
            else if (t === "c")
                root.pickColor();
            else if (t === "L")
                root.pickLabels();
            else if (t === "a")
                root.archive();
            else if (t === "d")
                root.trash();
            else
                event.accepted = false;
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: root.compact ? undefined : parent
        width: root.compact ? parent.width : Math.min(parent.width - 48, 640)
        height: root.compact ? parent.height : Math.min(parent.height - 48, root.wanted)
        radius: root.compact ? Theme.radius + 2 : Theme.cardRadius
        color: NoteColors.fill(root.color)
        border.width: root.color === "" ? 1 : 0
        border.color: Theme.outline_variant
        opacity: scrim.opacity
        scale: root.compact ? 1 : 0.96 + 0.04 * scrim.opacity

        Behavior on color {
            ColorAnimation {
                duration: Theme.animNormal
            }
        }
        Behavior on height {
            enabled: !root.compact
            NumberAnimation {
                duration: Theme.animFast
            }
        }

        // Swallow clicks on the card itself
        MouseArea {
            anchors.fill: parent
            onClicked: body.forceActiveFocus()
        }

        // Pictures dropped on it are attached
        DropArea {
            id: drop

            anchors.fill: parent
            enabled: !root.trashed
            keys: ["text/uri-list"]
            onDropped: event => {
                for (const url of event.urls) {
                    const s = url.toString();
                    if (s.startsWith("file://"))
                        root.attach(decodeURIComponent(s.slice(7)), false);
                }
                event.accept();
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: Theme.primary
            visible: drop.containsDrag
            z: 2
        }

        Flickable {
            id: flick

            anchors.top: parent.top
            anchors.bottom: toolbar.top
            width: parent.width
            contentWidth: width
            contentHeight: column.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            // Keeps the cursor in sight as it moves
            function follow(rect, item) {
                const y = item.mapToItem(column, 0, rect.y).y;
                if (y < contentY)
                    contentY = Math.max(0, y - 8);
                else if (y + rect.height > contentY + height)
                    contentY = y + rect.height - height + 8;
            }

            Column {
                id: column

                x: 20
                width: parent.width - 40
                topPadding: 18
                bottomPadding: 8
                spacing: 10

                // The pictures, each its own shape, up to a height
                Flow {
                    width: parent.width
                    spacing: 6
                    visible: root.images.length > 0

                    Repeater {
                        model: root.images

                        Picture {
                            id: picture

                            required property var modelData

                            height: root.images.length === 1 ? Math.min(root.compact ? 200 : 320, parent.width * aspect) : root.compact ? 100 : 140
                            width: root.images.length === 1 ? parent.width : Math.min(parent.width, height / aspect)
                            path: modelData.path

                            MouseArea {
                                id: pictureMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                // xdg-open, not Qt.openUrlExternally: the portal that
                                // goes through asks which app, for files
                                onClicked: Quickshell.execDetached(["xdg-open", picture.path])
                            }

                            // Takes it off, on hover
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                width: 30
                                height: 30
                                radius: 15
                                color: Qt.rgba(0, 0, 0, 0.55)
                                visible: !root.trashed && (pictureMouse.containsMouse || remove.containsMouse)

                                Icon {
                                    anchors.centerIn: parent
                                    name: "close"
                                    size: 14
                                    color: "white"
                                }

                                MouseArea {
                                    id: remove

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.detach(picture.modelData.id)
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: Math.max(title.implicitHeight, 24)

                    TextInput {
                        id: title

                        anchors.left: parent.left
                        anchors.right: pinButton.left
                        anchors.rightMargin: 8
                        readOnly: root.trashed
                        color: Theme.on_surface
                        selectionColor: Theme.primary
                        selectedTextColor: Theme.on_primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        wrapMode: TextInput.Wrap
                        onTextEdited: root.changed()
                        onActiveFocusChanged: if (activeFocus) {
                            root.command = false;
                            root.lastField = title;
                        }
                        Keys.onPressed: event => {
                            if (root.action(event)) {
                                event.accepted = true;
                            } else if (event.matches(StandardKey.Paste) && !root.trashed) {
                                event.accepted = true;
                                root.paste(title);
                            } else if (event.key === Qt.Key_Escape) {
                                event.accepted = true;
                                root.commandMode();
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                event.accepted = true;
                                body.forceActiveFocus();
                                if (event.key !== Qt.Key_Down)
                                    body.cursorPosition = 0;
                            }
                        }

                        Label {
                            anchors.verticalCenter: undefined
                            visible: title.text === ""
                            text: "Title"
                            color: Theme.on_surface_variant
                            font: title.font
                        }
                    }

                    IconButton {
                        id: pinButton

                        anchors.right: parent.right
                        anchors.rightMargin: -6
                        y: -4
                        visible: !root.trashed
                        icon: root.pinned ? "keep" : "keep_off"
                        iconSize: 18
                        color: root.pinned ? Theme.primary : Theme.on_surface_variant
                        onClicked: root.togglePin()
                    }
                }

                TextEdit {
                    id: body

                    width: parent.width
                    readOnly: root.trashed
                    color: Theme.on_surface
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.on_primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    selectByMouse: true
                    onTextChanged: if (activeFocus)
                        root.changed()
                    onActiveFocusChanged: if (activeFocus) {
                        root.command = false;
                        root.lastField = body;
                    }
                    onCursorRectangleChanged: if (activeFocus)
                        flick.follow(cursorRectangle, body)
                    Keys.onPressed: event => {
                        if (root.action(event)) {
                            event.accepted = true;
                        } else if (event.matches(StandardKey.Paste) && !root.trashed) {
                            event.accepted = true;
                            root.paste(body);
                        } else if (event.key === Qt.Key_Escape) {
                            event.accepted = true;
                            root.commandMode();
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                            event.accepted = true;
                            root.toggleChecked();
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            event.accepted = root.continueList();
                        } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                            event.accepted = true;
                            root.toggleCheckbox();
                        } else if (event.key === Qt.Key_Up && body.cursorRectangle.y < 4) {
                            event.accepted = true;
                            title.forceActiveFocus();
                        }
                    }

                    // Ctrl+click opens the link under it
                    TapHandler {
                        acceptedModifiers: Qt.ControlModifier
                        onTapped: point => {
                            const link = root.linkAt(body.positionAt(point.position.x, point.position.y));
                            if (link)
                                Qt.openUrlExternally(link);
                        }
                    }

                    Label {
                        anchors.verticalCenter: undefined
                        visible: body.text === ""
                        text: "Take a note…"
                        color: Theme.on_surface_variant
                        font: body.font
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6
                    topPadding: 6
                    visible: root.labels.length > 0

                    Repeater {
                        model: root.labels

                        Chip {
                            required property string modelData

                            text: modelData
                            removable: !root.trashed
                            onRemoved: {
                                root.labels = root.labels.filter(l => l !== modelData);
                                root.changed();
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: toolbar

            anchors.bottom: parent.bottom
            width: parent.width
            height: 52

            Row {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                visible: !root.trashed

                IconButton {
                    icon: "palette"
                    iconSize: 18
                    color: Theme.on_surface_variant
                    onClicked: root.pickColor()
                }

                IconButton {
                    icon: "label"
                    iconSize: 18
                    color: Theme.on_surface_variant
                    onClicked: root.pickLabels()
                }

                IconButton {
                    icon: root.archived ? "unarchive" : "archive"
                    iconSize: 18
                    color: Theme.on_surface_variant
                    onClicked: root.archive()
                }

                IconButton {
                    icon: "delete"
                    iconSize: 18
                    color: Theme.on_surface_variant
                    onClicked: root.trash()
                }
            }

            Label {
                x: 20
                visible: root.trashed
                text: "Note in the trash — r restores it from the grid"
                color: Theme.on_surface_variant
                font.pixelSize: 12
                font.weight: Font.Normal
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // In command mode, its keys; else when it was last edited
                Label {
                    width: Math.min(implicitWidth, toolbar.width - 250)
                    text: root.command && !root.trashed ? "i edit   p pin   c colour   L labels   a archive   d trash" : root.edited(root.updated)
                    color: root.command && !root.trashed ? Theme.primary : Theme.on_surface_variant
                    font.pixelSize: 12
                    font.weight: root.command && !root.trashed ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }

                TextButton {
                    text: "Close"
                    color: Theme.on_surface
                    onClicked: root.close()
                }
            }
        }
    }
}
