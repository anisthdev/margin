pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The notes, from the backend (backend/, the `margin` binary) kept running
// as `margin serve`: JSON requests on its stdin, answers on its stdout, one
// a line (backend/src/serve.rs). Holds what the window shows: the notes of
// the current view, label and search, and every label in use.
Singleton {
    id: root

    // $MARGIN_BIN, else the build in backend/
    readonly property string binary: Quickshell.env("MARGIN_BIN") || Quickshell.shellDir + "/backend/target/release/margin"

    // "notes", "archive" or "trash"; a label narrows "notes" to it
    property string view: "notes"
    property string label
    property string query
    property var notes: []
    property var labels: []
    // Set once the first list has come back
    property bool loaded: false
    property string error

    property int nextReq: 1
    property var pending: ({})

    // After any change, for lists kept elsewhere (the menu's) to load again
    signal changed

    // Sends a request; `done` gets its result, `failed` its error (else
    // it's shown as `error`)
    function request(op, args, done, failed) {
        const req = nextReq++;
        pending[req] = {
            done: done,
            failed: failed
        };
        server.write(JSON.stringify(Object.assign({
            req: req,
            op: op
        }, args ?? {})) + "\n");
    }

    function answer(line) {
        let reply;
        try {
            reply = JSON.parse(line);
        } catch (e) {
            console.warn("margin serve:", line);
            return;
        }
        const job = pending[reply.req];
        delete pending[reply.req];
        if (reply.ok)
            job?.done?.(reply.result);
        else if (job?.failed)
            job.failed(reply.error);
        else
            error = reply.error;
    }

    // Notes for a list of its own, leaving the window's view alone
    function fetch(query, done) {
        request("list", {
            view: "notes",
            query: query || null
        }, done);
    }

    function refresh() {
        changed();
        request("list", {
            view: view,
            label: label || null,
            query: query || null
        }, result => {
            notes = result;
            loaded = true;
        });
        request("labels", {}, result => labels = result);
    }

    // Shows a view, or with a label the notes that have it
    function show(newView, newLabel) {
        view = newView;
        label = newLabel ?? "";
        refresh();
    }

    function create(fields, done) {
        request("create", fields, note => {
            refresh();
            done?.(note);
        });
    }

    // Changes some of a note's fields (title, body, color, labels, pinned,
    // archived)
    function update(id, fields, done) {
        request("update", Object.assign({
            id: id
        }, fields), note => {
            refresh();
            done?.(note);
        });
    }

    function trash(id, done) {
        request("trash", {
            id: id
        }, note => {
            refresh();
            done?.(note);
        });
    }

    function restore(id, done) {
        request("restore", {
            id: id
        }, note => {
            refresh();
            done?.(note);
        });
    }

    function remove(id) {
        request("delete", {
            id: id
        }, () => refresh());
    }

    // A picture from a file onto a note (moved, with removeSource, as from
    // a temporary file); `done` gets the note with it
    function attach(id, path, removeSource, done) {
        request("attach", {
            id: id,
            path: path,
            remove_source: !!removeSource
        }, note => {
            refresh();
            done?.(note);
        });
    }

    // A picture off its note, by its id
    function detach(imageId, done) {
        request("detach", {
            id: imageId
        }, note => {
            refresh();
            done?.(note);
        });
    }

    function emptyTrash() {
        request("empty_trash", {}, () => refresh());
    }

    function renameLabel(from, to) {
        request("rename_label", {
            from: from,
            to: to
        }, () => {
            if (label === from)
                label = to;
            refresh();
        });
    }

    onQueryChanged: refresh()

    Process {
        id: server

        command: [root.binary, "serve"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.answer(line)
        }
        stderr: SplitParser {
            onRead: line => {
                console.warn("margin serve:", line);
                root.error = line;
            }
        }
        onStarted: root.refresh()
        // Requests in flight are lost with it; start it again
        onExited: (code, status) => {
            root.pending = {};
            restart.start();
        }
    }

    Timer {
        id: restart

        interval: 1000
        onTriggered: server.running = true
    }
}
