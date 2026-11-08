//! A splice tree: the monorepo and each splice in it, one row each, as `tree`
//! prints folders. A row has the splice's folder, the commit its parent
//! records for it on the edge into it (its synced commit), and, where the
//! splice has commits of its own, its rebuild R, dashed. A splice's children
//! hang from its head: R if it has one, else its synced commit. See README.md.

use crate::check::{subject_has_label, Labels};
use crate::diagram::{Diagram, Style};
use crate::history::History;
use git_splice::util::git;
use std::collections::{HashMap, HashSet};

const BLUE: &str = "#0070E0";
const ORANGE: &str = "#E07000";
const RED: &str = "#D00000";

/// Whether drawing <d> is a splice tree: its root text is styled tree=1.
pub fn is_tree(d: &Diagram) -> bool {
    d.cells.iter().any(|c| !c.edge && c.style.has("tree=1"))
}

struct Row {
    path: String,
    /// The path of the row it hangs from.
    parent: String,
    text: usize,
    circles: Vec<usize>,
    synced: Option<usize>,
    r: Option<usize>,
    theirs: Option<usize>,
}

impl Row {
    fn head(&self) -> Option<usize> {
        self.r.or(self.synced)
    }
}

struct Tree<'a> {
    d: &'a Diagram,
    labels: &'a Labels,
    git: History,
    errors: Vec<String>,
}

fn center(d: &Diagram, cell: usize) -> (f64, f64) {
    let c = &d.cells[cell];
    (c.x + c.width / 2.0, c.y + c.height / 2.0)
}

fn stroke(style: &Style) -> String {
    style.color("strokeColor", "black")
}

impl Tree<'_> {
    /// Whether circle label <label> names commit <commit>: given as
    /// <label>=<rev>, by its subject, or, with a trailing ', as a copy of the
    /// commit the label without it names.
    fn names(&self, label: &str, commit: &str) -> bool {
        if commit.is_empty() {
            return false;
        }
        if let Some(rev) = self.labels.revs.get(label) {
            return self.git.commit(rev).as_deref() == Some(commit);
        }
        if let Some(original) = label.strip_suffix('\'') {
            if let Some(rev) = self.labels.revs.get(original) {
                let Some(original) = self.git.commit(rev) else {
                    return false;
                };
                return original != commit
                    && self.git.copy_key(&original) == self.git.copy_key(commit);
            }
            // Labelled by subject: a commit with that subject, another one,
            // with the same copy key.
            let key = self.git.copy_key(commit);
            return self.git.log(&["--all".to_string()]).iter().any(|c| {
                c.hash != commit
                    && subject_has_label(&c.subject, original)
                    && self.git.copy_key(&c.hash) == key
            });
        }
        subject_has_label(&self.subject(commit), label)
    }

    fn subject(&self, commit: &str) -> String {
        self.git
            .message(commit)
            .lines()
            .next()
            .unwrap_or("")
            .to_string()
    }

    /// The label a commit would get by its subject, for messages.
    fn label_of(&self, commit: &str) -> String {
        let subject = self.subject(commit);
        let label = subject.split(": ").next().unwrap_or(&subject).to_string();
        format!("{label} ({})", &commit[..commit.len().min(7)])
    }

    fn expect(&mut self, cell: usize, commit: &str, what: &str) {
        let label = self.d.cells[cell].value.clone();
        if !self.names(&label, commit) {
            let says = if commit.is_empty() {
                "nothing".to_string()
            } else {
                self.label_of(commit)
            };
            self.errors
                .push(format!("{label} is {what}, but the code says {says}"));
        }
    }

    /// Whether commit <commit> records another synced commit for a splice
    /// inside it than its first parent does: a pull.
    fn records_pull(&self, commit: &str) -> bool {
        !self.git.pulls_in(commit).is_empty()
    }

    /// The rows, by their folder texts, and the circles at the same height.
    fn rows(&mut self) -> Vec<Row> {
        let d = self.d;
        let drawn = |c: usize| d.cells[c].parent == "1";
        let circles: Vec<usize> = (0..d.cells.len())
            .filter(|&c| drawn(c) && !d.cells[c].edge && d.cells[c].style.is_ellipse())
            .collect();
        let texts: Vec<usize> = (0..d.cells.len())
            .filter(|&c| drawn(c) && !d.cells[c].edge && d.cells[c].style.is_text())
            .collect();
        let arrow = |source: usize, target: usize, dashed: bool| {
            d.cells.iter().any(|e| {
                e.edge
                    && e.source == d.cells[source].id
                    && e.target == d.cells[target].id
                    && e.style.dashed() == dashed
            })
        };
        let connector_into = |target: usize| {
            d.cells.iter().find_map(|e| {
                (e.edge && e.target == d.cells[target].id && e.style.has("endArrow=none"))
                    .then(|| d.index_of(&e.source))
                    .flatten()
            })
        };
        // Each text's row: the circles left of it at its height.
        let mut rows: Vec<(usize, Vec<usize>)> = Vec::new();
        for &t in &texts {
            let (_, ty) = center(d, t);
            let mut row: Vec<usize> = circles
                .iter()
                .copied()
                .filter(|&c| (center(d, c).1 - ty).abs() < d.cells[c].height / 2.0)
                .filter(|&c| d.cells[c].x < d.cells[t].x)
                .collect();
            row.sort_by(|a, b| d.cells[*a].x.total_cmp(&d.cells[*b].x));
            rows.push((t, row));
        }
        // Paths, from the root down: a row's parent is the row of the circle
        // its edge comes from.
        let row_of_circle: HashMap<usize, usize> = rows
            .iter()
            .enumerate()
            .flat_map(|(i, (_, cs))| cs.iter().map(move |&c| (c, i)))
            .collect();
        let mut out: Vec<Row> = Vec::new();
        let mut path_of: HashMap<usize, String> = HashMap::new();
        let mut pending: Vec<usize> = (0..rows.len()).collect();
        let mut progress = true;
        while progress && !pending.is_empty() {
            progress = false;
            pending.retain(|&i| {
                let (t, cs) = &rows[i];
                let folder = d.cells[*t]
                    .value
                    .split_whitespace()
                    .next()
                    .unwrap_or("")
                    .trim_end_matches('/')
                    .to_string();
                if d.cells[*t].style.has("tree=1") {
                    path_of.insert(i, String::new());
                    out.push(Row {
                        path: String::new(),
                        parent: String::new(),
                        text: *t,
                        circles: cs.clone(),
                        synced: cs.first().copied(),
                        r: None,
                        theirs: None,
                    });
                    progress = true;
                    return false;
                }
                let synced = cs.iter().copied().find(|&c| connector_into(c).is_some());
                let Some(synced) = synced else {
                    return true;
                };
                let from = connector_into(synced).unwrap();
                let Some(parent_row) = row_of_circle.get(&from) else {
                    return true;
                };
                let Some(parent_path) = path_of.get(parent_row).cloned() else {
                    return true;
                };
                let path = if parent_path.is_empty() {
                    folder
                } else {
                    format!("{parent_path}/{folder}")
                };
                let r = cs
                    .iter()
                    .copied()
                    .find(|&c| c != synced && arrow(synced, c, true) && d.cells[c].style.dashed());
                let head = r.unwrap_or(synced);
                let theirs = cs
                    .iter()
                    .copied()
                    .find(|&c| c != synced && Some(c) != r && arrow(c, head, true));
                path_of.insert(i, path.clone());
                out.push(Row {
                    parent: parent_path.clone(),
                    path,
                    text: *t,
                    circles: cs.clone(),
                    synced: Some(synced),
                    r,
                    theirs,
                });
                progress = true;
                false
            });
        }
        for i in pending {
            let value = &d.cells[rows[i].0].value;
            self.errors.push(format!(
                "{value} hangs from no row: draw an edge, without an arrowhead, from its parent's head to the circle of its synced commit"
            ));
        }
        // An edge comes from its parent's head.
        for row in &out {
            let Some(synced) = row.synced else { continue };
            if row.path.is_empty() {
                continue;
            }
            let from = connector_into(synced).unwrap();
            let parent = out.iter().find(|p| p.circles.contains(&from));
            if let Some(parent) = parent {
                if parent.head() != Some(from) {
                    self.errors.push(format!(
                        "{}/ hangs from {}, but its parent's head is {}: draw the edge from the head",
                        row.path,
                        d.cells[from].value,
                        d.cells[parent.head().unwrap()].value
                    ));
                }
            }
        }
        out
    }

    fn check(&mut self) {
        let rows = self.rows();
        for row in &rows {
            let roles = [row.synced, row.r, row.theirs];
            for &c in &row.circles {
                if roles.contains(&Some(c)) {
                    continue;
                }
                let (whose, roles) = if row.path.is_empty() {
                    ("the monorepo".to_string(), "its head")
                } else {
                    (
                        format!("{}/", row.path),
                        "its synced commit, R, nor what a conflicted pull merges in",
                    )
                };
                self.errors.push(format!(
                    "{} is in the row of {whose}, but is neither {roles}: drop it",
                    self.d.cells[c].value
                ));
            }
        }
        let splices: Vec<String> = self.git.splices();
        let base = self
            .git
            .rev_parse("SPLICE_PULL_START")
            .or_else(|| self.git.rev_parse("HEAD^1"))
            .unwrap_or_default();
        let in_progress = ["CHERRY_PICK_HEAD", "MERGE_HEAD"]
            .iter()
            .find_map(|head| self.git.rev_parse(head));
        let head = self.git.head();
        let mut used: HashSet<&str> = HashSet::new();
        let mut drawn: Vec<String> = Vec::new();
        let d = self.d;
        for row in &rows {
            let text = &d.cells[row.text].value;
            if row.path.is_empty() {
                let Some(circle) = row.synced else {
                    self.errors
                        .push(format!("{text} has no commit: draw HEAD's, in a circle"));
                    continue;
                };
                self.expect(circle, &head, "the monorepo's head");
                let style = &d.cells[circle].style;
                let color = stroke(style);
                let pulled = self.records_pull(&head);
                let carried = self.carried_over();
                self.color(circle, &color, (pulled, carried), &mut used);
                continue;
            }
            drawn.push(row.path.clone());
            if !splices.contains(&row.path) {
                self.errors
                    .push(format!("{}/ isn't a splice of the monorepo", row.path));
                continue;
            }
            // The splice directly around it, or the monorepo.
            let around = splices
                .iter()
                .filter(|s| row.path.starts_with(&format!("{s}/")))
                .max_by_key(|s| s.len())
                .cloned()
                .unwrap_or_default();
            if row.parent != around {
                let name = |p: &str| {
                    if p.is_empty() {
                        "the monorepo".to_string()
                    } else {
                        format!("{p}/")
                    }
                };
                self.errors.push(format!(
                    "{}/ hangs from {}, but the splice around it is {}: draw its row below that one's",
                    row.path,
                    name(&row.parent),
                    name(&around)
                ));
            }
            let synced = self
                .git
                .config(&format!("HEAD:{}/.splice", row.path), "splice.commit");
            let before = self
                .git
                .config(&format!("{base}:{}/.splice", row.path), "splice.commit");
            let s = row.synced.unwrap();
            self.expect(s, &synced, &format!("{}/'s synced commit", row.path));
            if d.cells[s].style.dashed() {
                self.errors.push(format!(
                    "{}, the synced commit of {}/, is dashed: an upstream has it, draw it solid",
                    d.cells[s].value, row.path
                ));
            }
            let color = stroke(&d.cells[s].style);
            self.color(s, &color, (synced != before, false), &mut used);
            let r = self.git.truth(&row.path).r;
            match row.r {
                Some(c) if r == synced => self.errors.push(format!(
                    "{}/ has no commits of its own, R is its synced commit: drop {}",
                    row.path, d.cells[c].value
                )),
                Some(c) => {
                    self.expect(c, &r, &format!("R of {}/", row.path));
                    let color = stroke(&d.cells[c].style);
                    let pulled = self.records_pull(&r);
                    self.color(c, &color, (pulled, true), &mut used);
                }
                None if !r.is_empty() && r != synced => self.errors.push(format!(
                    "{}/ has commits of its own: draw R, {}, dashed, with a dashed arrow from its synced commit",
                    row.path,
                    self.label_of(&r)
                )),
                None => {}
            }
            if let Some(c) = row.theirs {
                let merged = in_progress
                    .as_deref()
                    .map(|h| {
                        self.git
                            .config(&format!("{h}:{}/.splice", row.path), "splice.commit")
                    })
                    .unwrap_or_default();
                if merged.is_empty() || merged == synced {
                    self.errors.push(format!(
                        "{} is drawn as merged into {}/ with a conflict, but the pull in progress doesn't move it",
                        d.cells[c].value, row.path
                    ));
                } else {
                    self.expect(
                        c,
                        &merged,
                        &format!("what {}/'s conflicted pull merges in", row.path),
                    );
                }
                if stroke(&d.cells[c].style) != RED {
                    self.errors.push(format!(
                        "{}, merged in with a conflict, isn't outlined red",
                        d.cells[c].value
                    ));
                }
                used.insert("red");
            }
        }
        for splice in &splices {
            if !drawn.contains(splice) {
                self.errors.push(format!(
                    "{splice} is a splice of the monorepo, but has no row: draw one, so the tree shows every splice"
                ));
            }
        }
        self.check_legend(&used);
    }

    /// Circle <cell>, outlined <color>: blue where it records a pull since
    /// the pull started, with a blue sample in the legend; orange, with an
    /// orange sample, where the rebuild carries it over.
    fn color(
        &mut self,
        cell: usize,
        color: &str,
        (pulled, carried): (bool, bool),
        used: &mut HashSet<&str>,
    ) {
        let samples = self.samples();
        let label = self.d.cells[cell].value.clone();
        let blue = samples.contains(BLUE) && pulled;
        let orange = samples.contains(ORANGE) && !blue && carried;
        let want = if blue {
            BLUE
        } else if orange {
            ORANGE
        } else {
            "black"
        };
        if color == RED {
            self.errors.push(format!(
                "{label} is outlined red, but only a commit merged in with a conflict is"
            ));
        } else if color != want {
            let name = match want {
                BLUE => "blue: it records a pull",
                ORANGE => "orange: the rebuild carries it over",
                _ => "black",
            };
            self.errors
                .push(format!("{label} should be outlined {name}"));
        }
        match color {
            BLUE => used.insert("blue"),
            ORANGE => used.insert("orange"),
            _ => false,
        };
    }

    /// Whether the monorepo's head changed a splice's folder, which the
    /// rebuilds carry over.
    fn carried_over(&self) -> bool {
        // Against the first parent, as the rebuild walks it, a merge too.
        let changed = git(&["diff-tree", "--name-only", "-r", "HEAD^1", "HEAD"])
            .q()
            .out()
            .unwrap_or_default();
        let splices = self.git.splices();
        changed
            .lines()
            .any(|file| splices.iter().any(|s| file.starts_with(&format!("{s}/"))))
    }

    /// The outline colors of the legend's samples.
    fn samples(&self) -> HashSet<String> {
        let legends: Vec<&str> = self
            .d
            .cells
            .iter()
            .filter(|c| c.style.is_legend())
            .map(|c| c.id.as_str())
            .collect();
        self.d
            .cells
            .iter()
            .filter(|c| legends.contains(&c.parent.as_str()) && c.style.is_ellipse())
            .map(|c| stroke(&c.style))
            .collect()
    }

    fn check_legend(&mut self, used: &HashSet<&str>) {
        let samples = self.samples();
        for (name, color, word) in [
            ("blue", BLUE, "pulled"),
            ("orange", ORANGE, "carried over"),
            ("red", RED, "merged in with a conflict"),
        ] {
            let explains = samples.contains(color);
            if used.contains(name) && !explains {
                self.errors.push(format!(
                    "the legend doesn't explain {name}, {word}: add a sample circle with it"
                ));
            } else if !used.contains(name) && explains {
                self.errors.push(format!(
                    "the legend explains {name}, which no commit has: drop that sample"
                ));
            }
        }
    }
}

/// Checks splice tree <d>, from drawing <name>; prints what it found.
pub fn run(name: &str, d: &Diagram, labels: &Labels) -> bool {
    let mut tree = Tree {
        d,
        labels,
        git: History::default(),
        errors: Vec::new(),
    };
    tree.check();
    if !tree.errors.is_empty() {
        for error in &tree.errors {
            println!("!!   {error}");
        }
        return false;
    }
    let rows = d
        .cells
        .iter()
        .filter(|c| c.parent == "1" && !c.edge && c.style.is_text())
        .count();
    println!("ok   {name}: a tree of {rows} rows");
    true
}
