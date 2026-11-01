//! Google Keep's notes, from a Google Takeout export (`Takeout/Keep/`: a JSON
//! file a note, and its pictures beside them), into the store as they were
//! there: text or checklist as Markdown, colour, labels, pinned, archived,
//! trashed, pictures and times. Reminders and sharing aren't in the export.
//!
//! Each note is known by its creation time (to the microsecond), so an
//! import run again, or of a later export, skips what's in already.

use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::store::{Imported, Result, Store};

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct KeepNote {
    title: String,
    text_content: String,
    list_content: Vec<KeepItem>,
    color: String,
    labels: Vec<KeepLabel>,
    is_pinned: bool,
    is_archived: bool,
    is_trashed: bool,
    attachments: Vec<KeepAttachment>,
    annotations: Vec<KeepAnnotation>,
    created_timestamp_usec: i64,
    user_edited_timestamp_usec: i64,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct KeepItem {
    text: String,
    is_checked: bool,
}

#[derive(Deserialize, Default)]
#[serde(default)]
struct KeepLabel {
    name: String,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct KeepAttachment {
    file_path: String,
}

#[derive(Deserialize, Default)]
#[serde(default)]
struct KeepAnnotation {
    url: String,
}

/// Keep's colour names to ours (store::COLORS); CERULEAN is its dark blue.
fn color(keep: &str) -> &'static str {
    match keep {
        "RED" => "red",
        "ORANGE" => "orange",
        "YELLOW" => "yellow",
        "GREEN" => "green",
        "TEAL" => "teal",
        "BLUE" => "blue",
        "CERULEAN" => "darkblue",
        "PURPLE" => "purple",
        "PINK" => "pink",
        "BROWN" => "brown",
        "GRAY" => "gray",
        _ => "",
    }
}

/// A picture's file: as named, else the same name with the other JPEG
/// extension (Takeout doesn't always keep the one it lists).
fn picture(dir: &Path, name: &str) -> Option<PathBuf> {
    let path = dir.join(name);
    if path.exists() {
        return Some(path);
    }
    let stem = Path::new(name).file_stem()?.to_string_lossy().into_owned();
    ["jpg", "jpeg", "png", "JPG", "JPEG", "PNG"].iter().map(|ext| dir.join(format!("{stem}.{ext}"))).find(|p| p.exists())
}

fn convert(dir: &Path, k: KeepNote) -> (Imported, Vec<String>) {
    let mut problems = Vec::new();
    let mut body = if k.list_content.is_empty() {
        k.text_content.trim_end().to_string()
    } else {
        // An item is one line; one that ran over several is joined up
        k.list_content
            .iter()
            .map(|i| format!("- [{}] {}", if i.is_checked { "x" } else { " " }, i.text.split_whitespace().collect::<Vec<_>>().join(" ")))
            .collect::<Vec<_>>()
            .join("\n")
    };
    // Keep's link previews: their links, where the text doesn't have them
    let links: Vec<&str> =
        k.annotations.iter().map(|a| a.url.as_str()).filter(|u| !u.is_empty() && !body.contains(*u)).collect();
    if !links.is_empty() {
        if !body.is_empty() {
            body.push_str("\n\n");
        }
        body.push_str(&links.join("\n"));
    }
    let mut pictures = Vec::new();
    for a in &k.attachments {
        match picture(dir, &a.file_path) {
            Some(p) => pictures.push(p),
            None => problems.push(format!("picture {} not found", a.file_path)),
        }
    }
    if !k.color.is_empty() && k.color != "DEFAULT" && color(&k.color).is_empty() {
        problems.push(format!("colour {} unknown, left default", k.color));
    }
    let created = k.created_timestamp_usec / 1000;
    let updated = (k.user_edited_timestamp_usec / 1000).max(created);
    (
        Imported {
            title: k.title.trim().to_string(),
            body,
            color: color(&k.color).to_string(),
            labels: k.labels.into_iter().map(|l| l.name).collect(),
            pinned: k.is_pinned,
            archived: k.is_archived,
            trashed: k.is_trashed,
            created,
            updated,
            pictures,
        },
        problems,
    )
}

/// Imports a Takeout Keep folder; with `dry_run`, only says what it would
/// do. Prints a summary (no note's content unless `list`).
pub fn import(store: &Store, dir: &Path, dry_run: bool, list: bool) -> Result<()> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .collect();
    files.sort();
    if files.is_empty() {
        return Err(format!("{}: no Keep notes (.json) here; point at Takeout/Keep", dir.display()));
    }
    let (mut added, mut skipped, mut failed, mut pictures) = (0, 0, 0, 0);
    let (mut lists, mut archived, mut trashed, mut pinned) = (0, 0, 0, 0);
    for file in &files {
        let name = file.file_name().unwrap_or_default().to_string_lossy().into_owned();
        let text = match std::fs::read_to_string(file) {
            Ok(t) => t,
            Err(e) => {
                eprintln!("{name}: {e}");
                failed += 1;
                continue;
            }
        };
        let keep: KeepNote = match serde_json::from_str(&text) {
            Ok(k) => k,
            Err(e) => {
                eprintln!("{name}: not a Keep note ({e})");
                failed += 1;
                continue;
            }
        };
        if keep.created_timestamp_usec == 0 {
            eprintln!("{name}: no creation time, skipped");
            failed += 1;
            continue;
        }
        let source = format!("keep:{}", keep.created_timestamp_usec);
        let is_list = !keep.list_content.is_empty();
        let (note, problems) = convert(dir, keep);
        for p in &problems {
            eprintln!("{name}: {p}");
        }
        if store.imported(&source)? {
            skipped += 1;
            continue;
        }
        if !dry_run {
            if let Err(e) = store.import(&source, &note) {
                eprintln!("{name}: {e}");
                failed += 1;
                continue;
            }
        }
        added += 1;
        pictures += note.pictures.len();
        lists += is_list as usize;
        archived += note.archived as usize;
        trashed += note.trashed as usize;
        pinned += (note.pinned && !note.archived && !note.trashed) as usize;
        if list {
            let title = if note.title.is_empty() { note.body.lines().next().unwrap_or("") } else { &note.title };
            println!("  {}{}", title.chars().take(60).collect::<String>(), if note.pictures.is_empty() { String::new() } else { format!("  [{} picture(s)]", note.pictures.len()) });
        }
    }
    println!(
        "{} {added} notes ({lists} checklists, {pictures} pictures; {pinned} pinned, {archived} archived, {trashed} in the trash); {skipped} already in, {failed} failed",
        if dry_run { "Would import" } else { "Imported" }
    );
    Ok(())
}
