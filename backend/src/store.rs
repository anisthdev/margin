//! The notes, in one SQLite database. Built for the sync to come: every note
//! has a permanent id (a UUIDv7, so ids sort by creation), records when and
//! on which device it last changed, and is never removed outright — deleting
//! one clears it and leaves a tombstone, so the deletion can reach other
//! devices too.
//!
//! Pictures are attachments, as Keep's are: each its own row (with its own
//! id, time and tombstone, for the sync) and a file in `attachments/` beside
//! the database, named by its id.

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OptionalExtension, Row, params};
use serde::{Deserialize, Serialize};

/// Notes left in the trash this long are deleted for good, as Keep does.
const TRASH_DAYS: i64 = 7;

/// Keep's note colours, by Keep's own names; "" is the default.
pub const COLORS: &[&str] = &[
    "", "red", "orange", "yellow", "green", "teal", "blue", "darkblue", "purple", "pink", "brown", "gray",
];

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS notes (
    id         TEXT PRIMARY KEY,
    title      TEXT NOT NULL DEFAULT '',
    body       TEXT NOT NULL DEFAULT '',  -- Markdown
    color      TEXT NOT NULL DEFAULT '',
    labels     TEXT NOT NULL DEFAULT '[]', -- JSON array of names
    pinned     INTEGER NOT NULL DEFAULT 0,
    archived   INTEGER NOT NULL DEFAULT 0,
    trashed_at INTEGER,                    -- ms; NULL unless in the trash
    deleted    INTEGER NOT NULL DEFAULT 0, -- a tombstone: cleared, kept for sync
    created_at INTEGER NOT NULL,           -- ms since the epoch
    updated_at INTEGER NOT NULL,
    device     TEXT NOT NULL               -- the device that made the last change
);
CREATE INDEX IF NOT EXISTS notes_updated ON notes (updated_at);
CREATE TABLE IF NOT EXISTS attachments (
    id         TEXT PRIMARY KEY,
    note_id    TEXT NOT NULL,
    file       TEXT NOT NULL,              -- its name in attachments/
    mime       TEXT NOT NULL,
    deleted    INTEGER NOT NULL DEFAULT 0, -- a tombstone, the file gone
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    device     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS attachments_note ON attachments (note_id);
-- Notes brought in from elsewhere (Keep), by where they came from, so an
-- import run again skips them
CREATE TABLE IF NOT EXISTS imports (
    source  TEXT PRIMARY KEY,
    note_id TEXT NOT NULL
);
";

/// A note from elsewhere, with its own times, for `Store::import`.
#[derive(Debug, Clone, Default)]
pub struct Imported {
    pub title: String,
    pub body: String,
    pub color: String,
    pub labels: Vec<String>,
    pub pinned: bool,
    pub archived: bool,
    pub trashed: bool,
    pub created: i64,
    pub updated: i64,
    pub pictures: Vec<PathBuf>,
}

/// The pictures a note can have, by their first bytes: (MIME type, extension).
fn image_type(head: &[u8]) -> Option<(&'static str, &'static str)> {
    match head {
        [0x89, b'P', b'N', b'G', ..] => Some(("image/png", "png")),
        [0xff, 0xd8, 0xff, ..] => Some(("image/jpeg", "jpg")),
        [b'G', b'I', b'F', b'8', ..] => Some(("image/gif", "gif")),
        [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] => Some(("image/webp", "webp")),
        _ => None,
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Note {
    pub id: String,
    pub title: String,
    pub body: String,
    pub color: String,
    pub labels: Vec<String>,
    pub pinned: bool,
    pub archived: bool,
    pub trashed: bool,
    pub created: i64,
    pub updated: i64,
    pub images: Vec<Image>,
}

/// A note's picture: its attachment's id and the file to show.
#[derive(Debug, Clone, Serialize)]
pub struct Image {
    pub id: String,
    pub path: String,
}

/// Which notes a list shows, as Keep's side menu splits them.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize, clap::ValueEnum)]
#[serde(rename_all = "lowercase")]
pub enum View {
    #[default]
    Notes,
    Archive,
    Trash,
}

/// Fields to change on a note; what's left out stays as it is.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct Patch {
    pub title: Option<String>,
    pub body: Option<String>,
    pub color: Option<String>,
    pub labels: Option<Vec<String>>,
    pub pinned: Option<bool>,
    pub archived: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct Label {
    pub name: String,
    pub count: usize,
}

pub type Result<T> = std::result::Result<T, String>;

pub struct Store {
    db: Connection,
    device: String,
    // Attachments' files
    files: PathBuf,
}

pub fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// $MARGIN_DB, else $XDG_DATA_HOME/margin/margin.db.
pub fn default_path() -> PathBuf {
    if let Some(path) = std::env::var_os("MARGIN_DB") {
        return path.into();
    }
    let data = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/share"));
    data.join("margin/margin.db")
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

const COLUMNS: &str = "id, title, body, color, labels, pinned, archived, trashed_at, created_at, updated_at";

fn note(row: &Row) -> rusqlite::Result<Note> {
    let labels: String = row.get(4)?;
    Ok(Note {
        id: row.get(0)?,
        title: row.get(1)?,
        body: row.get(2)?,
        color: row.get(3)?,
        labels: serde_json::from_str(&labels).unwrap_or_default(),
        pinned: row.get(5)?,
        archived: row.get(6)?,
        trashed: row.get::<_, Option<i64>>(7)?.is_some(),
        created: row.get(8)?,
        updated: row.get(9)?,
        images: Vec::new(),
    })
}

/// Labels trimmed, without empties or repeats (ignoring case), in order.
fn clean_labels(labels: Vec<String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for label in labels {
        let label = label.trim().to_string();
        if !label.is_empty() && !out.iter().any(|l| l.to_lowercase() == label.to_lowercase()) {
            out.push(label);
        }
    }
    out
}

impl Store {
    pub fn open(path: &Path) -> Result<Store> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        let db = Connection::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
        // WAL, so the UI's `margin serve` and a CLI call can share it
        db.pragma_update(None, "journal_mode", "wal").map_err(err)?;
        db.busy_timeout(std::time::Duration::from_secs(5)).map_err(err)?;
        db.execute_batch(SCHEMA).map_err(err)?;
        let device = match db
            .query_row("SELECT value FROM meta WHERE key = 'device'", [], |r| r.get(0))
            .optional()
            .map_err(err)?
        {
            Some(device) => device,
            None => {
                let device = uuid::Uuid::now_v7().to_string();
                db.execute("INSERT INTO meta (key, value) VALUES ('device', ?1)", [&device]).map_err(err)?;
                device
            }
        };
        let files = path.with_file_name("attachments");
        let store = Store { db, device, files };
        store.purge_trash()?;
        Ok(store)
    }

    /// Notes in the trash for longer than TRASH_DAYS become tombstones.
    fn purge_trash(&self) -> Result<()> {
        let cutoff = now() - TRASH_DAYS * 24 * 60 * 60 * 1000;
        let ids: Vec<String> = self
            .db
            .prepare("SELECT id FROM notes WHERE deleted = 0 AND trashed_at < ?1")
            .and_then(|mut s| s.query_map([cutoff], |r| r.get(0))?.collect())
            .map_err(err)?;
        for id in ids {
            self.delete(&id)?;
        }
        Ok(())
    }

    /// Pinned first, then the most recently changed.
    pub fn list(&self, view: View, label: Option<&str>, query: Option<&str>) -> Result<Vec<Note>> {
        let filter = match view {
            View::Notes => "trashed_at IS NULL AND archived = 0",
            View::Archive => "trashed_at IS NULL AND archived = 1",
            View::Trash => "trashed_at IS NOT NULL",
        };
        let sql = format!(
            "SELECT {COLUMNS} FROM notes WHERE deleted = 0 AND {filter} ORDER BY pinned DESC, updated_at DESC"
        );
        let mut stmt = self.db.prepare(&sql).map_err(err)?;
        let mut notes: Vec<Note> = stmt.query_map([], note).and_then(|rows| rows.collect()).map_err(err)?;
        for n in &mut notes {
            n.images = self.images(&n.id)?;
        }
        let query = query.map(str::trim).filter(|q| !q.is_empty()).map(str::to_lowercase);
        let label = label.map(str::to_lowercase);
        Ok(notes
            .into_iter()
            .filter(|n| label.as_ref().is_none_or(|l| n.labels.iter().any(|x| x.to_lowercase() == *l)))
            .filter(|n| {
                query.as_ref().is_none_or(|q| {
                    n.title.to_lowercase().contains(q)
                        || n.body.to_lowercase().contains(q)
                        || n.labels.iter().any(|l| l.to_lowercase().contains(q))
                })
            })
            .collect())
    }

    pub fn get(&self, id: &str) -> Result<Note> {
        let mut n = self
            .db
            .query_row(&format!("SELECT {COLUMNS} FROM notes WHERE id = ?1 AND deleted = 0"), [id], note)
            .optional()
            .map_err(err)?
            .ok_or_else(|| format!("no note {id}"))?;
        n.images = self.images(id)?;
        Ok(n)
    }

    /// A note's pictures, oldest first.
    fn images(&self, note_id: &str) -> Result<Vec<Image>> {
        self.db
            .prepare_cached("SELECT id, file FROM attachments WHERE note_id = ?1 AND deleted = 0 ORDER BY id")
            .and_then(|mut s| {
                s.query_map([note_id], |r| {
                    let file: String = r.get(1)?;
                    Ok(Image { id: r.get(0)?, path: self.files.join(file).to_string_lossy().into_owned() })
                })?
                .collect()
            })
            .map_err(err)
    }

    /// Gives a note a picture, copied in from `source` (moved, with
    /// `remove_source`, as from a temporary file).
    pub fn attach(&self, note_id: &str, source: &Path, remove_source: bool) -> Result<Note> {
        if self.get(note_id)?.trashed {
            return Err("the note is in the trash".into());
        }
        let data = std::fs::read(source).map_err(|e| format!("{}: {e}", source.display()))?;
        let (mime, ext) = image_type(&data).ok_or_else(|| format!("{}: not a PNG, JPEG, GIF or WebP picture", source.display()))?;
        std::fs::create_dir_all(&self.files).map_err(|e| format!("{}: {e}", self.files.display()))?;
        let id = uuid::Uuid::now_v7().to_string();
        let file = format!("{id}.{ext}");
        let target = self.files.join(&file);
        std::fs::write(&target, &data).map_err(|e| format!("{}: {e}", target.display()))?;
        let t = now();
        self.db
            .execute(
                "INSERT INTO attachments (id, note_id, file, mime, created_at, updated_at, device)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6)",
                params![id, note_id, file, mime, t, self.device],
            )
            .map_err(err)?;
        self.touch(note_id)?;
        if remove_source {
            let _ = std::fs::remove_file(source);
        }
        self.get(note_id)
    }

    /// Whether a note from `source` was imported already.
    pub fn imported(&self, source: &str) -> Result<bool> {
        self.db
            .query_row("SELECT 1 FROM imports WHERE source = ?1", [source], |_| Ok(()))
            .optional()
            .map(|r| r.is_some())
            .map_err(err)
    }

    /// Adds a note from elsewhere as it was there, its times included; one
    /// from a `source` imported before is skipped (None). All or nothing.
    pub fn import(&self, source: &str, n: &Imported) -> Result<Option<Note>> {
        if self.imported(source)? {
            return Ok(None);
        }
        if !COLORS.contains(&n.color.as_str()) {
            return Err(format!("no colour {:?}", n.color));
        }
        // Pictures read and checked before anything is written
        let mut pictures = Vec::new();
        for path in &n.pictures {
            let data = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
            let (mime, ext) = image_type(&data).ok_or_else(|| format!("{}: not a PNG, JPEG, GIF or WebP picture", path.display()))?;
            pictures.push((data, mime, ext));
        }
        let id = uuid::Uuid::now_v7().to_string();
        let mut written = Vec::new();
        let result = (|| -> Result<()> {
            self.db.execute_batch("BEGIN").map_err(err)?;
            self.db
                .execute(
                    "INSERT INTO notes (id, title, body, color, labels, pinned, archived, trashed_at, created_at, updated_at, device)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
                    params![
                        id,
                        n.title,
                        n.body,
                        n.color,
                        serde_json::to_string(&clean_labels(n.labels.clone())).map_err(err)?,
                        n.pinned && !n.archived && !n.trashed,
                        n.archived,
                        // The trash's seven days start now, not when it was trashed there
                        n.trashed.then(now),
                        n.created,
                        n.updated,
                        self.device
                    ],
                )
                .map_err(err)?;
            if !pictures.is_empty() {
                std::fs::create_dir_all(&self.files).map_err(|e| format!("{}: {e}", self.files.display()))?;
            }
            for (data, mime, ext) in &pictures {
                let attachment = uuid::Uuid::now_v7().to_string();
                let file = format!("{attachment}.{ext}");
                let target = self.files.join(&file);
                std::fs::write(&target, data).map_err(|e| format!("{}: {e}", target.display()))?;
                written.push(target);
                self.db
                    .execute(
                        "INSERT INTO attachments (id, note_id, file, mime, created_at, updated_at, device)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6)",
                        params![attachment, id, file, mime, n.updated, self.device],
                    )
                    .map_err(err)?;
            }
            self.db.execute("INSERT INTO imports (source, note_id) VALUES (?1, ?2)", params![source, id]).map_err(err)?;
            self.db.execute_batch("COMMIT").map_err(err)
        })();
        if let Err(e) = result {
            let _ = self.db.execute_batch("ROLLBACK");
            for f in written {
                let _ = std::fs::remove_file(f);
            }
            return Err(e);
        }
        // Not get(): a note imported straight into the trash is still there
        let mut note = self
            .db
            .query_row(&format!("SELECT {COLUMNS} FROM notes WHERE id = ?1"), [&id], note)
            .map_err(err)?;
        note.images = self.images(&id)?;
        Ok(Some(note))
    }

    /// Takes a picture off its note, for good.
    pub fn detach(&self, attachment_id: &str) -> Result<Note> {
        let (note_id, file): (String, String) = self
            .db
            .query_row("SELECT note_id, file FROM attachments WHERE id = ?1 AND deleted = 0", [attachment_id], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
            .optional()
            .map_err(err)?
            .ok_or_else(|| format!("no picture {attachment_id}"))?;
        self.drop_attachment(attachment_id, &file)?;
        self.touch(&note_id)?;
        self.get(&note_id)
    }

    fn drop_attachment(&self, id: &str, file: &str) -> Result<()> {
        self.db
            .execute(
                "UPDATE attachments SET deleted = 1, updated_at = ?2, device = ?3 WHERE id = ?1",
                params![id, now(), self.device],
            )
            .map_err(err)?;
        let _ = std::fs::remove_file(self.files.join(file));
        Ok(())
    }

    /// Marks a note changed, here, now: its pictures changed.
    fn touch(&self, note_id: &str) -> Result<()> {
        self.db
            .execute("UPDATE notes SET updated_at = ?2, device = ?3 WHERE id = ?1", params![note_id, now(), self.device])
            .map_err(err)?;
        Ok(())
    }

    pub fn create(&self, patch: Patch) -> Result<Note> {
        let id = uuid::Uuid::now_v7().to_string();
        let t = now();
        self.db
            .execute(
                "INSERT INTO notes (id, created_at, updated_at, device) VALUES (?1, ?2, ?2, ?3)",
                params![id, t, self.device],
            )
            .map_err(err)?;
        self.update(&id, patch)
    }

    /// Changes what the patch sets; the note's time and device change only
    /// when something did.
    pub fn update(&self, id: &str, patch: Patch) -> Result<Note> {
        let old = self.get(id)?;
        if let Some(color) = &patch.color {
            if !COLORS.contains(&color.as_str()) {
                return Err(format!("no colour {color:?} (one of: {})", COLORS[1..].join(", ")));
            }
        }
        // As Keep: archiving unpins, and pinning an archived note brings it back
        let mut pinned = patch.pinned.unwrap_or(old.pinned);
        let mut archived = patch.archived.unwrap_or(old.archived);
        if patch.archived == Some(true) && patch.pinned.is_none() {
            pinned = false;
        }
        if patch.pinned == Some(true) && patch.archived.is_none() {
            archived = false;
        }
        let new = Note {
            title: patch.title.unwrap_or(old.title.clone()),
            body: patch.body.unwrap_or(old.body.clone()),
            color: patch.color.unwrap_or(old.color.clone()),
            labels: patch.labels.map(clean_labels).unwrap_or(old.labels.clone()),
            pinned,
            archived,
            ..old.clone()
        };
        if (&new.title, &new.body, &new.color, &new.labels, new.pinned, new.archived)
            == (&old.title, &old.body, &old.color, &old.labels, old.pinned, old.archived)
        {
            return Ok(old);
        }
        self.db
            .execute(
                "UPDATE notes SET title = ?2, body = ?3, color = ?4, labels = ?5, pinned = ?6, archived = ?7,
                 updated_at = ?8, device = ?9 WHERE id = ?1",
                params![
                    id,
                    new.title,
                    new.body,
                    new.color,
                    serde_json::to_string(&new.labels).map_err(err)?,
                    new.pinned,
                    new.archived,
                    now(),
                    self.device
                ],
            )
            .map_err(err)?;
        self.get(id)
    }

    fn set_trashed(&self, id: &str, trashed: bool) -> Result<Note> {
        self.get(id)?;
        self.db
            .execute(
                "UPDATE notes SET trashed_at = ?2, pinned = CASE WHEN ?2 IS NULL THEN pinned ELSE 0 END,
                 updated_at = ?3, device = ?4 WHERE id = ?1",
                params![id, trashed.then(now), now(), self.device],
            )
            .map_err(err)?;
        self.get(id)
    }

    pub fn trash(&self, id: &str) -> Result<Note> {
        self.set_trashed(id, true)
    }

    pub fn restore(&self, id: &str) -> Result<Note> {
        self.set_trashed(id, false)
    }

    /// For good: the note is cleared, leaving its id as a tombstone.
    pub fn delete(&self, id: &str) -> Result<()> {
        let changed = self
            .db
            .execute(
                "UPDATE notes SET title = '', body = '', color = '', labels = '[]', pinned = 0, archived = 0,
                 trashed_at = NULL, deleted = 1, updated_at = ?2, device = ?3 WHERE id = ?1 AND deleted = 0",
                params![id, now(), self.device],
            )
            .map_err(err)?;
        if changed == 0 {
            return Err(format!("no note {id}"));
        }
        let files: Vec<(String, String)> = self
            .db
            .prepare("SELECT id, file FROM attachments WHERE note_id = ?1 AND deleted = 0")
            .and_then(|mut s| s.query_map([id], |r| Ok((r.get(0)?, r.get(1)?)))?.collect())
            .map_err(err)?;
        for (attachment, file) in files {
            self.drop_attachment(&attachment, &file)?;
        }
        Ok(())
    }

    pub fn empty_trash(&self) -> Result<usize> {
        let notes = self.list(View::Trash, None, None)?;
        for n in &notes {
            self.delete(&n.id)?;
        }
        Ok(notes.len())
    }

    /// Every label in use, outside the trash, by name.
    pub fn labels(&self) -> Result<Vec<Label>> {
        let mut labels: Vec<Label> = Vec::new();
        for view in [View::Notes, View::Archive] {
            for n in self.list(view, None, None)? {
                for name in n.labels {
                    match labels.iter_mut().find(|l| l.name.to_lowercase() == name.to_lowercase()) {
                        Some(l) => l.count += 1,
                        None => labels.push(Label { name, count: 1 }),
                    }
                }
            }
        }
        labels.sort_by_key(|l| l.name.to_lowercase());
        Ok(labels)
    }

    /// Renames a label on every note; an empty name takes it off them.
    pub fn rename_label(&self, from: &str, to: &str) -> Result<usize> {
        let from = from.to_lowercase();
        let mut changed = 0;
        for view in [View::Notes, View::Archive, View::Trash] {
            for n in self.list(view, None, None)? {
                if !n.labels.iter().any(|l| l.to_lowercase() == from) {
                    continue;
                }
                let labels = n
                    .labels
                    .iter()
                    .map(|l| if l.to_lowercase() == from { to.to_string() } else { l.clone() })
                    .collect();
                self.update(&n.id, Patch { labels: Some(labels), ..Default::default() })?;
                changed += 1;
            }
        }
        Ok(changed)
    }
}
