# margin

Notes, to replace Google Keep, syncing between the phone and this machine. App ID `io.github.anisthdev.Margin`. Primary target: Arch Linux + Hyprland, alongside the shell (`~/Projects/quickbar`), whose look and keyboard-first style it shares.

## Phases

1. **The app, local only** (this). A Quickshell window over a Rust backend keeping the notes in SQLite.
2. **Sync**: the backend grows into a daemon syncing to a server of our own. Rust so it ships as one static binary (musl).
3. **Android client**: native Kotlin + Compose (home-screen widget, share target, reminders), talking to the server.
4. **Keep import**: Google Takeout's Keep JSON into the store. Colours and labels already follow Keep's (`NoteColors.qml`, `store::COLORS`).

## How it runs

```
makepkg -si                 # install: margin (backend), margin-app, the QML in /etc/xdg/quickshell/margin
ln -s ~/Projects/margin ~/.config/quickshell/margin   # run this checkout instead (comes first)
cargo build --release --manifest-path backend/Cargo.toml   # the backend; MARGIN_BIN=$PWD/backend/target/release/margin to use it
./margin-app              # open or close the window, starting margin if it isn't running
./margin-app new          # the window, on a new note
./margin-app menu         # open or close the menu
./margin-app menu new     # the menu, on a new note
qs -c margin ipc call margin toggle|open|close|compose|menu|capture
```

Two ways in, one instance (`shell.qml`), the same notes and backend:

- **The window** (`Margin.qml`): an ordinary one (`FloatingWindow`), tiled or floated like any app, with everything (side menu, grid, archive, trash).
- **The menu** (`NoteMenu.qml`): one of the shell's menus, as Seedling is: a layer-shell panel at the bottom centre (namespace `quickbar-overlay`, so Hyprland blurs it like quickbar's), see-through. A field filtering the notes, up to seven rows, and the window's editor made compact (`Editor.compact`). Enter opens, Ctrl+Enter saves what's typed as a note, Ctrl+o hands over to the window. It keeps its own list (`Notes.fetch`, reloaded on `Notes.changed`), so it doesn't follow the window's view.

Neither opens on starting; `margin-app` starts margin and then asks. A reload puts back whatever was open (`PersistentProperties` in `shell.qml`). Closing the window (q, Ctrl+w) hides it; margin keeps running. `io.github.anisthdev.Margin.desktop` (installed by the package) is the launcher entry, with New note and Quick menu actions.

No build step for the QML: Quickshell reloads the running app when a file changes. Restart it after rebuilding the backend (`qs kill -c margin`), since `margin serve` keeps running the old binary. Check `qs list --all` for stray instances: two at once confuse IPC. Logs: `/run/user/1000/quickshell/by-id/*/log.qslog`.

## Backend (`backend/`, the `margin` binary)

All storage and logic live here, never in QML, so the sync daemon, the CLI and the Keep import share them.

- `store.rs`: SQLite at `$MARGIN_DB`, else `~/.local/share/margin/margin.db` (WAL, so the app and a CLI call can share it). Built for sync: UUIDv7 ids, `updated_at` and `device` on every change (the device's id is in `meta`), deletes leave tombstones (`deleted = 1`, content cleared). Trash (`trashed_at`) empties itself after 7 days. Labels are a JSON array on each note. Keep's rules: archiving unpins, pinning an archived note unarchives it.
- `serve.rs`: `margin serve`, JSON lines on stdin/stdout. Requests carry `req` (not `id`: that's a note's field) and `op`; answers echo `req` with `ok` and `result` or `error`.
- `main.rs`: the CLI (`list`, `show`, `new`, `edit` with a JSON patch on stdin, `trash`, `restore`, `delete`, `empty-trash`, `labels`, `rename-label`, `attach`, `detach`, `path`).

- Pictures are attachments (as Keep's): an `attachments` row each (id, note, file, MIME type, time, device, tombstone) and a file named by its id in `attachments/` beside the database. Only PNG, JPEG, GIF and WebP, told by their first bytes. `attach` copies a file in (`remove_source` moves a temporary one), `detach` takes one off; deleting a note for good drops its pictures. Notes carry them as `images: [{id, path}]`.

The body is Markdown. Checklists are `- [ ] ` / `- [x] ` lines; cards draw them as boxes that tick on a click (`views/NoteBody.qml`). A single line break shows as one (a hard break added between plain lines). Links, Markdown's and bare, are made HTML there so they take the theme's colour (Text ignores `linkColor` for Markdown) and open through `components/LinkTaps.qml` (the card's MouseArea keeps Text's own link clicks from coming through). In the editor, Ctrl+click opens the link under it.

Pictures go on with Ctrl+V in the editor (`wl-paste` into a temporary file the backend moves in; text pastes as text) or by dropping files on its card; a new note is made first if need be (`Editor.withNote`). Cards show the first picture across the top and up to three more as squares; the editor shows them all, a click opening one, its × taking it off.

## Layout

```
shell.qml           # entry: pragmas, the window and the menu, IPC, what a reload puts back
Margin.qml          # the window: side menu, search, grid, editor, pickers, dialogs; grid keys
NoteMenu.qml        # the menu: panel, field, rows, compact editor
Notes.qml           # singleton: `margin serve`, requests, the notes and labels on show
Theme.qml           # singleton: matugen palette, fonts, motion (from Seedling, opaque here)
NoteColors.qml      # singleton: Keep's colours over the theme's surface
views/              # Sidebar, NoteGrid (masonry, spatial keys), NoteCard, NoteBody, Editor
components/         # Chip, ColorPicker, LabelPicker, Fab, Picture, LinkTaps; Label, Icon, IconButton, TextButton, Snackbar, KeyHelp, ConfirmDialog copied from Seedling
icons/              # Material Symbols Rounded (filled, white), from @material-symbols/svg-400 0.48.1, some via quickbar
```

Copied files say so in their header. Don't import from quickbar or Seedling.

## Keys

Everything works from the keyboard, vim style; `?` lists the keys (keep `Margin.bindings` in sync). Grid keys are handled in `Margin.handleKey`; overlays (editor, pickers, dialogs) take focus while open and give it back through `focusGrid()`. Match letters on `event.text`, special keys on `event.key`. Shift+Tab can arrive as Tab with Shift held. No focus rings: the current card is lifted and lightened.

## Design

Keep's layout in the shell's look: side menu pills (`secondary_container`), a pill search field, "Take a note…" bar, cards in masonry columns (pinned under their own heading), an open note as a card over a scrim. Colours from `Theme` only (matugen); note colours from `NoteColors`.
