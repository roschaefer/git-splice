//! The draw.io diagram inside a drawing: its cells, their styles and where
//! they are.

use std::collections::HashMap;

/// A cell's style, e.g. `ellipse;dashed=1;fillColor=#E0E0E0;`.
#[derive(Default, Clone)]
pub struct Style(pub String);

impl Style {
    /// Whether it has entry <entry>, e.g. `dashed=1`.
    pub fn has(&self, entry: &str) -> bool {
        format!(";{};", self.0).contains(&format!(";{entry};"))
    }

    /// Whether it draws shape <shape>: named first, or as an entry. <loose>
    /// also takes an entry that only starts with the name.
    fn draws(&self, shape: &str, loose: bool) -> bool {
        self.0.starts_with(shape)
            || if loose {
                self.0.contains(&format!(";{shape}"))
            } else {
                self.0.contains(&format!(";{shape};"))
            }
    }

    pub fn is_ellipse(&self) -> bool {
        self.draws("ellipse", true)
    }

    pub fn is_line(&self) -> bool {
        self.draws("line", false)
    }

    pub fn is_text(&self) -> bool {
        self.draws("text", false)
    }

    pub fn dashed(&self) -> bool {
        self.has("dashed=1")
    }

    /// The color style key <key> sets: <default> where it sets none or the
    /// default, `none` where it's transparent, `white` and `black` by those
    /// names, and otherwise the color in upper case. The last entry wins.
    pub fn color(&self, key: &str, default: &str) -> String {
        let style = format!(";{};", self.0);
        let marker = format!(";{key}=");
        let color = style.rfind(&marker).map_or(String::new(), |at| {
            let rest = &style[at + marker.len()..];
            rest[..rest.find(';').unwrap_or(rest.len())].to_uppercase()
        });
        match color.as_str() {
            "" | "DEFAULT" => default.to_string(),
            "NONE" => "none".to_string(),
            "#FFFFFF" | "WHITE" => "white".to_string(),
            "#000000" | "BLACK" => "black".to_string(),
            _ => color,
        }
    }
}

/// A shape or an arrow of the diagram.
#[derive(Default, Clone)]
pub struct Cell {
    pub id: String,
    pub edge: bool,
    pub value: String,
    pub style: Style,
    pub source: String,
    pub target: String,
    pub parent: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

pub struct Diagram {
    pub cells: Vec<Cell>,
    by_id: HashMap<String, usize>,
}

/// Why a file holds no diagram to check.
pub struct NoDiagram;

const SVG_NAMESPACE: &str = "http://www.w3.org/2000/svg";

/// The diagram's XML: the `content` attribute of a `.drawio.svg`, or a
/// `.drawio` file as it is.
fn diagram_xml(path: &str) -> Result<String, NoDiagram> {
    let text = std::fs::read_to_string(path).map_err(|_| NoDiagram)?;
    if !path.ends_with(".svg") {
        return Ok(text);
    }
    // draw.io writes SVG 1.1's DOCTYPE.
    let options = roxmltree::ParsingOptions {
        allow_dtd: true,
        ..roxmltree::ParsingOptions::default()
    };
    let svg = roxmltree::Document::parse_with_options(&text, options).map_err(|_| NoDiagram)?;
    let root = svg.root_element();
    if root.tag_name().name() != "svg" || root.tag_name().namespace() != Some(SVG_NAMESPACE) {
        return Err(NoDiagram);
    }
    root.attribute("content")
        .map(str::to_string)
        .ok_or(NoDiagram)
}

fn number(text: Option<&str>) -> f64 {
    text.and_then(|text| text.trim().parse().ok())
        .unwrap_or(0.0)
}

impl Diagram {
    /// Reads the one uncompressed diagram in drawing <path>.
    pub fn read(path: &str) -> Result<Diagram, NoDiagram> {
        let xml = diagram_xml(path)?;
        let document = roxmltree::Document::parse(&xml).map_err(|_| NoDiagram)?;
        let models = document
            .descendants()
            .filter(|node| node.has_tag_name("mxGraphModel"))
            .count();
        if models != 1 {
            return Err(NoDiagram);
        }
        let mut cells = Vec::new();
        // Cells 0 and 1 are draw.io's root and default layer.
        for node in document.descendants().filter(|n| n.has_tag_name("mxCell")) {
            let Some(id) = node.attribute("id") else {
                continue;
            };
            if id == "0" || id == "1" {
                continue;
            }
            let geometry = node.children().find(|n| n.has_tag_name("mxGeometry"));
            let at = |name: &str| number(geometry.and_then(|g| g.attribute(name)));
            let attribute = |name: &str| node.attribute(name).unwrap_or("").to_string();
            cells.push(Cell {
                id: id.to_string(),
                edge: node.attribute("edge") == Some("1"),
                value: attribute("value"),
                style: Style(attribute("style")),
                source: attribute("source"),
                target: attribute("target"),
                parent: attribute("parent"),
                x: at("x"),
                y: at("y"),
                width: at("width"),
                height: at("height"),
            });
        }
        let mut by_id = HashMap::new();
        for (index, cell) in cells.iter().enumerate() {
            by_id.insert(cell.id.clone(), index);
        }
        Ok(Diagram { cells, by_id })
    }

    pub fn index_of(&self, id: &str) -> Option<usize> {
        self.by_id.get(id).copied()
    }

    /// A shape's absolute position: draw.io stores it relative to its parent.
    fn absolute(&self, cell: usize) -> (f64, f64) {
        let (mut x, mut y) = (0.0, 0.0);
        let mut at = Some(cell);
        // A parent cycle would never end otherwise.
        for _ in 0..=self.cells.len() {
            let Some(index) = at else { break };
            let cell = &self.cells[index];
            x += cell.x;
            y += cell.y;
            at = self.index_of(&cell.parent);
        }
        (x, y)
    }

    /// Whether shape <cell> lies wholly inside shape <outer>.
    pub fn contains(&self, cell: usize, outer: usize) -> bool {
        let (x, y) = self.absolute(cell);
        let (ox, oy) = self.absolute(outer);
        let (c, o) = (&self.cells[cell], &self.cells[outer]);
        x >= ox && x + c.width <= ox + o.width && y >= oy && y + c.height <= oy + o.height
    }

    pub fn center_x(&self, cell: usize) -> f64 {
        self.absolute(cell).0 + self.cells[cell].width / 2.0
    }
}

/// A lane's label: a folder, e.g. `vendor/a/`.
pub fn is_lane_label(value: &str) -> bool {
    value.len() > 1 && value.ends_with('/') && !value.contains(' ')
}

/// The lengths a box's name at the start of <text> can have: a word without
/// spaces, or `U(x)`, where x is a label, which may have spaces. A shorter
/// word would leave no ` = ` after it.
fn name_lengths(text: &str) -> Vec<usize> {
    let word = text.find(' ').unwrap_or(text.len());
    let mut lengths: Vec<usize> = if word > 0 { vec![word] } else { vec![] };
    if let Some(inner) = text.strip_prefix("U(") {
        let end = inner.find(['(', ')']).unwrap_or(inner.len());
        if end > 0 && inner[end..].starts_with(')') {
            lengths.push(end + 3);
        }
    }
    lengths
}

/// A box's label: names joined by ` = `, e.g. `U(H) = U(B)`.
pub fn is_box_label(value: &str) -> bool {
    name_lengths(value).into_iter().any(|length| {
        let rest = &value[length..];
        rest.is_empty() || rest.strip_prefix(" = ").is_some_and(is_box_label)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_color_is_read_from_the_last_entry_that_sets_it() {
        let style = Style("ellipse;fillColor=#e0e0e0;strokeColor=default;fillColor=none".into());
        assert_eq!(style.color("fillColor", "white"), "none");
        assert_eq!(style.color("strokeColor", "black"), "black");
        assert_eq!(
            Style("ellipse;fillColor=#e0e0e0;".into()).color("fillColor", "white"),
            "#E0E0E0"
        );
    }

    #[test]
    fn a_box_label_is_names_joined_by_equals_signs() {
        for label in [
            "H",
            "U(H) = U(B)",
            "origin/main",
            "merge-base(R,T)",
            "U(a note)",
            "T = U(a note) = main",
            "U(café)",
            "größe = H",
        ] {
            assert!(is_box_label(label), "{label}");
        }
        for label in [
            "",
            "a note",
            "H =",
            "H = ",
            " = H",
            "U(a (b))",
            "U(a note) x",
            "größe ändern",
        ] {
            assert!(!is_box_label(label), "{label}");
        }
    }

    #[test]
    fn a_lane_label_is_a_folder() {
        assert!(is_lane_label("vendor/a/"));
        assert!(!is_lane_label("/"));
        assert!(!is_lane_label("vendor/a"));
        assert!(!is_lane_label("vendor a/"));
    }
}
