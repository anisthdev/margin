//! margin: notes, kept in SQLite. The command line for scripts and the
//! shell, and `margin serve` for the app's window (see serve.rs). In time,
//! the daemon that syncs them.

mod keep;
mod serve;
mod store;

use std::io::Read;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use serde::Serialize;
use store::{Patch, Store, View};

#[derive(Parser)]
#[command(version, about = "Notes, kept in SQLite")]
struct Cli {
    /// The database (default: $MARGIN_DB, else ~/.local/share/margin/margin.db)
    #[arg(long, global = true)]
    db: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// List notes: id and title, or all of them as JSON
    List {
        #[arg(long, value_enum, default_value = "notes")]
        view: View,
        #[arg(long)]
        label: Option<String>,
        /// Only notes whose title, body or labels contain this
        #[arg(long, short)]
        query: Option<String>,
        #[arg(long)]
        json: bool,
    },
    /// Print a note: its Markdown, or all of it as JSON
    Show {
        id: String,
        #[arg(long)]
        json: bool,
    },
    /// Make a note; its body is BODY, else stdin when that isn't a terminal.
    /// Prints its id.
    New {
        #[arg(long, short)]
        title: Option<String>,
        #[arg(long, short)]
        label: Vec<String>,
        /// May start with "-", as a checklist does
        #[arg(allow_hyphen_values = true)]
        body: Option<String>,
    },
    /// Change a note from a JSON object on stdin (title, body, color, labels,
    /// pinned, archived; what's left out stays)
    Edit { id: String },
    /// Move a note to the trash
    Trash { id: String },
    /// Take a note out of the trash
    Restore { id: String },
    /// Delete a note for good
    Delete { id: String },
    /// Delete everything in the trash for good
    EmptyTrash,
    /// Labels in use, with how many notes have each
    Labels,
    /// Rename a label on every note (an empty name removes it)
    RenameLabel { from: String, to: String },
    /// Give a note a picture (PNG, JPEG, GIF or WebP), copied in
    Attach { id: String, file: PathBuf },
    /// Take a picture off its note, by the id `show --json` gives it
    Detach { id: String },
    /// Import Google Keep's notes from a Takeout export (its Takeout/Keep
    /// folder). Notes imported before are skipped, so it can run again.
    ImportKeep {
        dir: PathBuf,
        /// Only say what would be imported
        #[arg(long, short = 'n')]
        dry_run: bool,
        /// Also list the notes, by title
        #[arg(long, short)]
        list: bool,
    },
    /// Answer JSON requests on stdin, one a line (for the app)
    Serve,
    /// Print the database's path
    Path,
}

fn print_json(value: &impl Serialize) -> Result<(), String> {
    println!("{}", serde_json::to_string_pretty(value).map_err(|e| e.to_string())?);
    Ok(())
}

fn stdin() -> Result<String, String> {
    let mut text = String::new();
    std::io::stdin().read_to_string(&mut text).map_err(|e| e.to_string())?;
    Ok(text)
}

fn run(cli: Cli) -> Result<(), String> {
    let path = cli.db.unwrap_or_else(store::default_path);
    if let Command::Path = cli.command {
        println!("{}", path.display());
        return Ok(());
    }
    let store = Store::open(&path)?;
    match cli.command {
        Command::List { view, label, query, json } => {
            let notes = store.list(view, label.as_deref(), query.as_deref())?;
            if json {
                return print_json(&notes);
            }
            for n in notes {
                let title = if n.title.is_empty() { n.body.lines().next().unwrap_or("") } else { &n.title };
                println!("{}  {}{}", n.id, if n.pinned { "📌 " } else { "" }, title);
            }
        }
        Command::Show { id, json } => {
            let note = store.get(&id)?;
            if json {
                return print_json(&note);
            }
            if !note.title.is_empty() {
                println!("# {}\n", note.title);
            }
            println!("{}", note.body);
        }
        Command::New { title, label, body } => {
            use std::io::IsTerminal;
            let body = match body {
                Some(body) => Some(body),
                None if !std::io::stdin().is_terminal() => Some(stdin()?.trim_end().to_string()),
                None => None,
            };
            let labels = (!label.is_empty()).then_some(label);
            let note = store.create(Patch { title, body, labels, ..Default::default() })?;
            println!("{}", note.id);
        }
        Command::Edit { id } => {
            let patch: Patch = serde_json::from_str(&stdin()?).map_err(|e| format!("bad JSON: {e}"))?;
            print_json(&store.update(&id, patch)?)?;
        }
        Command::Trash { id } => {
            store.trash(&id)?;
        }
        Command::Restore { id } => {
            store.restore(&id)?;
        }
        Command::Delete { id } => store.delete(&id)?,
        Command::EmptyTrash => println!("{} deleted", store.empty_trash()?),
        Command::Labels => {
            for l in store.labels()? {
                println!("{}\t{}", l.count, l.name);
            }
        }
        Command::RenameLabel { from, to } => println!("{} notes changed", store.rename_label(&from, &to)?),
        Command::Attach { id, file } => {
            let note = store.attach(&id, &file, false)?;
            println!("{}", note.images.last().map(|i| i.id.as_str()).unwrap_or(""));
        }
        Command::Detach { id } => {
            store.detach(&id)?;
        }
        Command::ImportKeep { dir, dry_run, list } => keep::import(&store, &dir, dry_run, list)?,
        Command::Serve => serve::serve(&store)?,
        Command::Path => unreachable!(),
    }
    Ok(())
}

fn main() -> ExitCode {
    match run(Cli::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("margin: {e}");
            ExitCode::FAILURE
        }
    }
}
