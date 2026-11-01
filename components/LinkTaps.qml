import QtQuick

// Opens the link under a click on its Text (its parent) in the browser, and
// shows the hand over one. Text's own link clicks don't come through when
// the card under it takes clicks too; a pointer handler sees them first.
Item {
    id: root

    readonly property Text text: parent

    TapHandler {
        target: null
        parent: root.text
        onTapped: point => {
            const link = root.text.linkAt(point.position.x, point.position.y);
            if (link)
                Qt.openUrlExternally(link);
        }
    }

    HoverHandler {
        id: hover

        parent: root.text
        cursorShape: root.text.linkAt(point.position.x, point.position.y) ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
