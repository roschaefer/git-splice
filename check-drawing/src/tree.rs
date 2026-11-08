//! A splice tree: the monorepo and each splice in it, one row each, as `tree`
//! prints folders. It isn't drawn by hand but written from the repository,
//! so a check of one only asks whether it's still what the repository gives.
//! See README.md.

use crate::check::Labels;
use crate::diagram::{cell_lines, diagram_xml, Diagram};
use crate::history::History;
use std::collections::HashMap;

const PULLED: &str = "#0070E0";
const CARRIED: &str = "#E07000";
const CONFLICT: &str = "#D00000";
const FONT: &str = "fontFamily=Roboto Mono,monospace;";
const ROW: f64 = 60.0;
const CIRCLE: f64 = 36.0;
const GAP: f64 = 26.0;

/// Whether drawing <d> is a splice tree: its root text is styled tree=1.
pub fn is_tree(d: &Diagram) -> bool {
    d.cells.iter().any(|c| !c.edge && c.style.has("tree=1"))
}

/// Which of the lane drawing's marks a tree shows, each with a sample in
/// its legend.
#[derive(Default)]
pub struct Marks {
    pub pulled: bool,
    pub carried: bool,
}

impl Marks {
    /// The marks drawing <d>'s legend has samples of.
    fn of(d: &Diagram) -> Marks {
        let sampled = |color: &str| {
            d.cells
                .iter()
                .any(|c| d.in_legend(c) && c.style.color("strokeColor", "black") == color)
        };
        Marks {
            pulled: sampled(PULLED),
            carried: sampled(CARRIED),
        }
    }

    /// The options of `check-drawing tree` that give these marks.
    fn options(&self) -> String {
        let mut options = String::new();
        if self.pulled {
            options.push_str(" --mark pulled");
        }
        if self.carried {
            options.push_str(" --mark carried");
        }
        options
    }
}

/// A commit a row shows: its label, and the color of its outline, if any.
struct Circle {
    label: String,
    color: Option<&'static str>,
}

/// A row: the splice's folder, relative to the row it hangs from, how deep
/// it hangs, its synced commit (the root's: HEAD), R, where the splice has
/// commits of its own, and the commit a conflicted pull of it merges in.
struct Row {
    folder: String,
    depth: usize,
    synced: Option<Circle>,
    r: Option<Circle>,
    theirs: Option<Circle>,
}

/// The rows of the monorepo in the current folder, with marks <marks>, each
/// commit labelled as <labels> name it, else by its subject.
fn rows(git: &History, labels: &Labels, marks: &Marks) -> Result<Vec<Row>, Vec<String>> {
    let head = git.head();
    let mut splices = git.splices();
    // As `tree` lists folders: each right after the one around it.
    splices.sort_by(|a, b| a.split('/').cmp(b.split('/')));
    let truths: HashMap<String, _> = splices.iter().map(|s| (s.clone(), git.truth(s))).collect();
    // The splice a pull merges into with a conflict, and what it merges in.
    let conflict = git
        .rev_parse("CHERRY_PICK_HEAD")
        .and_then(|pick| git.pulls_in(&pick).into_iter().next())
        .and_then(|(file, _, now)| Some((file.strip_suffix("/.splice")?.to_string(), now)));

    let mut drawn = vec![head.clone()];
    for truth in truths.values() {
        drawn.extend([truth.u.clone(), truth.r.clone()]);
    }
    let (pulls, brought) = git.pulls_among(&drawn);
    let (walked, copied) = git.walked_and_copied(truths.values());

    // The first label, by name, that names a commit.
    let mut given: HashMap<String, String> = HashMap::new();
    let mut names: Vec<(&String, &String)> = labels.revs.iter().collect();
    names.sort();
    for (label, rev) in names.into_iter().rev() {
        if let Some(commit) = git.commit(rev) {
            given.insert(commit, label.clone());
        }
    }
    // Each commit of the monorepo's history, by what its copies share with it.
    let originals: HashMap<String, String> = git
        .log_with_copy_keys(&["--first-parent".to_string(), "HEAD".to_string()])
        .iter()
        .map(|c| (git.copy_key(c), c.clone()))
        .collect();
    let by_subject = |commit: &str| {
        let subject = git
            .log(&["--no-walk".to_string(), commit.to_string()])
            .first()
            .map(|s| s.subject.clone())
            .unwrap_or_default();
        match subject.split_once(": ") {
            Some((label, _)) => label.to_string(),
            None => subject,
        }
    };
    let label = |commit: &str| {
        given
            .get(commit)
            .cloned()
            .unwrap_or_else(|| by_subject(commit))
    };
    // R's copy of a commit is labelled after it, with a '.
    let copy_label = |commit: &str| {
        given.get(commit).cloned().unwrap_or_else(|| {
            let original = originals.get(&git.copy_key(commit));
            format!("{}'", label(original.map_or(commit, String::as_str)))
        })
    };
    let pulled = |commit: &str| pulls.contains(commit) || brought.contains(commit);
    let mut errors = Vec::new();
    let mut circle = |label: String, pulled: bool, carried: bool| {
        let (pulled, carried) = (pulled && marks.pulled, carried && marks.carried);
        if pulled && carried {
            errors.push(format!(
                "{label} is both pulled and carried over, and one outline can't show both: leave out --mark pulled or --mark carried"
            ));
        }
        let color = if pulled {
            Some(PULLED)
        } else if carried {
            Some(CARRIED)
        } else {
            None
        };
        Circle { label, color }
    };

    let mut rows = vec![Row {
        folder: "monorepo".to_string(),
        depth: 0,
        synced: Some(circle(
            label(&head),
            pulled(&head),
            walked.contains(&head) && copied.contains(&git.copy_key(&head)),
        )),
        r: None,
        theirs: None,
    }];
    for splice in &splices {
        let truth = &truths[splice];
        let around: Vec<&String> = splices
            .iter()
            .filter(|p| splice.starts_with(&format!("{p}/")))
            .collect();
        let folder = around
            .iter()
            .max_by_key(|p| p.len())
            .map_or(splice.as_str(), |p| &splice[p.len() + 1..]);
        let synced =
            (!truth.u.is_empty()).then(|| circle(label(&truth.u), pulled(&truth.u), false));
        let r = (!truth.r.is_empty() && truth.r != truth.u).then(|| {
            circle(
                copy_label(&truth.r),
                pulled(&truth.r),
                !git.is_ancestor(&truth.r, &truth.s),
            )
        });
        let theirs = conflict
            .as_ref()
            .filter(|(path, _)| path == splice)
            .map(|(_, commit)| Circle {
                label: label(commit),
                color: Some(CONFLICT),
            });
        rows.push(Row {
            folder: format!("{folder}/"),
            depth: around.len() + 1,
            synced,
            r,
            theirs,
        });
    }
    if errors.is_empty() {
        Ok(rows)
    } else {
        Err(errors)
    }
}

/// <text> as an XML attribute's value.
fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('"', "&quot;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// The draw.io diagram of rows <rows>, with a legend of <marks>.
fn render(rows: &[Row], marks: &Marks) -> String {
    let mut cells = String::new();
    let mut shape = |id: &str, value: &str, style: &str, at: (f64, f64, f64, f64), parent: &str| {
        let (x, y, w, h) = at;
        cells.push_str(&format!(
            "<mxCell id=\"{id}\" parent=\"{parent}\" style=\"{}\" value=\"{}\" vertex=\"1\"><mxGeometry x=\"{x}\" y=\"{y}\" width=\"{w}\" height=\"{h}\" as=\"geometry\"/></mxCell>\n",
            escape(style),
            escape(value)
        ));
    };
    let commit = format!("ellipse;aspect=fixed;strokeWidth=2;fontSize=14;{FONT}");
    let outline = |color: Option<&str>| {
        color.map_or(String::new(), |c| format!("strokeColor={c};strokeWidth=3;"))
    };
    // The head of the row last drawn at each depth, and its x: what the
    // rows below it hang from.
    let mut heads: Vec<(String, f64)> = Vec::new();
    let mut edges = String::new();
    for (i, row) in rows.iter().enumerate() {
        let y = i as f64 * ROW;
        let x = match row.depth {
            0 => 0.0,
            depth => heads.get(depth - 1).map_or(0.0, |h| h.1) + CIRCLE / 2.0 + 18.0,
        };
        let mut head = None;
        let mut next = x;
        if let Some(synced) = &row.synced {
            let id = format!("s{i}");
            let style = format!("{commit}{}", outline(synced.color));
            shape(&id, &synced.label, &style, (x, y, CIRCLE, CIRCLE), "1");
            head = Some((id, x));
            next += CIRCLE + GAP;
        }
        if let Some(r) = &row.r {
            let dots = format!("text;align=center;verticalAlign=middle;fontSize=16;{FONT}");
            shape(
                &format!("dots{i}"),
                "…",
                &dots,
                (next - GAP + 2.0, y, GAP - 4.0, CIRCLE),
                "1",
            );
            let id = format!("r{i}");
            let style = format!("{commit}dashed=1;{}", outline(r.color));
            shape(&id, &r.label, &style, (next, y, CIRCLE, CIRCLE), "1");
            head = Some((id, next));
            next += CIRCLE + GAP;
        }
        if let Some((above, _)) = row.depth.checked_sub(1).and_then(|d| heads.get(d)) {
            let into = if row.synced.is_some() { "s" } else { "r" };
            edges.push_str(&format!(
                "<mxCell id=\"c{i}\" edge=\"1\" parent=\"1\" source=\"{}\" target=\"{into}{i}\" style=\"endArrow=none;strokeWidth=1.5;edgeStyle=orthogonalEdgeStyle;rounded=0;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;\"><mxGeometry relative=\"1\" as=\"geometry\"/></mxCell>\n",
                above
            ));
        }
        if let Some(theirs) = &row.theirs {
            let style = format!("{commit}{}", outline(theirs.color));
            shape(
                &format!("t{i}"),
                &theirs.label,
                &style,
                (next, y, CIRCLE, CIRCLE),
                "1",
            );
            next += CIRCLE + GAP;
        }
        let mut style = format!("text;align=left;verticalAlign=middle;fontSize=15;{FONT}");
        let mut value = row.folder.clone();
        if row.theirs.is_some() {
            style.push_str(&format!("fontColor={CONFLICT};fontStyle=1;"));
            value.push_str("   conflict");
        }
        if row.depth == 0 {
            style.push_str("tree=1;");
        }
        let width = row.folder.chars().count() as f64 * 9.0 + 120.0;
        let text_x = if next == x { x } else { next - GAP + 10.0 };
        shape(
            &format!("f{i}"),
            &value,
            &style,
            (text_x, y, width, CIRCLE),
            "1",
        );
        if let Some(head) = head {
            heads.truncate(row.depth);
            heads.push(head);
        }
    }
    let mut items: Vec<(&str, &str)> = Vec::new();
    if marks.pulled {
        items.push((PULLED, "pulled"));
    }
    if marks.carried {
        items.push((CARRIED, "carried over"));
    }
    if rows.iter().any(|r| r.theirs.is_some()) {
        items.push((CONFLICT, "merged in, conflicts"));
    }
    if !items.is_empty() {
        let height = 20.0 + 30.0 * items.len().div_ceil(2) as f64;
        let frame =
            "rounded=1;arcSize=8;fillColor=none;strokeColor=#999999;strokeWidth=1;legend=1;";
        shape(
            "legend",
            "",
            frame,
            (0.0, rows.len() as f64 * ROW + 10.0, 470.0, height),
            "1",
        );
        for (k, (color, text)) in items.iter().enumerate() {
            let (lx, ly) = (12.0 + (k % 2) as f64 * 230.0, 10.0 + (k / 2) as f64 * 30.0);
            let sample = format!(
                "ellipse;aspect=fixed;strokeWidth=2;{}",
                outline(Some(color))
            );
            shape(
                &format!("lg{k}"),
                "",
                &sample,
                (lx, ly, 24.0, 24.0),
                "legend",
            );
            let words = format!("text;align=left;verticalAlign=middle;fontSize=12;{FONT}");
            shape(
                &format!("lt{k}"),
                text,
                &words,
                (lx + 32.0, ly - 2.0, 190.0, 28.0),
                "legend",
            );
        }
    }
    format!(
        "<mxfile host=\"Electron\"><diagram name=\"tree\" id=\"tree\"><mxGraphModel grid=\"0\" page=\"0\" background=\"#ffffff\"><root><mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>\n{cells}{edges}</root></mxGraphModel></diagram></mxfile>\n"
    )
}

/// `check-drawing tree [--mark pulled|carried]... [<label>=<rev>...]`:
/// prints the tree of the monorepo in the current folder.
pub fn generate(labels: &Labels, marks: &Marks) -> bool {
    match rows(&History::default(), labels, marks) {
        Ok(rows) => {
            print!("{}", render(&rows, marks));
            true
        }
        Err(errors) => {
            for error in errors {
                eprintln!("!!   {error}");
            }
            false
        }
    }
}

/// Checks tree <d>, from drawing <path>, named <name>: that it's the tree
/// the repository gives, with the marks its legend has samples of; prints
/// each cell that differs.
pub fn run(path: &str, name: &str, d: &Diagram, labels: &Labels) -> bool {
    let marks = Marks::of(d);
    let rows = match rows(&History::default(), labels, &marks) {
        Ok(rows) => rows,
        Err(errors) => {
            for error in errors {
                println!("!!   {error}");
            }
            return false;
        }
    };
    let lines = |xml: Result<String, _>| xml.and_then(|xml| cell_lines(&xml)).unwrap_or_default();
    let (drawn, given) = (lines(diagram_xml(path)), lines(Ok(render(&rows, &marks))));
    let mut ids: Vec<&String> = drawn.keys().chain(given.keys()).collect();
    ids.sort();
    ids.dedup();
    let differ: Vec<&String> = ids
        .into_iter()
        .filter(|id| drawn.get(*id) != given.get(*id))
        .collect();
    if differ.is_empty() {
        println!("ok   {name}: a tree of {} rows", rows.len());
        return true;
    }
    let mut revs: Vec<String> = labels
        .revs
        .iter()
        .map(|(l, r)| format!(" {l}={r}"))
        .collect();
    revs.sort();
    println!(
        "!!   {name} isn't the tree the repository gives: write it with `check-drawing tree{}{}`, and export it",
        marks.options(),
        revs.concat()
    );
    for id in differ {
        let cell = |cells: &HashMap<String, String>| {
            cells
                .get(id)
                .map_or("nothing".to_string(), |c| format!("\"{c}\""))
        };
        println!("!!   {id}: drawn {}, given {}", cell(&drawn), cell(&given));
    }
    false
}
