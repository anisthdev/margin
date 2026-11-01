//! `margin serve`: the store over stdin and stdout, one JSON object a line,
//! for the UI to keep running rather than starting `margin` for every save.
//!
//! Each request names its `op` and carries a `req` number, which comes back
//! on its answer: `{"req": 3, "ok": true, "result": …}` or `{"req": 3, "ok":
//! false, "error": "…"}`. (Not `id`: that's a note's.) Requests are answered
//! in order.

use std::io::{BufRead, Write};

use serde::Deserialize;
use serde_json::{Value, json};

use crate::store::{Patch, Result, Store, View};

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum Op {
    List {
        #[serde(default)]
        view: View,
        label: Option<String>,
        query: Option<String>,
    },
    Get {
        id: String,
    },
    Create {
        #[serde(flatten)]
        patch: Patch,
    },
    Update {
        id: String,
        #[serde(flatten)]
        patch: Patch,
    },
    Trash {
        id: String,
    },
    Restore {
        id: String,
    },
    Delete {
        id: String,
    },
    EmptyTrash,
    Labels,
    RenameLabel {
        from: String,
        to: String,
    },
    /// A picture from a file onto a note; `remove_source` for a temporary one
    Attach {
        id: String,
        path: String,
        #[serde(default)]
        remove_source: bool,
    },
    /// A picture off its note, by the attachment's id
    Detach {
        id: String,
    },
}

fn run(store: &Store, op: Op) -> Result<Value> {
    let value = |v: std::result::Result<Value, serde_json::Error>| v.map_err(|e| e.to_string());
    match op {
        Op::List { view, label, query } => value(serde_json::to_value(store.list(
            view,
            label.as_deref(),
            query.as_deref(),
        )?)),
        Op::Get { id } => value(serde_json::to_value(store.get(&id)?)),
        Op::Create { patch } => value(serde_json::to_value(store.create(patch)?)),
        Op::Update { id, patch } => value(serde_json::to_value(store.update(&id, patch)?)),
        Op::Trash { id } => value(serde_json::to_value(store.trash(&id)?)),
        Op::Restore { id } => value(serde_json::to_value(store.restore(&id)?)),
        Op::Delete { id } => store.delete(&id).map(|()| Value::Null),
        Op::EmptyTrash => store.empty_trash().map(Value::from),
        Op::Labels => value(serde_json::to_value(store.labels()?)),
        Op::RenameLabel { from, to } => store.rename_label(&from, &to).map(Value::from),
        Op::Attach { id, path, remove_source } => {
            value(serde_json::to_value(store.attach(&id, std::path::Path::new(&path), remove_source)?))
        }
        Op::Detach { id } => value(serde_json::to_value(store.detach(&id)?)),
    }
}

pub fn serve(store: &Store) -> Result<()> {
    let stdin = std::io::stdin();
    let mut stdout = std::io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = line.map_err(|e| e.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let answer = match serde_json::from_str::<Value>(&line) {
            Err(e) => json!({ "req": Value::Null, "ok": false, "error": format!("bad request: {e}") }),
            Ok(request) => {
                let req = request.get("req").cloned().unwrap_or(Value::Null);
                match serde_json::from_value::<Op>(request).map_err(|e| format!("bad request: {e}")) {
                    Err(error) => json!({ "req": req, "ok": false, "error": error }),
                    Ok(op) => match run(store, op) {
                        Ok(result) => json!({ "req": req, "ok": true, "result": result }),
                        Err(error) => json!({ "req": req, "ok": false, "error": error }),
                    },
                }
            }
        };
        writeln!(stdout, "{answer}").and_then(|()| stdout.flush()).map_err(|e| e.to_string())?;
    }
    Ok(())
}
