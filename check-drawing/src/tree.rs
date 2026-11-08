//! A splice tree: the monorepo and each splice in it, one row each, as `tree`
//! prints folders. It's a summary of the lane drawing, and checked as one: each
//! row becomes the splice's lane, nested as the rows hang, with the commits
//! the row shows, and the boxes that say what they are. The checks are then
//! the lane drawing's; only how the rows hang is the tree's own. See README.md.

use crate::check::{Checker, Labels};
use crate::diagram::{Cell, Diagram, Style};
use std::collections::HashMap;

const RED: &str = "#D00000";

/// Whether drawing <d> is a splice tree: its root text is styled tree=1.
pub fn is_tree(d: &Diagram) -> bool {
    d.cells.iter().any(|c| !c.edge && c.style.has("tree=1"))
}

/// A row: the splice's path, relative to the monorepo, the row it hangs from,
/// and its circles: its synced commit (the root's: HEAD), R, after the dots,
/// and what a conflicted pull merges in, outlined red, if drawn.
struct Row {
    path: String,
    parent: Option<usize>,
    synced: Option<usize>,
    r: Option<usize>,
    theirs: Option<usize>,
    depth: usize,
}

fn center_y(d: &Diagram, cell: usize) -> f64 {
    d.cells[cell].y + d.cells[cell].height / 2.0
}

fn stroke(style: &Style) -> String {
    style.color("strokeColor", "black")
}

/// The rows of tree <d>, in the order drawn, top to bottom; what doesn't fit
/// the tree's shape goes to <errors>.
fn rows(d: &Diagram, errors: &mut Vec<String>) -> Vec<Row> {
    let drawn = |c: usize| d.cells[c].parent == "1" && !d.cells[c].edge;
    let is_dots = |c: usize| d.cells[c].value.trim_matches(['.', '…', ' ']).is_empty();
    let (dots, mut texts): (Vec<usize>, Vec<usize>) = (0..d.cells.len())
        .filter(|&c| drawn(c) && d.cells[c].style.is_text())
        .partition(|&c| is_dots(c));
    texts.sort_by(|a, b| d.cells[*a].y.total_cmp(&d.cells[*b].y));
    let circles: Vec<usize> = (0..d.cells.len())
        .filter(|&c| drawn(c) && d.cells[c].style.is_ellipse())
        .collect();
    let connector_into = |target: usize| {
        d.cells.iter().find_map(|e| {
            (e.edge && e.target == d.cells[target].id && e.style.has("endArrow=none"))
                .then(|| d.index_of(&e.source))
                .flatten()
        })
    };
    let mut out: Vec<Row> = Vec::new();
    let mut row_of: HashMap<usize, usize> = HashMap::new();
    for &t in &texts {
        let ty = center_y(d, t);
        let mut cs: Vec<usize> = circles
            .iter()
            .copied()
            .filter(|&c| (center_y(d, c) - ty).abs() < d.cells[c].height / 2.0)
            .filter(|&c| d.cells[c].x < d.cells[t].x)
            .collect();
        cs.sort_by(|a, b| d.cells[*a].x.total_cmp(&d.cells[*b].x));
        // R is the circle after the dots; whether it's dashed is the lane
        // checker's to say.
        let dots_x = dots
            .iter()
            .find(|&&c| (center_y(d, c) - ty).abs() < d.cells[c].height / 2.0)
            .map(|&c| d.cells[c].x);
        let theirs = cs
            .iter()
            .copied()
            .find(|&c| stroke(&d.cells[c].style) == RED);
        let (after, rest): (Vec<usize>, Vec<usize>) = cs
            .iter()
            .copied()
            .filter(|&c| Some(c) != theirs)
            .partition(|&c| dots_x.is_some_and(|x| d.cells[c].x > x));
        if after.len() > 1 {
            errors.push(format!(
                "{} has {} circles after its dots, but a row shows one R: drop the others",
                d.cells[t].value,
                after.len()
            ));
        }
        let r = after.first().copied();
        let folder = d.cells[t]
            .value
            .split_whitespace()
            .next()
            .unwrap_or("")
            .trim_end_matches('/')
            .to_string();
        let root = d.cells[t].style.has("tree=1");
        if rest.len() > 1 {
            errors.push(format!(
                "{} has {} circles before its dots, but a row shows one synced commit: drop the others",
                d.cells[t].value,
                rest.len()
            ));
        }
        let synced = rest.first().copied();
        let mut row = Row {
            path: if root { String::new() } else { folder.clone() },
            parent: None,
            synced,
            r,
            theirs,
            depth: 0,
        };
        if !root {
            // Into the synced commit; into R for a splice that has none
            // yet, after an init.
            let from = synced.or(r).and_then(connector_into);
            match from.and_then(|f| row_of.get(&f).copied()) {
                Some(p) => {
                    let parent = &out[p];
                    if parent.r.or(parent.synced) != from {
                        errors.push(format!(
                            "{} hangs from {}, but its parent's head is {}: draw the edge from the head",
                            d.cells[t].value,
                            d.cells[from.unwrap()].value,
                            parent
                                .r
                                .or(parent.synced)
                                .map_or("", |h| d.cells[h].value.as_str())
                        ));
                    }
                    row.path = if parent.path.is_empty() {
                        folder
                    } else {
                        format!("{}/{folder}", parent.path)
                    };
                    row.parent = Some(p);
                    row.depth = parent.depth + 1;
                }
                None => errors.push(format!(
                    "{} hangs from no row above it: draw an edge, without an arrowhead, from its parent's head to the circle of its synced commit",
                    d.cells[t].value
                )),
            }
        }
        // Only now: an edge from a circle of this row is from no row above.
        for &c in &cs {
            row_of.insert(c, out.len());
        }
        out.push(row);
    }
    out
}

/// The lane drawing tree <d> summarizes: a lane per row, nested as the rows
/// hang, each with the row's circles, and a box on each saying what it is:
/// H for the root's, U(H) for a synced commit, R, and T for what a conflicted
/// pull merges in, which is what its upstream branch has.
fn as_lanes(d: &Diagram, rows: &[Row]) -> Diagram {
    const ROW: f64 = 100.0;
    let mut cells: Vec<Cell> = Vec::new();
    let add = |cells: &mut Vec<Cell>, cell: Cell| cells.push(cell);
    let shape = |id: String, value: &str, style: &str, (x, y, w, h): (f64, f64, f64, f64)| Cell {
        id,
        edge: false,
        value: value.to_string(),
        style: Style(style.to_string()),
        parent: "1".to_string(),
        x,
        y,
        width: w,
        height: h,
        ..Cell::default()
    };
    // A row's subtree is the rows after it, deeper than it, up to the next
    // that isn't.
    let last_below = |i: usize| {
        let mut last = i;
        while last + 1 < rows.len() && rows[last + 1].depth > rows[i].depth {
            last += 1;
        }
        last
    };
    for (i, row) in rows.iter().enumerate() {
        let y = i as f64 * ROW;
        let x = row.depth as f64 * 20.0;
        if !row.path.is_empty() {
            let height = (last_below(i) - i) as f64 * ROW + 60.0;
            add(
                &mut cells,
                shape(
                    format!("lane{i}"),
                    &format!("{}/", row.path),
                    "rounded=1;",
                    (x, y - 10.0, 4000.0 - 2.0 * x, height),
                ),
            );
        }
        let roles = [
            (row.synced, if row.path.is_empty() { "H" } else { "U(H)" }),
            (row.r, "R"),
            (row.theirs, "T"),
        ];
        for (k, (circle, term)) in roles.iter().enumerate() {
            let Some(c) = circle else { continue };
            let mut commit = d.cells[*c].clone();
            commit.parent = "1".to_string();
            commit.x = x + 100.0 + k as f64 * 60.0;
            commit.y = y;
            commit.width = 40.0;
            commit.height = 40.0;
            add(&mut cells, commit);
            let id = format!("box{i}_{k}");
            add(
                &mut cells,
                shape(
                    id.clone(),
                    term,
                    "rounded=1;",
                    (x + 1000.0 + k as f64 * 80.0, y, 60.0, 30.0),
                ),
            );
            add(
                &mut cells,
                Cell {
                    id: format!("{id}_arrow"),
                    edge: true,
                    source: id,
                    target: d.cells[*c].id.clone(),
                    parent: "1".to_string(),
                    style: Style("endArrow=block;".to_string()),
                    ..Cell::default()
                },
            );
        }
    }
    // The legend, as it is, out of the lanes' way.
    for cell in &d.cells {
        if cell.style.is_legend() {
            let mut legend = cell.clone();
            legend.x = 5000.0;
            legend.y = 0.0;
            add(&mut cells, legend);
        } else if d.in_legend(cell) {
            add(&mut cells, cell.clone());
        }
    }
    Diagram::from_cells(cells)
}

/// Checks splice tree <d>, from drawing <name>, as the lane drawing it
/// summarizes; prints what it found.
pub fn run(name: &str, d: &Diagram, labels: &Labels) -> bool {
    let mut errors = Vec::new();
    let rows = rows(d, &mut errors);
    let lanes = as_lanes(d, &rows);
    Checker::check_diagram(name, &lanes, labels, true, errors)
}
