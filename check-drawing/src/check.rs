//! Checks a drawing against the repositories it shows, in phases: read the
//! diagram, place each shape in its lane and on its side, find the commit each
//! label names and the facts of each splice, then check the rules, each adding
//! the differences it finds. See README.md next to src/ for the vocabulary.

use crate::diagram::{is_box_label, is_lane_label, Diagram};
use crate::history::{History, Truth};
use std::collections::{HashMap, HashSet};

const CARRIED_OUTLINE: &str = "#E07000";
const WALKED_FILL: &str = "#E0E0E0";

/// What a shape of the drawing is.
#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Commit,
    Edge,
    Separator,
    Lane,
    Side,
    Box,
}

/// The lane a shape is in: the innermost one around it.
#[derive(Clone, Default)]
struct Place {
    /// The lane's cell.
    lane: Option<usize>,
    /// Its splice's folder, e.g. `vendor/a`.
    splice: String,
    /// Its label, e.g. `vendor/a/`.
    label: String,
}

/// The upstream a side of a split lane holds.
#[derive(Clone)]
struct Side {
    name: String,
    key: String,
}

/// The arguments after the drawing.
#[derive(Default)]
pub struct Labels {
    /// `<label>=<rev>`: the revision a label names.
    pub revs: HashMap<String, String>,
    /// `--alias <name>=<term>`.
    pub aliases: HashMap<String, String>,
}

/// One side of one lane: the lane's cell and the number of separators left
/// of it.
type Region = (usize, usize);

fn is_term(term: &str, function: &str) -> bool {
    term.len() >= function.len() + 2
        && term.starts_with(function)
        && term[function.len()..].starts_with('(')
        && term.ends_with(')')
}

/// The argument of `U(x)` or `tracked(x)`.
fn argument<'a>(term: &'a str, function: &str) -> &'a str {
    &term[function.len() + 1..term.len() - 1]
}

/// Whether box term <term> is a branch name, not H, B, T, R, U(x),
/// tracked(b) or merge-base(R,T).
fn is_branch_term(term: &str) -> bool {
    !matches!(term, "H" | "B" | "T" | "R" | "merge-base(R,T)")
        && !is_term(term, "U")
        && !is_term(term, "tracked")
}

/// Whether commit <commit>'s message names commit <named> by hash, at least
/// 7 digits of it.
fn names_commit(message: &str, named: &str) -> bool {
    message
        .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
        .filter(|word| {
            (7..=40).contains(&word.len())
                && word.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
        })
        .any(|hash| named.starts_with(hash))
}

/// Whether subject <subject> is labelled <label>: all of it, or its start up
/// to a colon.
fn subject_has_label(subject: &str, label: &str) -> bool {
    let subject = subject.split('\t').next().unwrap_or("");
    subject == label || subject.starts_with(&format!("{label}: "))
}

fn file_name(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

pub struct Checker<'a> {
    name: String,
    d: &'a Diagram,
    labels: &'a Labels,
    git: History,
    errors: Vec<String>,

    kind: HashMap<usize, Kind>,
    commits: Vec<usize>,
    edges: Vec<usize>,
    boxes: Vec<usize>,
    lanes: Vec<usize>,
    separators: Vec<usize>,
    sides: Vec<usize>,
    legends: usize,
    legend_samples: Vec<usize>,

    splices: Vec<String>,
    default: String,
    lane_splice: HashMap<usize, String>,
    place: HashMap<usize, Place>,
    split_lanes: Vec<(usize, usize)>,
    region_name: HashMap<Region, String>,
    region_key: HashMap<Region, String>,
    side: HashMap<usize, Side>,

    head: String,
    splice_of: HashMap<usize, String>,
    truth: HashMap<String, Truth>,
    no_truth: Truth,
    /// The branches of dashed boxes, by splice, in the order drawn.
    local_tips: Vec<(String, Vec<String>)>,

    commit_of: HashMap<usize, String>,
    label_of: HashMap<String, String>,
    id_of_label: HashMap<String, usize>,
    label_count: HashMap<String, usize>,
}

impl<'a> Checker<'a> {
    fn value(&self, cell: usize) -> &'a str {
        &self.d.cells[cell].value
    }

    fn dashed(&self, cell: usize) -> bool {
        self.d.cells[cell].style.dashed()
    }

    fn kind_of(&self, id: &str) -> Option<Kind> {
        self.d.index_of(id).and_then(|i| self.kind.get(&i).copied())
    }

    fn place(&self, cell: usize) -> Place {
        self.place.get(&cell).cloned().unwrap_or_default()
    }

    fn lane_of(&self, cell: usize) -> String {
        self.place(cell).splice
    }

    fn side_name(&self, cell: usize) -> String {
        self.side
            .get(&cell)
            .map(|s| s.name.clone())
            .unwrap_or_default()
    }

    fn side_key(&self, cell: usize) -> String {
        self.side
            .get(&cell)
            .map(|s| s.key.clone())
            .unwrap_or_default()
    }

    fn commit(&self, cell: usize) -> String {
        self.commit_of.get(&cell).cloned().unwrap_or_default()
    }

    fn truth(&self, splice: &str) -> &Truth {
        self.truth.get(splice).unwrap_or(&self.no_truth)
    }

    fn splice_of(&self, cell: usize) -> String {
        self.splice_of.get(&cell).cloned().unwrap_or_default()
    }

    fn tips_of(&self, splice: &str) -> &[String] {
        self.local_tips
            .iter()
            .find(|(s, _)| s == splice)
            .map_or(&[], |(_, tips)| tips.as_slice())
    }

    /// Checks drawing <path>: prints what it checked, or each difference.
    pub fn run(path: &str, labels: &Labels) -> bool {
        let name = file_name(path).to_string();
        let Ok(d) = Diagram::read(path) else {
            println!("!!   {name}: no diagram inside, or a compressed one: save it with File > Properties > Compressed off");
            return false;
        };
        let mut checker = Checker {
            name,
            d: &d,
            labels,
            git: History::default(),
            errors: Vec::new(),
            kind: HashMap::new(),
            commits: Vec::new(),
            edges: Vec::new(),
            boxes: Vec::new(),
            lanes: Vec::new(),
            separators: Vec::new(),
            sides: Vec::new(),
            legends: 0,
            legend_samples: Vec::new(),
            splices: Vec::new(),
            default: String::new(),
            lane_splice: HashMap::new(),
            place: HashMap::new(),
            split_lanes: Vec::new(),
            region_name: HashMap::new(),
            region_key: HashMap::new(),
            side: HashMap::new(),
            head: String::new(),
            splice_of: HashMap::new(),
            truth: HashMap::new(),
            no_truth: Truth::default(),
            local_tips: Vec::new(),
            commit_of: HashMap::new(),
            label_of: HashMap::new(),
            id_of_label: HashMap::new(),
            label_count: HashMap::new(),
        };
        checker.check()
    }

    fn check(&mut self) -> bool {
        self.classify();
        if self.commits.is_empty() {
            println!("!!   {}: no commits drawn", self.name);
            return false;
        }
        // Git commands run at the monorepo's root from here on.
        self.splices = self.git.splices();
        if let Err(message) = self.place_in_lanes() {
            println!("!!   {message}");
            return false;
        }
        self.place_on_sides();
        self.load_truth();
        self.read_dashed_boxes();
        self.find_commits();
        self.check_lanes_of_commits();
        self.check_dashes();
        self.check_colors();
        self.check_legend();
        let (drawn_edges, box_arrows, branch_tips) = self.check_arrows();
        self.check_branches_off_t(&branch_tips);
        for &cell in &self.boxes {
            let arrows = box_arrows.get(&cell).copied().unwrap_or(0);
            if arrows != 1 {
                self.errors.push(format!(
                    "{} has {arrows} arrows, not one: draw one from the box to its commit",
                    self.value(cell)
                ));
            }
        }
        self.check_parent_arrows_drawn(&drawn_edges);

        if !self.errors.is_empty() {
            for error in &self.errors {
                println!("!!   {error}");
            }
            return false;
        }
        let mut line = format!(
            "ok   {}: {} commits, {} arrows, {} boxes",
            self.name,
            self.commits.len(),
            self.edges.len(),
            self.boxes.len()
        );
        if !self.lanes.is_empty() {
            line.push_str(&format!(", {} lanes", self.lanes.len()));
        }
        if !self.region_name.is_empty() {
            line.push_str(&format!(", {} upstreams", self.region_name.len()));
        }
        println!("{line}");
        true
    }

    /// What each shape is. A legend, a shape styled legend=1, explains the
    /// marks a drawing uses: the shapes inside it are samples, not commits,
    /// boxes or texts.
    fn classify(&mut self) {
        let legends: HashSet<&str> = self
            .d
            .cells
            .iter()
            .filter(|c| c.style.has("legend=1"))
            .map(|c| c.id.as_str())
            .collect();
        self.legends = legends.len();
        for (i, cell) in self.d.cells.iter().enumerate() {
            if legends.contains(cell.id.as_str()) {
                continue;
            }
            if legends.contains(cell.parent.as_str()) {
                if cell.style.is_ellipse() {
                    self.legend_samples.push(i);
                }
                continue;
            }
            let (kind, list) = if cell.edge {
                (Kind::Edge, &mut self.edges)
            } else if cell.style.is_ellipse() {
                (Kind::Commit, &mut self.commits)
            } else if cell.style.is_line() {
                (Kind::Separator, &mut self.separators)
            } else if is_lane_label(&cell.value) {
                (Kind::Lane, &mut self.lanes)
            } else if cell.style.is_text() {
                // An upstream's name, if it's in a split lane; a box by its
                // label otherwise.
                (Kind::Side, &mut self.sides)
            } else if is_box_label(&cell.value) {
                (Kind::Box, &mut self.boxes)
            } else {
                continue;
            };
            list.push(i);
            self.kind.insert(i, kind);
        }
    }

    /// The splices, the lanes that name them, and the lane each shape is in:
    /// the innermost one around it. Lanes nest as their folders do.
    fn place_in_lanes(&mut self) -> Result<(), String> {
        for &lane in &self.lanes {
            let value = self.value(lane);
            let folder = value.strip_suffix('/').unwrap_or(value);
            if self.splices.iter().any(|s| s == folder) {
                self.lane_splice.insert(lane, folder.to_string());
            } else {
                self.errors
                    .push(format!("the lane {value} isn't a splice of the monorepo"));
            }
        }
        if self.splices.len() == 1 {
            self.default = self.splices[0].clone();
        } else if self.splices.len() > 1 && self.lanes.is_empty() {
            return Err(format!(
                "the monorepo has {} splices: draw a lane for each one the drawing shows, labelled with its folder, e.g. {}/",
                self.splices.len(),
                self.splices[0]
            ));
        }
        for &l in &self.lanes {
            for &o in &self.lanes {
                if o == l {
                    continue;
                }
                let (lv, ov) = (self.value(l), self.value(o));
                let below = lv.len() > ov.len() && lv.starts_with(ov);
                if self.d.inside(l, o) && !below {
                    self.errors.push(format!(
                        "the lane {lv} is drawn inside {ov}, but its folder isn't inside that one"
                    ));
                }
                if below && !self.d.contains(l, o) {
                    self.errors.push(format!(
                        "the lane {lv} is a folder inside {ov}: draw it inside that lane"
                    ));
                }
            }
        }
        let shapes: Vec<usize> = [&self.commits, &self.boxes, &self.separators, &self.sides]
            .into_iter()
            .flatten()
            .copied()
            .collect();
        for shape in shapes {
            let mut place = Place::default();
            let mut smallest: Option<f64> = None;
            for &lane in &self.lanes {
                let Some(splice) = self.lane_splice.get(&lane) else {
                    continue;
                };
                if !self.d.contains(shape, lane) {
                    continue;
                }
                let cell = &self.d.cells[lane];
                let area = cell.width * cell.height;
                if smallest.is_none_or(|s| area < s) {
                    place = Place {
                        lane: Some(lane),
                        splice: splice.clone(),
                        label: cell.value.clone(),
                    };
                    smallest = Some(area);
                }
            }
            self.place.insert(shape, place);
        }
        Ok(())
    }

    /// A shape's side: the number of its lane's separators left of its
    /// center.
    fn region(&self, cell: usize) -> Region {
        let lane = self.place(cell).lane.unwrap_or(usize::MAX);
        let x = self.d.center_x(cell);
        let left = self
            .separators
            .iter()
            .filter(|&&sep| self.place(sep).lane == Some(lane) && self.d.center_x(sep) < x)
            .count();
        (lane, left)
    }

    fn split_count(&self, lane: Option<usize>) -> Option<usize> {
        let lane = lane?;
        self.split_lanes
            .iter()
            .find(|(l, _)| *l == lane)
            .map(|(_, n)| *n)
    }

    /// Upstreams side by side: a dashed line, a separator, splits a lane, and
    /// a text on each side names the upstream whose commits that side holds.
    fn place_on_sides(&mut self) {
        for &sep in &self.separators {
            let place = self.place(sep);
            let Some(lane) = place.lane else {
                self.errors.push("a separator is in no lane: draw it inside the lane of the splice whose upstreams it separates".to_string());
                continue;
            };
            let style = &self.d.cells[sep].style;
            if !style.dashed() {
                self.errors.push(format!(
                    "a line in {} is solid: dash it, a separator is dashed",
                    place.label
                ));
                continue;
            }
            if !style.has("direction=south") && !style.has("direction=north") {
                self.errors.push(format!(
                    "a line in {} isn't vertical: a separator runs from top to bottom, direction=south",
                    place.label
                ));
                continue;
            }
            match self.split_lanes.iter_mut().find(|(l, _)| *l == lane) {
                Some((_, n)) => *n += 1,
                None => self.split_lanes.push((lane, 1)),
            }
        }
        let mut named: HashSet<Region> = HashSet::new();
        let mut lane_upstream: HashSet<(usize, String)> = HashSet::new();
        for side in self.sides.clone() {
            let place = self.place(side);
            let value = self.value(side).to_string();
            if self.split_count(place.lane).is_none() {
                if is_box_label(&value) {
                    self.kind.insert(side, Kind::Box);
                    self.boxes.push(side);
                }
                continue;
            }
            let lane = place.lane.unwrap_or_default();
            let region = self.region(side);
            named.insert(region);
            if let Some(other) = self.region_name.get(&region) {
                self.errors.push(format!(
                    "{other} and {value} name one side of {}: name each side once",
                    place.label
                ));
                continue;
            }
            if !lane_upstream.insert((lane, value.clone())) {
                self.errors.push(format!(
                    "{value} names two sides of {}: name each side after another upstream",
                    place.label
                ));
                continue;
            }
            let names = self.git.upstream_names(&place.splice);
            if !format!(" {} ", names.join(" ")).contains(&format!(" {value} ")) {
                let listed: String = names.iter().map(|n| format!(" {n}")).collect();
                self.errors.push(format!(
                    "{} has no upstream named {value}: name a side after one of its upstreams,{listed}",
                    place.label
                ));
                continue;
            }
            let key = self.git.upstream_key(&place.splice, &value);
            if key.is_empty() {
                self.errors.push(format!(
                    "{value} of {} was never fetched: fetch it before drawing its side",
                    place.label
                ));
                continue;
            }
            self.region_key.insert(region, key);
            self.region_name.insert(region, value);
        }
        // Every side is named, even one with nothing on it.
        for &(lane, separators) in &self.split_lanes {
            for n in 0..=separators {
                if !named.contains(&(lane, n)) {
                    self.errors.push(format!(
                        "side {} of {}, from the left, names no upstream: label each side with its upstream's name",
                        n + 1,
                        self.value(lane)
                    ));
                }
            }
        }
        for cell in self.commits.iter().chain(&self.boxes).copied() {
            if self.split_count(self.place(cell).lane).is_none() {
                continue;
            }
            let region = self.region(cell);
            if let Some(name) = self.region_name.get(&region) {
                let key = self.region_key.get(&region).cloned().unwrap_or_default();
                self.side.insert(
                    cell,
                    Side {
                        name: name.clone(),
                        key,
                    },
                );
            }
        }
    }

    /// What H names, and B, T, R, U(H) and U(B) of each splice the drawing
    /// uses.
    fn load_truth(&mut self) {
        self.head = self.git.head();
        for cell in self.commits.clone().into_iter().chain(self.boxes.clone()) {
            let lane = self.lane_of(cell);
            let splice = if lane.is_empty() {
                self.default.clone()
            } else {
                lane
            };
            if !splice.is_empty() && !self.truth.contains_key(&splice) {
                let truth = self.git.truth(&splice);
                self.truth.insert(splice.clone(), truth);
            }
            self.splice_of.insert(cell, splice);
        }
    }

    /// A dashed box in a lane names a branch of the monorepo whose commits
    /// belong to that splice, but no upstream has, e.g. one checked out in a
    /// worktree of the rebuild: its commits are drawn in the lane, dashed.
    fn read_dashed_boxes(&mut self) {
        for cell in self.boxes.clone() {
            if !self.dashed(cell) {
                continue;
            }
            let value = self.value(cell).to_string();
            let lane = self.lane_of(cell);
            if lane.is_empty() {
                self.errors.push(format!("{value} is dashed, but outside every lane: a dashed box names a branch of the monorepo with a splice's commits, so draw it in that splice's lane"));
                continue;
            }
            let term = self
                .labels
                .aliases
                .get(&value)
                .cloned()
                .unwrap_or(value.clone());
            if value.contains(" = ") || !is_branch_term(&term) {
                self.errors.push(format!(
                    "{value} is dashed, but only a branch of the monorepo is: draw it solid"
                ));
                continue;
            }
            let Some(tip) = self.git.commit(&format!("refs/heads/{term}")) else {
                self.errors.push(format!("{value} is dashed, but the monorepo has no branch {term}: a dashed box names a branch of the monorepo"));
                continue;
            };
            match self.local_tips.iter_mut().find(|(s, _)| *s == lane) {
                Some((_, tips)) => tips.push(tip),
                None => self.local_tips.push((lane, vec![tip])),
            }
        }
    }

    /// Whether commit <commit> is on the branch of a dashed box in splice
    /// <splice>'s lane.
    fn on_local_branch(&self, commit: &str, splice: &str) -> bool {
        self.tips_of(splice)
            .iter()
            .any(|tip| self.git.is_ancestor(commit, tip))
    }

    /// The first commit `git log <args>` lists that label <label> names.
    fn find_labelled(&self, label: &str, args: &[String]) -> String {
        self.git
            .log(args)
            .iter()
            .find(|c| subject_has_label(&c.subject, label))
            .map(|c| c.hash.clone())
            .unwrap_or_default()
    }

    /// The commit each circle's label names.
    fn find_commits(&mut self) {
        let mut drawn_on_side: HashSet<(String, Option<usize>, String)> = HashSet::new();
        for cell in self.commits.clone() {
            let label = self.value(cell).to_string();
            let primed = label.ends_with('\'');
            let base = label.strip_suffix('\'').unwrap_or(&label).to_string();
            let splice = self.splice_of(cell);
            let side_key = self.side_key(cell);
            let revs = &self.labels.revs;
            let mut hash = if let Some(rev) = revs.get(&label).or_else(|| revs.get(&base)) {
                // A copy given in full, e.g. b'=<rev>: several copies of b can
                // look alike, e.g. a pushed one and R's after a 'git rebase'.
                self.git.commit(rev).unwrap_or_default()
            } else {
                // On a side, its upstream's commit first: the monorepo or
                // another upstream may have one with the same subject.
                let mut hash = String::new();
                if !side_key.is_empty() && !primed {
                    hash = self
                        .find_labelled(&base, &[format!("--glob=refs/splices/{side_key}/heads/*")]);
                }
                if hash.is_empty() {
                    hash = self
                        .find_labelled(&base, &["--first-parent".to_string(), "HEAD".to_string()]);
                }
                let mut tips: Vec<String> = Vec::new();
                if !splice.is_empty() {
                    let truth = self.truth(&splice);
                    for tip in [&truth.t, &truth.r, &truth.u, &truth.s] {
                        if !tip.is_empty() {
                            tips.push(tip.clone());
                        }
                    }
                }
                if !side_key.is_empty() {
                    tips.push(format!("--glob=refs/splices/{side_key}/heads/*"));
                }
                tips.extend(self.tips_of(&splice).iter().cloned());
                if hash.is_empty() && !primed && !tips.is_empty() {
                    hash = self.find_labelled(&base, &tips);
                }
                hash
            };
            if !hash.is_empty() && primed && !self.labels.revs.contains_key(&label) {
                if splice.is_empty() {
                    self.errors.push(format!(
                        "{label} is in no lane: draw it in the lane of the splice it's rebuilt for"
                    ));
                    continue;
                }
                let key = self.git.copy_key(&hash);
                // R's history first: a monorepo commit pushed before a 'git
                // rebase' has an older copy on an upstream branch too.
                let truth = self.truth(&splice);
                let upstream_key = if side_key.is_empty() {
                    truth.key.clone()
                } else {
                    side_key.clone()
                };
                let mut tips = Vec::new();
                if !truth.r.is_empty() {
                    tips.push(truth.r.clone());
                }
                tips.push(format!("--glob=refs/splices/{upstream_key}/heads/*"));
                let original = hash;
                hash = tips
                    .iter()
                    .find_map(|tip| {
                        self.git
                            .log_with_copy_keys(std::slice::from_ref(tip))
                            .iter()
                            .find(|copy| **copy != original && self.git.copy_key(copy) == key)
                            .cloned()
                    })
                    .unwrap_or_default();
            }
            if hash.is_empty() {
                self.errors.push(format!("{label}: no such commit"));
                continue;
            }
            self.commit_of.insert(cell, hash.clone());
            // A commit on each side of a separator is one commit, drawn once
            // per side.
            let side = self.side_name(cell);
            if !side.is_empty() {
                let lane = self.place(cell).lane;
                if !drawn_on_side.insert((label.clone(), lane, side.clone())) {
                    self.errors.push(format!(
                        "{label} is drawn twice on the {side} side of {}: draw it once per side",
                        self.place(cell).label
                    ));
                    continue;
                }
                if let Some(&other) = self.id_of_label.get(&label) {
                    let other_side = self.side_name(other);
                    if !other_side.is_empty() {
                        if self.commit(other) != hash {
                            self.errors.push(format!("{label} names one commit on the {other_side} side and another on the {side} side: label them apart"));
                        }
                        continue;
                    }
                }
            }
            self.label_of.insert(hash, label.clone());
            self.id_of_label.insert(label.clone(), cell);
            *self.label_count.entry(label).or_default() += 1;
        }
    }

    /// A monorepo commit: on HEAD, or on another branch of the monorepo, like
    /// a colleague's work on origin/main.
    fn in_monorepo(&self, commit: &str) -> bool {
        self.git.is_ancestor(commit, "HEAD")
            || self
                .git
                .any_ref_contains(commit, &["refs/heads/", "refs/remotes/"])
    }

    fn upstream_has(&self, commit: &str, key: &str) -> bool {
        self.git
            .any_ref_contains(commit, &[&format!("refs/splices/{key}/heads/")])
    }

    /// Whether no fetched branch of any upstream splice <splice> names has
    /// commit <commit>.
    fn not_upstream_of(&self, commit: &str, splice: &str) -> bool {
        self.git.upstream_names(splice).iter().all(|name| {
            let key = self.git.upstream_key(splice, name);
            key.is_empty() || !self.upstream_has(commit, &key)
        })
    }

    /// A commit in a lane is in that splice's upstream history: on R, on a
    /// fetched upstream branch, in a recorded commit's history, or on the
    /// branch of a dashed box in the lane.
    fn of_splice(&self, commit: &str, splice: &str) -> bool {
        let truth = self.truth(splice);
        self.on_local_branch(commit, splice)
            || self.git.is_ancestor(commit, &truth.r)
            || self.upstream_has(commit, &truth.key)
            || truth.synced.iter().any(|s| self.git.is_ancestor(commit, s))
    }

    /// A commit of splice <splice> is dashed if it isn't in the upstream's
    /// history yet: no fetched upstream branch has it. On a side of a
    /// separator, the upstream is that side's, key <side_key>.
    fn not_upstream(&self, commit: &str, splice: &str, side_key: &str) -> bool {
        if splice.is_empty() {
            return false;
        }
        if !self.on_local_branch(commit, splice) && self.in_monorepo(commit) {
            return false;
        }
        let key = if side_key.is_empty() {
            &self.truth(splice).key
        } else {
            side_key
        };
        !self.upstream_has(commit, key)
    }

    fn check_lanes_of_commits(&mut self) {
        for &cell in &self.commits {
            let commit = self.commit(cell);
            if commit.is_empty() {
                continue;
            }
            let value = self.value(cell);
            if self.splices.is_empty() {
                if !self.in_monorepo(&commit) {
                    self.errors.push(format!(
                        "{value} isn't a commit of the monorepo, which has no splices"
                    ));
                }
                continue;
            }
            let lane = self.lane_of(cell);
            if !self.lanes.is_empty() && lane.is_empty() {
                if !self.in_monorepo(&commit) {
                    self.errors.push(format!("{value} isn't a monorepo commit, but it's outside every lane: draw it in its splice's lane"));
                } else if !self.git.is_ancestor(&commit, "HEAD") {
                    if let Some((splice, _)) = self.local_tips.iter().find(|(splice, _)| {
                        self.on_local_branch(&commit, splice)
                            && self.not_upstream_of(&commit, splice)
                    }) {
                        self.errors.push(format!("{value} is on the dashed branch of the lane {splice}/, but outside every lane: draw it in that lane"));
                    }
                }
                continue;
            }
            if lane.is_empty() {
                continue;
            }
            let side = self.side_name(cell);
            if !side.is_empty() {
                if self.upstream_has(&commit, &self.side_key(cell)) {
                    continue;
                }
                if !self.not_upstream_of(&commit, &lane) {
                    self.errors.push(format!("{value} is on the {side} side, but no fetched branch of {side} has it: draw it on the side of an upstream that has it"));
                    continue;
                }
            }
            if !self.of_splice(&commit, &lane) {
                self.errors.push(format!(
                    "{value} is in the lane {lane}/, but isn't in that splice's upstream history or R"
                ));
            }
        }
    }

    fn check_dashes(&mut self) {
        for &cell in &self.commits {
            let commit = self.commit(cell);
            if commit.is_empty() {
                continue;
            }
            let value = self.value(cell);
            if self.not_upstream(&commit, &self.splice_of(cell), &self.side_key(cell)) {
                if !self.dashed(cell) {
                    self.errors.push(format!(
                        "{value} is solid, but no upstream branch has it: dash it"
                    ));
                }
            } else if self.dashed(cell) {
                self.errors.push(format!(
                    "{value} is dashed, but an upstream branch has it: draw it solid"
                ));
            }
        }
    }

    /// What the next rebuild does with a commit, if the drawing's legend says
    /// so. A change it carries across is outlined orange, on both ends: a
    /// commit R copies, from the monorepo's first-parent history since B, and
    /// its copy in R. With a grey sample in the legend, each monorepo commit
    /// the rebuild walks, on that history, is filled grey, e.g. to count them.
    /// Every other commit is outlined black and white inside. Without
    /// splices, e.g. in a drawing of git subtree, neither is checked.
    fn check_colors(&mut self) {
        let mut walked: HashSet<String> = HashSet::new();
        let mut copied: HashSet<String> = HashSet::new();
        for splice in &self.splices {
            let Some(truth) = self.truth.get(splice) else {
                continue;
            };
            if truth.b.is_empty() {
                continue;
            }
            if !truth.r.is_empty() {
                let mut range = vec![truth.r.clone()];
                if !truth.s.is_empty() {
                    range.push(format!("^{}", truth.s));
                }
                for commit in self.git.log_with_copy_keys(&range).iter() {
                    copied.insert(self.git.copy_key(commit));
                }
            }
            walked.extend(self.git.first_parent_since(&truth.b));
            // Where the splice starts, the rebuild walks B too, and copies it,
            // e.g. right after init.
            if copied.contains(&self.git.copy_key(&truth.b)) {
                walked.insert(truth.b.clone());
            }
        }
        let legend_grey = self
            .legend_samples
            .iter()
            .any(|&s| self.d.cells[s].style.color("fillColor", "white") == WALKED_FILL);
        // Each walked monorepo commit's label, by what its copy in R shares
        // with it: author, dates and message.
        let mut walked_label: HashMap<String, String> = HashMap::new();
        for &cell in &self.commits {
            let commit = self.commit(cell);
            if !commit.is_empty() && walked.contains(&commit) && !self.value(cell).ends_with('\'') {
                walked_label.insert(self.git.copy_key(&commit), self.value(cell).to_string());
            }
        }
        for &cell in &self.commits {
            let commit = self.commit(cell);
            if commit.is_empty() || self.splices.is_empty() {
                continue;
            }
            let value = self.value(cell);
            let primed = value.ends_with('\'');
            let splice = self.splice_of(cell);
            let truth = self.truth(&splice);
            let (mut is_walked, mut is_carried) = (false, false);
            // R's copy of a drawn commit is labelled after it, with a '.
            if !primed
                && !splice.is_empty()
                && !truth.r.is_empty()
                && !self.in_monorepo(&commit)
                && self.git.is_ancestor(&commit, &truth.r)
            {
                if let Some(original) = walked_label.get(&self.git.copy_key(&commit)) {
                    self.errors.push(format!(
                        "{value} is R's copy of {original}: label it {original}'"
                    ));
                    continue;
                }
            }
            if primed {
                if !splice.is_empty()
                    && !truth.r.is_empty()
                    && self.git.is_ancestor(&commit, &truth.r)
                    && !self.git.is_ancestor(&commit, &truth.s)
                {
                    is_carried = true;
                }
            } else if self.in_monorepo(&commit)
                && (self.lanes.is_empty() || self.lane_of(cell).is_empty())
                && walked.contains(&commit)
            {
                is_walked = true;
                is_carried = copied.contains(&self.git.copy_key(&commit));
            }

            let style = &self.d.cells[cell].style;
            let have = style.color("fillColor", "white");
            let want = if is_walked && legend_grey {
                WALKED_FILL
            } else {
                "white"
            };
            if have != want {
                if is_walked && legend_grey {
                    self.errors.push(format!(
                        "{value} is a commit the rebuild walks: fill it grey, {WALKED_FILL}"
                    ));
                } else if !is_walked {
                    self.errors.push(format!(
                        "{value} is filled, but the rebuild doesn't walk it: leave it white"
                    ));
                } else if self.legends == 0 {
                    self.errors.push(format!("{value} is filled, but the drawing has no legend to say why: add one, or leave it white"));
                } else if have != WALKED_FILL {
                    self.errors.push(format!(
                        "{value} is filled {have}, a color the legend doesn't explain: leave it white"
                    ));
                }
            }

            let have = style.color("strokeColor", "black");
            let want = if is_carried && self.legends > 0 {
                CARRIED_OUTLINE
            } else {
                "black"
            };
            if have != want {
                if is_carried && self.legends > 0 && primed {
                    self.errors.push(format!(
                        "{value} is R's copy of a commit since B: outline it orange, {CARRIED_OUTLINE}"
                    ));
                } else if is_carried && self.legends > 0 {
                    self.errors.push(format!(
                        "{value} is a commit R copies: outline it orange, {CARRIED_OUTLINE}"
                    ));
                } else if is_carried {
                    self.errors.push(format!("{value} is outlined in color, but the drawing has no legend to say why: add one, or outline it black"));
                } else {
                    self.errors.push(format!("{value} is outlined in color, but the rebuild doesn't carry it across: outline it black"));
                }
            }
        }
    }

    /// The legend explains each mark the drawing's commits use, by a sample
    /// commit with that mark next to the words for it, and no other mark.
    fn check_legend(&mut self) {
        if self.legends == 0 || self.splices.is_empty() {
            return;
        }
        let has_mark = |cell: usize, mark: &str| {
            let c = &self.d.cells[cell];
            match mark {
                "grey" => c.style.color("fillColor", "white") == WALKED_FILL,
                "orange" => c.style.color("strokeColor", "black") == CARRIED_OUTLINE,
                "dashed" => c.style.dashed(),
                _ => c.value.ends_with('\''),
            }
        };
        let marks = [
            ("grey", "a grey fill"),
            ("orange", "an orange outline"),
            ("dashed", "a dashed outline"),
            ("prime", "a ' after a label"),
        ];
        for (mark, name) in marks {
            let uses = self.commits.iter().any(|&c| has_mark(c, mark));
            let explains = self.legend_samples.iter().any(|&c| has_mark(c, mark));
            if uses && !explains {
                self.errors.push(format!(
                    "the legend doesn't explain {name}: add a sample commit with it, and what it means"
                ));
            } else if !uses && explains {
                self.errors.push(format!(
                    "the legend explains {name}, which no commit has: drop that sample"
                ));
            }
        }
    }

    /// What box term <term> of splice <splice> names, or nothing. A branch
    /// name in a box pointing at monorepo commit <pointed> names a monorepo
    /// branch, e.g. main or origin/main; otherwise, an upstream branch, as
    /// fetched, of the upstream with key <side_key>, if given.
    fn resolve_term(&self, term: &str, splice: &str, side_key: &str, pointed: &str) -> String {
        let truth = self.truth(splice);
        let key = if side_key.is_empty() {
            truth.key.as_str()
        } else {
            side_key
        };
        let branch = |name: &str| {
            self.git
                .commit(&format!("refs/splices/{key}/heads/{name}"))
                .unwrap_or_default()
        };
        if is_branch_term(term) && !pointed.is_empty() && self.in_monorepo(pointed) {
            return self
                .git
                .commit(&format!("refs/heads/{term}"))
                .or_else(|| self.git.commit(&format!("refs/remotes/{term}")))
                .unwrap_or_default();
        }
        match term {
            "H" => self.head.clone(),
            "B" => truth.b.clone(),
            "T" => truth.t.clone(),
            "R" => truth.r.clone(),
            "merge-base(R,T)" => truth.base.clone(),
            _ if is_term(term, "tracked") => {
                let name = self.git.tracked_name(argument(term, "tracked"), key);
                if name.is_empty() {
                    String::new()
                } else {
                    branch(&name)
                }
            }
            _ if !is_term(term, "U") => branch(term),
            _ => match argument(term, "U") {
                "H" => truth.u.clone(),
                "B" => truth.s.clone(),
                label => {
                    let Some(&cell) = self.id_of_label.get(label) else {
                        return String::new();
                    };
                    let lane = self.lane_of(cell);
                    let commit = self.commit(cell);
                    let folder = if lane.is_empty() {
                        self.git.path_at(splice, &commit)
                    } else {
                        splice
                            .strip_prefix(&format!("{lane}/"))
                            .unwrap_or(splice)
                            .to_string()
                    };
                    self.git
                        .config(&format!("{commit}:{folder}/.splice"), "splice.commit")
                }
            },
        }
    }

    /// Arrows: between commits, parent to child; from a box, to its commit;
    /// styled message=1, from a commit to one its message names by hash.
    #[allow(clippy::type_complexity)]
    fn check_arrows(
        &mut self,
    ) -> (
        HashSet<(usize, usize)>,
        HashMap<usize, usize>,
        HashMap<(String, String), Vec<String>>,
    ) {
        let mut drawn_edges = HashSet::new();
        let mut box_arrows: HashMap<usize, usize> = HashMap::new();
        let mut branch_tips: HashMap<(String, String), Vec<String>> = HashMap::new();
        for edge in self.edges.clone() {
            let cell = &self.d.cells[edge];
            let (source_id, target_id) = (cell.source.as_str(), cell.target.as_str());
            if !source_id.is_empty() && self.kind_of(source_id) == Some(Kind::Box) {
                if let Some(s) = self.d.index_of(source_id) {
                    *box_arrows.entry(s).or_default() += 1;
                }
            }
            if source_id.is_empty() || target_id.is_empty() {
                self.errors.push(format!(
                    "an arrow ({}) isn't attached at both ends: drag its ends onto shapes",
                    cell.id
                ));
                continue;
            }
            let (source_kind, target_kind) = (self.kind_of(source_id), self.kind_of(target_id));
            let s = self.d.index_of(source_id).unwrap_or(usize::MAX);
            let t = self.d.index_of(target_id).unwrap_or(usize::MAX);
            let value_of = |i: usize| self.d.cells.get(i).map_or("", |c| c.value.as_str());
            let (vs, vt) = (value_of(s).to_string(), value_of(t).to_string());
            if cell.style.has("message=1") {
                if source_kind != Some(Kind::Commit) || target_kind != Some(Kind::Commit) {
                    self.errors.push(format!("a message arrow ({}) doesn't join two commits: draw it from a commit to the one its message names", cell.id));
                } else {
                    let (cs, ct) = (self.commit(s), self.commit(t));
                    if !cs.is_empty()
                        && !ct.is_empty()
                        && !names_commit(&self.git.message(&cs), &ct)
                    {
                        self.errors.push(format!(
                            "{vs}'s message doesn't name {vt}: point the message arrow at the commit it names"
                        ));
                    }
                }
                continue;
            }
            if source_kind == Some(Kind::Box) {
                if target_kind != Some(Kind::Commit) {
                    self.errors
                        .push(format!("{vs} points at something other than a commit"));
                    continue;
                }
                // A box sits with the commit it points at: in its lane, or
                // outside every lane, like H and B with their monorepo
                // commits.
                let (lane_s, lane_t) = (self.lane_of(s), self.lane_of(t));
                if lane_s != lane_t {
                    if lane_t.is_empty() {
                        self.errors.push(format!("{vs} points at {vt}, which is outside every lane: draw the box outside every lane too"));
                    } else {
                        self.errors.push(format!(
                            "{vs} points at {vt}, in the lane {}: draw the box in that lane",
                            self.place(t).label
                        ));
                    }
                    continue;
                }
                let (side_s, side_t) = (self.side_name(s), self.side_name(t));
                if side_s != side_t {
                    let side = if side_t.is_empty() { "other" } else { &side_t };
                    self.errors.push(format!(
                        "{vs} points at {vt}, on the {side} side: draw the box on that side"
                    ));
                    continue;
                }
                self.check_box(s, t, &mut branch_tips);
                continue;
            }
            if target_kind == Some(Kind::Box) {
                self.errors.push(format!(
                    "an arrow from {vs} points at the box {vt}: draw it from the box to its commit"
                ));
                continue;
            }
            if source_kind != Some(Kind::Commit) || target_kind != Some(Kind::Commit) {
                continue;
            }
            if self.lane_of(s) != self.lane_of(t) {
                self.errors.push(format!(
                    "{vs} -> {vt} crosses lanes: draw a parent and its child in one lane"
                ));
                continue;
            }
            if self.side_name(s) != self.side_name(t) {
                self.errors.push(format!(
                    "{vs} -> {vt} crosses the separator: draw the parent on {vt}'s side too"
                ));
                continue;
            }
            let (cs, ct) = (self.commit(s), self.commit(t));
            if cs.is_empty() || ct.is_empty() {
                continue;
            }
            drawn_edges.insert((s, t));
            let dashed = self.dashed(edge);
            if !self.git.parents_of(&ct).contains(&cs) {
                self.errors
                    .push(format!("{vs} -> {vt}: {vs} isn't a parent of {vt}"));
            } else if self.not_upstream(&ct, &self.splice_of(t), &self.side_key(t)) {
                if !dashed {
                    self.errors.push(format!(
                        "{vs} -> {vt} is solid, but no upstream branch has {vt}: dash it"
                    ));
                }
            } else if dashed {
                self.errors.push(format!(
                    "{vs} -> {vt} is dashed, but an upstream branch has {vt}: draw it solid"
                ));
            }
        }
        (drawn_edges, box_arrows, branch_tips)
    }

    /// Box <s> points at commit <t>: each name in it must name that commit.
    fn check_box(
        &mut self,
        s: usize,
        t: usize,
        branch_tips: &mut HashMap<(String, String), Vec<String>>,
    ) {
        let splice = self.splice_of(s);
        let (vs, vt) = (self.value(s).to_string(), self.value(t).to_string());
        let target = self.commit(t);
        let aliases = &self.labels.aliases;
        for shown in vs.split(" = ") {
            let mut term = aliases.get(shown).cloned().unwrap_or(shown.to_string());
            if is_term(&term, "U") {
                let k = argument(&term, "U");
                term = format!("U({})", aliases.get(k).map_or(k, String::as_str));
            }
            // With several splices, only a lane says whose B is.
            if term == "B" && splice.is_empty() {
                self.errors.push("B outside every lane doesn't say which splice's boundary it is: with several splices, leave B out".to_string());
                continue;
            }
            if is_term(&term, "U") {
                let k = argument(&term, "U");
                if k != "H" && k != "B" {
                    let drawn = self
                        .id_of_label
                        .get(k)
                        .is_some_and(|&c| !self.commit(c).is_empty());
                    if !drawn {
                        self.errors.push(format!(
                            "{shown} points at {vt}, but no commit {k} is drawn"
                        ));
                        continue;
                    }
                    let count = self.label_count.get(k).copied().unwrap_or(0);
                    if count > 1 {
                        self.errors.push(format!(
                            "{shown} points at {vt}, but {count} commits are labelled {k}: label them apart"
                        ));
                        continue;
                    }
                }
            }
            let named = if let Some(rev) = self.labels.revs.get(shown) {
                self.git.commit(rev).unwrap_or_default()
            } else if self.dashed(s) {
                // Checked before: a branch of the monorepo.
                match self.git.commit(&format!("refs/heads/{term}")) {
                    Some(named) => named,
                    None => continue,
                }
            } else if !self.lane_of(s).is_empty()
                && is_branch_term(&term)
                && self.git.rev_parse(&format!("refs/heads/{term}")).is_some()
                && !target.is_empty()
                && self.git.is_ancestor(&target, &format!("refs/heads/{term}"))
                && self.not_upstream_of(&target, &splice)
            {
                self.errors.push(format!(
                    "{shown} is a branch of the monorepo, which the upstream doesn't have: dash the box"
                ));
                continue;
            } else {
                let named = self.resolve_term(&term, &splice, &self.side_key(s), &target);
                if (is_branch_term(&term) || is_term(&term, "tracked"))
                    && !named.is_empty()
                    && !self.in_monorepo(&named)
                {
                    branch_tips
                        .entry((splice.clone(), self.side_name(s)))
                        .or_default()
                        .push(named.clone());
                }
                named
            };
            if named.is_empty() {
                self.errors
                    .push(format!("{shown} points at {vt}, but there's no {shown}"));
            } else if target != named {
                let label = match self.label_of.get(&named) {
                    Some(label) => label.clone(),
                    None => format!(
                        "{}, which isn't drawn",
                        named.chars().take(7).collect::<String>()
                    ),
                };
                self.errors
                    .push(format!("{shown} points at {vt}, the code says {label}"));
            }
        }
    }

    /// A solid commit T lacks is on another upstream branch: its box shows
    /// which.
    fn check_branches_off_t(&mut self, branch_tips: &HashMap<(String, String), Vec<String>>) {
        for &cell in &self.commits {
            let commit = self.commit(cell);
            let splice = self.splice_of(cell);
            if commit.is_empty() || splice.is_empty() || self.in_monorepo(&commit) {
                continue;
            }
            let side_key = self.side_key(cell);
            if self.not_upstream(&commit, &splice, &side_key) {
                continue;
            }
            let truth = self.truth(&splice);
            if !truth.t.is_empty() && self.git.is_ancestor(&commit, &truth.t) {
                continue;
            }
            let tips = branch_tips.get(&(splice.clone(), self.side_name(cell)));
            if tips.is_some_and(|tips| tips.iter().any(|tip| self.git.is_ancestor(&commit, tip))) {
                continue;
            }
            let key = if side_key.is_empty() {
                truth.key.clone()
            } else {
                side_key
            };
            let prefix = format!("refs/splices/{key}/heads/");
            let branch = self
                .git
                .first_ref_containing(&commit, &[&prefix])
                .map(|name| name.splitn(5, '/').nth(4).unwrap_or("").to_string())
                .unwrap_or_default();
            self.errors.push(format!(
                "{} is on an upstream branch, but not T's: draw a box for the branch, e.g. {branch}",
                self.value(cell)
            ));
        }
    }

    /// Every parent link between two drawn commits of one lane is drawn.
    fn check_parent_arrows_drawn(&mut self, drawn_edges: &HashSet<(usize, usize)>) {
        for &t in &self.commits {
            let child = self.commit(t);
            if child.is_empty() {
                continue;
            }
            for parent in self.git.parents_of(&child) {
                for &s in &self.commits {
                    if self.commit(s) == parent
                        && self.lane_of(s) == self.lane_of(t)
                        && self.side_name(s) == self.side_name(t)
                        && !drawn_edges.contains(&(s, t))
                    {
                        self.errors.push(format!(
                            "no arrow {} -> {}, though {} is a parent of {}",
                            self.value(s),
                            self.value(t),
                            self.value(s),
                            self.value(t)
                        ));
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_branch_term_is_anything_but_the_vocabulary() {
        for term in ["main", "origin/main", "Tx", "U", "tracked"] {
            assert!(is_branch_term(term), "{term}");
        }
        for term in [
            "H",
            "B",
            "T",
            "R",
            "U(H)",
            "U(b)",
            "tracked(main)",
            "merge-base(R,T)",
        ] {
            assert!(!is_branch_term(term), "{term}");
        }
    }

    #[test]
    fn a_message_names_a_commit_by_a_whole_word_of_7_to_40_digits() {
        let named = "0123456789abcdef0123456789abcdef01234567";
        assert!(names_commit("git-subtree-mainline: 0123456", named));
        assert!(names_commit(
            &format!("(cherry picked from commit {named})"),
            named
        ));
        assert!(!names_commit("012345", named));
        assert!(!names_commit("x0123456", named));
        assert!(!names_commit("0123456_", named));
        assert!(!names_commit("1234567", named));
    }

    #[test]
    fn a_label_is_a_subject_or_its_start_up_to_a_colon() {
        assert!(subject_has_label("a: add vendor/a", "a"));
        assert!(subject_has_label("a", "a"));
        assert!(!subject_has_label("ab: add", "a"));
        assert!(!subject_has_label("a:b", "a"));
    }
}
