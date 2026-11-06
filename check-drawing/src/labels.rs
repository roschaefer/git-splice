//! `check-drawing labels`: checks that every commit a page names in its
//! prose, in italics like *k* or *b'*, is shown on that page: a circle in a
//! drawing it embeds, or a subject starting `k: ` in one of its code blocks.
//! A reader who lands on the page can't look the label up elsewhere.

use crate::diagram::Diagram;
use pulldown_cmark::{Event, Parser, Tag, TagEnd};
use std::collections::BTreeSet;
use std::path::Path;

/// Whether italic text <text> names a commit: a lowercase letter, then
/// uppercase letters or digits, then primes, e.g. `a`, `b'`, `jX1`. A
/// variable starts uppercase, *X*, and a term is a word, *mount*.
pub fn is_commit_label(text: &str) -> bool {
    let rest = text.trim_end_matches('\'');
    let mut chars = rest.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase())
        && chars.all(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
}

/// The commit labels line <line> of a code block shows as the start of a
/// subject, `m: reorganize folders`, as `git log` prints it or `-m` gives it.
pub fn subject_labels(line: &str) -> impl Iterator<Item = String> + '_ {
    line.split_whitespace().filter_map(|word| {
        let label = word
            .trim_start_matches(['"', '\'', '('])
            .strip_suffix(':')?;
        is_commit_label(label).then(|| label.to_string())
    })
}

/// What a page names and shows.
#[derive(Default)]
pub struct Page {
    /// The commit labels in its italics.
    pub named: BTreeSet<String>,
    /// The paths of the drawings it embeds, as written.
    pub drawings: Vec<String>,
    /// The labels its code blocks show as the start of a commit's subject.
    pub in_code: BTreeSet<String>,
}

/// Reads page <markdown>. A hidden block, `<!--` … `-->`, is HTML to the
/// parser, so it names and shows nothing.
pub fn read_page(markdown: &str) -> Page {
    let mut page = Page::default();
    // The text of the innermost italics we're in, while it's plain text.
    let mut italic: Option<String> = None;
    let mut in_code_block = false;
    for event in Parser::new(markdown) {
        match event {
            Event::Start(Tag::Emphasis) => italic = Some(String::new()),
            Event::End(TagEnd::Emphasis) => {
                if let Some(text) = italic.take().filter(|text| is_commit_label(text)) {
                    page.named.insert(text);
                }
            }
            Event::Start(Tag::CodeBlock(_)) => in_code_block = true,
            Event::End(TagEnd::CodeBlock) => in_code_block = false,
            Event::Text(text) if in_code_block => {
                page.in_code.extend(text.lines().flat_map(subject_labels));
            }
            Event::Text(text) => {
                if let Some(italic) = italic.as_mut() {
                    italic.push_str(&text);
                }
            }
            Event::Start(Tag::Image { dest_url, .. }) => {
                if dest_url.ends_with(".drawio.svg") {
                    page.drawings.push(dest_url.to_string());
                }
                italic = None;
            }
            // Code, a link or more markup inside italics: not a label.
            Event::Code(_) | Event::Start(_) => italic = None,
            _ => {}
        }
    }
    page
}

/// The labels of the circles in drawing <path>; none where it holds no
/// diagram.
fn circles(path: &Path) -> BTreeSet<String> {
    let Ok(diagram) = Diagram::read(&path.to_string_lossy()) else {
        return BTreeSet::new();
    };
    diagram
        .cells
        .iter()
        .filter(|cell| !cell.edge && cell.style.is_ellipse() && !cell.value.is_empty())
        .map(|cell| cell.value.clone())
        .collect()
}

/// The differences on page <path>, one per line.
fn check_page(path: &str) -> Vec<String> {
    let Ok(markdown) = std::fs::read_to_string(path) else {
        return vec![format!("{path}: can't read it")];
    };
    let page = read_page(&markdown);
    let folder = Path::new(path).parent().unwrap_or(Path::new(""));
    let mut shown = page.in_code;
    for drawing in &page.drawings {
        shown.extend(circles(&folder.join(drawing)));
    }
    page.named
        .difference(&shown)
        .map(|label| {
            format!(
                "{path}: *{label}* is in no drawing on this page, and no code block shows a subject `{label}: …`: show the commit"
            )
        })
        .collect()
}

/// Checks pages <pages>: prints each difference and returns whether there
/// were none.
pub fn run(pages: &[String]) -> bool {
    let errors: Vec<String> = pages.iter().flat_map(|page| check_page(page)).collect();
    for error in &errors {
        println!("!!   {error}");
    }
    if errors.is_empty() {
        println!(
            "ok   {} pages: each commit their prose names in italics is shown on its page",
            pages.len()
        );
    }
    errors.is_empty()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_commit_label_starts_lowercase_and_may_end_in_primes() {
        for label in ["a", "b'", "e''", "jX1", "qX"] {
            assert!(is_commit_label(label), "{label}");
        }
        for label in ["X", "L", "mount", "ours", "seed", "", "'", "a b"] {
            assert!(!is_commit_label(label), "{label}");
        }
    }

    #[test]
    fn a_page_names_the_labels_in_its_italics_only() {
        let page = r#"
The monorepo fetched *k* before, and *b'* (`local change`) is new.
Uppercase *X* is a variable, *mount* a term, **b** bold, `*c*` code.

```text
*d* in a code block
```

<!--
```scrut
$ check_drawing x.drawio.svg  # *e* in a hidden block
```
-->

[*f* in a link](other.md), _g_ with underscores.
"#;
        assert_eq!(
            read_page(page).named,
            BTreeSet::from(["b'".into(), "f".into(), "g".into(), "k".into()])
        );
    }

    #[test]
    fn a_page_shows_the_drawings_it_embeds() {
        let page = "![before](before.drawio.svg)\n\n[a link](after.drawio.svg)\n\n![a photo](../images/photo.jpg)\n";
        assert_eq!(
            read_page(page).drawings,
            vec!["before.drawio.svg".to_string()]
        );
    }

    #[test]
    fn a_code_block_shows_the_labels_that_start_a_subject() {
        let page = r#"
```scrut
$ git commit -q -m "m: reorganize folders"
$ git log --graph --format=%s
* b: feature change
ok   vendor/a: pulled 97810bc
seed
```

Inline `c: not a block`.

<!--
```scrut
$ git log --format=%s
d: hidden
```
-->
"#;
        assert_eq!(
            read_page(page).in_code,
            BTreeSet::from(["b".into(), "m".into()])
        );
    }
}
