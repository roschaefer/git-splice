//! The arrows of a drawing, each checked by what it means: from a commit to
//! its child, from a box to the commit it names, and, in drawings of other
//! tools, from a commit to the one its message or one of its files names.

use super::{argument, is_branch_term, is_term, names_commit, names_commit_on_line, Checker, Kind};
use std::collections::{HashMap, HashSet};

/// The two shapes an arrow joins, what they are, and their labels.
struct Ends {
    s: usize,
    t: usize,
    source: Option<Kind>,
    target: Option<Kind>,
    vs: String,
    vt: String,
}

impl Ends {
    fn join_commits(&self) -> bool {
        self.source == Some(Kind::Commit) && self.target == Some(Kind::Commit)
    }
}

/// What the arrows say: the parent links drawn, the arrows from each box,
/// and the upstream branch tips the boxes name, by splice and side.
pub(super) struct Arrows {
    pub drawn_edges: HashSet<(usize, usize)>,
    pub box_arrows: HashMap<usize, usize>,
    pub branch_tips: HashMap<(String, String), Vec<String>>,
}

impl Checker<'_> {
    /// Arrows: between commits, parent to child; from a box, to its commit;
    /// styled message=1, from a commit to one its message names by hash;
    /// styled config=<file>:<key>, from a commit to the one its <file> names
    /// under <key>.
    pub(super) fn check_arrows(&mut self) -> Arrows {
        let d = self.d;
        let mut arrows = Arrows {
            drawn_edges: HashSet::new(),
            box_arrows: HashMap::new(),
            branch_tips: HashMap::new(),
        };
        for edge in self.edges.clone() {
            let cell = &d.cells[edge];
            let (source_id, target_id) = (cell.source.as_str(), cell.target.as_str());
            if !source_id.is_empty() && self.kind_of(source_id) == Some(Kind::Box) {
                if let Some(s) = d.index_of(source_id) {
                    *arrows.box_arrows.entry(s).or_default() += 1;
                }
            }
            if source_id.is_empty() || target_id.is_empty() {
                self.errors.push(format!(
                    "an arrow ({}) isn't attached at both ends: drag its ends onto shapes",
                    cell.id
                ));
                continue;
            }
            let s = d.index_of(source_id).unwrap_or(usize::MAX);
            let t = d.index_of(target_id).unwrap_or(usize::MAX);
            let value_of = |i: usize| d.cells.get(i).map_or("", |c| c.value.as_str());
            let ends = Ends {
                s,
                t,
                source: self.kind_of(source_id),
                target: self.kind_of(target_id),
                vs: value_of(s).to_string(),
                vt: value_of(t).to_string(),
            };
            if cell.style.has("message=1") {
                self.check_message_arrow(edge, &ends);
            } else if let Some(config) = cell.style.value("config") {
                self.check_config_arrow(edge, config, &ends);
            } else if ends.source == Some(Kind::Box) {
                self.check_box_arrow(&ends, &mut arrows.branch_tips);
            } else if ends.target == Some(Kind::Box) {
                self.errors.push(format!(
                    "an arrow from {} points at the box {}: draw it from the box to its commit",
                    ends.vs, ends.vt
                ));
            } else if self.check_parent_arrow(edge, &ends) {
                arrows.drawn_edges.insert((s, t));
            }
        }
        arrows
    }

    /// A message arrow: the source's message names the target by hash, on a
    /// line that starts with the arrow's label, if it has one, e.g.
    /// `git-subtree-mainline`.
    fn check_message_arrow(&mut self, edge: usize, ends: &Ends) {
        let d = self.d;
        let (vs, vt) = (&ends.vs, &ends.vt);
        if !ends.join_commits() {
            self.errors.push(format!("a message arrow ({}) doesn't join two commits: draw it from a commit to the one its message names", d.cells[edge].id));
            return;
        }
        let (cs, ct) = (self.commit(ends.s), self.commit(ends.t));
        if cs.is_empty() || ct.is_empty() {
            return;
        }
        let label = d.cells[edge].value.trim();
        let message = self.git.message(&cs);
        if !names_commit(&message, &ct) {
            self.errors.push(format!(
                "{vs}'s message doesn't name {vt}: point the message arrow at the commit it names"
            ));
        } else if !label.is_empty() && !names_commit_on_line(&message, label, &ct) {
            self.errors.push(format!(
                "{vs}'s message names {vt}, but not on a line {label}: label the message arrow with the line's start"
            ));
        }
    }

    /// A config arrow, styled config=<file>:<key>: the source's <file> names
    /// the target under <key>, e.g. `.gitrepo:subrepo.parent`, and the arrow
    /// is labelled with the key's last part, if at all.
    fn check_config_arrow(&mut self, edge: usize, config: &str, ends: &Ends) {
        let d = self.d;
        let (vs, vt) = (&ends.vs, &ends.vt);
        let id = &d.cells[edge].id;
        let Some((file, key)) = config.split_once(':') else {
            self.errors.push(format!(
                "a config arrow ({id}) names no key: style it config=<file>:<key>"
            ));
            return;
        };
        let label = d.cells[edge].value.trim();
        let short_key = key.rsplit('.').next().unwrap_or(key);
        if !label.is_empty() && label != short_key {
            self.errors.push(format!(
                "a config arrow ({id}) is labelled {label}, not {short_key}: label it with its key"
            ));
        }
        if !ends.join_commits() {
            self.errors.push(format!("a config arrow ({id}) doesn't join two commits: draw it from a commit to the one its {file} names"));
            return;
        }
        let (cs, ct) = (self.commit(ends.s), self.commit(ends.t));
        let named = self.git.config(&format!("{cs}:{file}"), key);
        if !cs.is_empty() && !ct.is_empty() && (named.is_empty() || !ct.starts_with(&named)) {
            self.errors.push(format!(
                "{vs}'s {file} doesn't name {vt} as {key}: point the config arrow at the commit it names"
            ));
        }
    }

    /// An arrow from a box: to a commit in the box's lane, on its side, and
    /// each name in the box names that commit.
    fn check_box_arrow(
        &mut self,
        ends: &Ends,
        branch_tips: &mut HashMap<(String, String), Vec<String>>,
    ) {
        let (s, t, vs, vt) = (ends.s, ends.t, &ends.vs, &ends.vt);
        if ends.target != Some(Kind::Commit) {
            self.errors
                .push(format!("{vs} points at something other than a commit"));
            return;
        }
        // A box sits with the commit it points at: in its lane, or outside
        // every lane, like H and B with their monorepo commits.
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
            return;
        }
        let (side_s, side_t) = (self.side_name(s), self.side_name(t));
        if side_s != side_t {
            let side = if side_t.is_empty() { "other" } else { &side_t };
            self.errors.push(format!(
                "{vs} points at {vt}, on the {side} side: draw the box on that side"
            ));
            return;
        }
        self.check_box(s, t, branch_tips);
    }

    /// An arrow between commits: from a parent to its child, in one lane, on
    /// one side, dashed where no upstream branch has the child. Whether it
    /// joins two commits the drawing names.
    fn check_parent_arrow(&mut self, edge: usize, ends: &Ends) -> bool {
        let (s, t, vs, vt) = (ends.s, ends.t, &ends.vs, &ends.vt);
        if !ends.join_commits() {
            return false;
        }
        if self.lane_of(s) != self.lane_of(t) {
            self.errors.push(format!(
                "{vs} -> {vt} crosses lanes: draw a parent and its child in one lane"
            ));
            return false;
        }
        if self.side_name(s) != self.side_name(t) {
            self.errors.push(format!(
                "{vs} -> {vt} crosses the separator: draw the parent on {vt}'s side too"
            ));
            return false;
        }
        let (cs, ct) = (self.commit(s), self.commit(t));
        if cs.is_empty() || ct.is_empty() {
            return false;
        }
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
        true
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
}
