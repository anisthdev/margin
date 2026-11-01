import QtQuick
import ".."
import "../components"

// A note's Markdown as a card shows it: checklist lines (`- [ ] milk`,
// `- [x] eggs`) as rows with a box that ticks on a click (`toggled` gives
// the body with that line changed), everything else as Markdown text.
Column {
    id: root

    property string body
    property color color: Theme.on_surface
    property bool interactive: true

    signal toggled(string body)

    readonly property var lines: body.split("\n")
    readonly property var blocks: {
        const out = [];
        const item = /^(\s*)[-*+] \[([ xX])\] ?(.*)$/;
        let text = [];
        const flush = () => {
            // Blank lines at a block's ends only make gaps
            while (text.length && text[0].trim() === "")
                text.shift();
            while (text.length && text[text.length - 1].trim() === "")
                text.pop();
            if (text.length)
                out.push({
                    kind: "text",
                    // A line break between plain lines shows as one, as typed,
                    // not as Markdown's space (a hard break: two spaces at the
                    // line's end). Lists, headings and quotes break already.
                    text: text.map((l, i) => i < text.length - 1 && plain(l) && plain(text[i + 1]) ? l.replace(/\s*$/, "  ") : l).map(root.linkify).join("\n")
                });
            text = [];
        };
        lines.forEach((line, i) => {
            const m = item.exec(line);
            if (!m) {
                text.push(line);
                return;
            }
            flush();
            out.push({
                kind: "item",
                line: i,
                indent: m[1].length,
                checked: m[2] !== " ",
                text: m[3]
            });
        });
        flush();
        return out;
    }

    // Links in the theme's colour: Markdown's, bare ones and email
    // addresses made HTML, as Text ignores linkColor for Markdown (its links
    // come out the palette's dark blue). Code spans are left alone.
    function linkify(line) {
        const color = Theme.primary.toString();
        const a = (href, text) => `<a href="${href.replace(/"/g, "%22")}" style="color: ${color}; text-decoration: underline">${text}</a>`;
        const re = /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)|(https?:\/\/[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'"])|([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})/g;
        return line.split(/(`[^`]*`)/).map((part, i) => i % 2 ? part : part.replace(re, (m, text, href, bare, email) => email ? a(`mailto:${email}`, email) : bare ? a(bare, bare) : a(href, text))).join("");
    }

    // A line of running text: not blank, not a list item, heading, quote,
    // table row or code fence
    function plain(line) {
        return line.trim() !== "" && !/^\s*([-*+] |\d+[.)] |#{1,6} |> |\||```|~~~)/.test(line);
    }

    // The body with line i's box ticked or unticked
    function toggle(i) {
        const next = lines.slice();
        next[i] = next[i].replace(/\[([ xX])\]/, (_, c) => c === " " ? "[x]" : "[ ]");
        toggled(next.join("\n"));
    }

    spacing: 4

    Repeater {
        model: root.blocks

        Loader {
            id: block

            required property var modelData

            width: root.width
            sourceComponent: modelData.kind === "item" ? itemRow : textBlock

            Component {
                id: textBlock

                Label {
                    anchors.verticalCenter: undefined
                    text: block.modelData.text
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    color: root.color
                    font.weight: Font.Normal

                    LinkTaps {}
                }
            }

            Component {
                id: itemRow

                Item {
                    implicitHeight: Math.max(box.height, itemText.implicitHeight)

                    Icon {
                        id: box

                        anchors.verticalCenter: undefined
                        x: Math.min(block.modelData.indent, 8) * 8
                        y: Math.max(0, (itemText.lineHeightPx - height) / 2)
                        name: block.modelData.checked ? "check_box" : "check_box_outline_blank"
                        size: 18
                        color: block.modelData.checked ? Theme.on_surface_variant : root.color

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            enabled: root.interactive
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggle(block.modelData.line)
                        }
                    }

                    Label {
                        id: itemText

                        readonly property real lineHeightPx: fontInfo.pixelSize * 1.35

                        anchors.verticalCenter: undefined
                        anchors.left: box.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        text: root.linkify(block.modelData.text)
                        textFormat: Text.MarkdownText
                        wrapMode: Text.Wrap
                        color: block.modelData.checked ? Theme.on_surface_variant : root.color
                        font.weight: Font.Normal
                        font.strikeout: block.modelData.checked

                        LinkTaps {}
                        }
                }
            }
        }
    }
}
