//@ pragma AppId io.github.anisthdev.Margin
//@ pragma Env QT_DISABLE_SHADER_DISK_CACHE=1

import Quickshell
import Quickshell.Io
import QtQuick

// margin: notes, in place of Google Keep, two ways in: the window (Margin)
// and the shell-style menu (NoteMenu), both on the same notes (Notes, the
// backend's). Run with `qs -p ~/Projects/margin`; ./margin-app opens either
// (see the IPC below). Neither opens on starting.
ShellRoot {
    id: shell

    Margin {
        id: marginWindow

        onVisibleChanged: saved.windowOpen = visible
    }

    NoteMenu {
        id: noteMenu

        window: marginWindow
        onOpenChanged: saved.menuOpen = open
    }

    // A reload (a file of ours changed) puts back what was open
    PersistentProperties {
        id: saved

        reloadableId: "margin"

        property bool windowOpen: false
        property bool menuOpen: false

        onLoaded: {
            if (windowOpen)
                marginWindow.visible = true;
            if (menuOpen)
                noteMenu.show();
        }
    }

    IpcHandler {
        target: "margin"

        // The window
        function toggle(): void {
            marginWindow.visible = !marginWindow.visible;
        }
        function open(): void {
            marginWindow.visible = true;
        }
        function close(): void {
            marginWindow.visible = false;
        }
        // The window, on a new note
        function compose(): void {
            marginWindow.visible = true;
            marginWindow.newNote();
        }

        // The menu
        function menu(): void {
            noteMenu.open ? noteMenu.hide() : noteMenu.show();
        }
        // The menu, on a new note
        function capture(): void {
            noteMenu.showNew();
        }
    }
}
