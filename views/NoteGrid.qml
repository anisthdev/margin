import QtQuick
import ".."
import "../components"

// The notes as Keep lays them out: cards in columns, each going under the
// shortest column so far, pinned ones first under their own heading. The
// keyboard's current note is kept by id, so it stays put as notes change.
// Moving goes to the nearest card that way on screen.
Flickable {
    id: root

    property var notes: []
    property string currentId
    readonly property int currentIndex: notes.findIndex(n => n.id === currentId)
    readonly property var current: currentIndex >= 0 ? notes[currentIndex] : null
    // Headings over the pinned and other notes, when there are both
    readonly property bool sections: notes.some(n => n.pinned) && notes.some(n => !n.pinned)

    readonly property real minCardWidth: 230
    readonly property real gap: 14
    readonly property int columns: Math.max(1, Math.floor((width + gap) / (minCardWidth + gap)))
    readonly property real cardWidth: Math.min(300, (width - gap * (columns - 1)) / columns)
    // The columns, centred
    readonly property real offset: Math.max(0, (width - columns * cardWidth - (columns - 1) * gap) / 2)

    property real othersY: 0

    signal opened(var note)
    signal toggled(var note, string body)

    function relayout() {
        Qt.callLater(layout);
    }

    function layout() {
        const header = 34;
        let top = sections ? header : 0;
        let pinnedDone = !sections;
        let heights = new Array(columns).fill(top);
        for (let i = 0; i < cards.count; i++) {
            const card = cards.itemAt(i);
            if (!card)
                continue;
            if (!pinnedDone && !card.note.pinned) {
                // The others start under the tallest pinned column
                pinnedDone = true;
                othersY = Math.max(...heights) + 10;
                heights = new Array(columns).fill(othersY + header);
            }
            let col = 0;
            for (let c = 1; c < columns; c++)
                if (heights[c] < heights[col])
                    col = c;
            card.column = col;
            card.x = offset + col * (cardWidth + gap);
            card.y = heights[col];
            heights[col] += card.height + gap;
        }
        // Room at the bottom so the last cards scroll clear of the FAB
        canvas.height = Math.max(0, ...heights) + 96;
    }

    // The card nearest the current one in a direction ("up", "down",
    // "left", "right"); stays put when there's none
    function move(direction) {
        const from = cards.itemAt(currentIndex);
        if (!from) {
            first();
            return;
        }
        const fx = from.x + from.width / 2, fy = from.y + from.height / 2;
        let best = null, bestScore = Infinity;
        for (let i = 0; i < cards.count; i++) {
            const card = cards.itemAt(i);
            if (!card || card === from)
                continue;
            const cx = card.x + card.width / 2, cy = card.y + card.height / 2;
            let along, across;
            switch (direction) {
            case "down":
                along = card.y - (from.y + from.height) + 1;
                across = Math.abs(cx - fx);
                break;
            case "up":
                along = from.y - (card.y + card.height) + 1;
                across = Math.abs(cx - fx);
                break;
            case "right":
                along = cx - fx;
                across = Math.abs(cy - fy);
                break;
            case "left":
                along = fx - cx;
                across = Math.abs(cy - fy);
                break;
            }
            if (along <= 0)
                continue;
            // Staying in the column (or row) matters most
            const score = along + across * 4;
            if (score < bestScore) {
                bestScore = score;
                best = card;
            }
        }
        if (best)
            select(best.note.id);
    }

    function select(id) {
        currentId = id;
        reveal();
    }

    function first() {
        if (notes.length > 0)
            select(notes[0].id);
    }

    function last() {
        if (notes.length > 0)
            select(notes[notes.length - 1].id);
    }

    // Scrolls the current card into view
    function reveal() {
        Qt.callLater(() => {
            const card = cards.itemAt(currentIndex);
            if (!card)
                return;
            if (card.y - 12 < contentY)
                contentY = Math.max(0, card.y - (currentIndex === 0 || sections && card.y < 60 ? 40 : 12));
            else if (card.y + card.height + 12 > contentY + height)
                contentY = Math.min(contentHeight - height, card.y + card.height + 12 - height);
        });
    }

    // After the notes change: keep the current one, else take the one now
    // where it was
    property int lastIndex: 0
    onCurrentIndexChanged: if (currentIndex >= 0)
        lastIndex = currentIndex
    onNotesChanged: {
        sync();
        // Not currentIndex: its binding may not have caught up with notes yet
        if (notes.length > 0 && !notes.some(n => n.id === currentId))
            currentId = notes[Math.min(lastIndex, notes.length - 1)].id;
        relayout();
    }

    // The cards' model follows notes by id, moving and changing rows in
    // place, so a save doesn't rebuild every card and a note that moves
    // slides to its new place
    function sync() {
        const ids = new Set(notes.map(n => n.id));
        for (let i = cardModel.count - 1; i >= 0; i--)
            if (!ids.has(cardModel.get(i).nid))
                cardModel.remove(i);
        notes.forEach((n, i) => {
            const json = JSON.stringify(n);
            let j = i;
            while (j < cardModel.count && cardModel.get(j).nid !== n.id)
                j++;
            if (j === cardModel.count)
                cardModel.insert(i, {
                    nid: n.id,
                    json: json
                });
            else {
                if (j !== i)
                    cardModel.move(j, i, 1);
                if (cardModel.get(i).json !== json)
                    cardModel.setProperty(i, "json", json);
            }
        });
    }
    onWidthChanged: relayout()
    onSectionsChanged: relayout()

    contentWidth: width
    contentHeight: canvas.height
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Behavior on contentY {
        NumberAnimation {
            duration: Theme.animFast
        }
    }

    Item {
        id: canvas

        width: root.width

        Label {
            anchors.verticalCenter: undefined
            x: root.offset + 6
            y: 8
            visible: root.sections
            text: "PINNED"
            color: Theme.on_surface_variant
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }

        Label {
            anchors.verticalCenter: undefined
            x: root.offset + 6
            y: root.othersY + 8
            visible: root.sections
            text: "OTHERS"
            color: Theme.on_surface_variant
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }

        Repeater {
            id: cards

            model: ListModel {
                id: cardModel
            }

            NoteCard {
                required property string json

                note: JSON.parse(json)
                width: root.cardWidth
                current: note.id === root.currentId
                onHeightChanged: root.relayout()
                onNoteChanged: root.relayout()
                onClicked: root.select(note.id)
                onOpened: root.opened(note)
                onToggled: body => root.toggled(note, body)
            }

            onItemAdded: root.relayout()
            onItemRemoved: root.relayout()
        }
    }
}
