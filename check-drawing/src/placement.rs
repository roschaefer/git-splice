//! `check-drawing placement`: checks that every drawing a `check_drawing`
//! block checks is shown next to such a block, with only prose between the
//! image and the block: a place where the drawing shows the current state.
//! The check runs on the state at that point, so an image there can't show
//! an earlier or later one.

use pulldown_cmark::{Event, Parser, Tag, TagEnd};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Component, Path, PathBuf};

/// A top-level block of a page, as the rule sees it.
#[derive(Debug, PartialEq)]
pub enum Block {
    /// Text a reader reads, with the drawings it embeds.
    Prose(Vec<PathBuf>),
    /// Code that checks these drawings, hidden or not.
    Check(Vec<PathBuf>),
    /// Any other code, hidden or not: it may change the state.
    Code,
}

/// <path> without `.` and with each `..` taken back.
fn normalize(path: &Path) -> PathBuf {
    let mut normal = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir if normal.file_name().is_some() => {
                normal.pop();
            }
            _ => normal.push(component),
        }
    }
    normal
}

/// The drawings the `check_drawing` calls in <code> check, as `$TESTDIR`,
/// the page's folder <folder>, names them.
pub fn checked_drawings(code: &str, folder: &Path) -> Vec<PathBuf> {
    code.lines()
        .filter_map(|line| line.split_once("check_drawing").map(|(_, rest)| rest))
        .filter_map(|rest| {
            let start = rest.find("$TESTDIR/")? + "$TESTDIR/".len();
            let end = rest[start..].find(".drawio.svg")? + start + ".drawio.svg".len();
            Some(normalize(&folder.join(&rest[start..end])))
        })
        .collect()
}

/// Whether HTML block <html> only centers what's between its tags.
fn is_layout(html: &str) -> bool {
    let html = html.trim();
    html.starts_with("<div") || html.starts_with("</div")
}

/// The blocks of page <markdown> in folder <folder>, in order: a code
/// block counts wherever it is, in a list or a quote too, and splits the
/// prose around it. Centering `<div>` tags are left out: they're neither
/// prose nor code.
pub fn read_blocks(markdown: &str, folder: &Path) -> Vec<Block> {
    read(markdown, folder, false)
}

/// read_blocks; in a hidden block (<hidden>), images show nothing.
fn read(markdown: &str, folder: &Path, hidden: bool) -> Vec<Block> {
    let mut blocks = Vec::new();
    let mut images = Vec::new();
    // The text of the code or HTML block we're in.
    let mut code: Option<String> = None;
    for event in Parser::new(markdown) {
        match event {
            Event::Start(Tag::CodeBlock(_)) | Event::Start(Tag::HtmlBlock) => {
                blocks.push(Block::Prose(std::mem::take(&mut images)));
                code = Some(String::new());
            }
            Event::End(TagEnd::CodeBlock) | Event::End(TagEnd::HtmlBlock) => {
                let text = code.take().unwrap_or_default();
                let text = text.trim();
                // A hidden block holds code blocks of its own, each a step.
                if let Some(inner) = text.strip_prefix("<!--") {
                    let inner = inner.rfind("-->").map_or(inner, |end| &inner[..end]);
                    blocks.extend(read(inner, folder, true));
                    continue;
                }
                let checked = checked_drawings(text, folder);
                if !checked.is_empty() {
                    blocks.push(Block::Check(checked));
                } else if !text.starts_with('<') {
                    blocks.push(Block::Code);
                } else if !is_layout(text) {
                    blocks.push(Block::Prose(Vec::new()));
                }
            }
            Event::Text(text) | Event::Html(text) => {
                if let Some(code) = code.as_mut() {
                    code.push_str(&text);
                }
            }
            Event::Start(Tag::Image { dest_url, .. })
                if !hidden && dest_url.ends_with(".drawio.svg") =>
            {
                images.push(normalize(&folder.join(dest_url.as_ref())));
            }
            _ => {}
        }
    }
    blocks.push(Block::Prose(images));
    blocks
}

/// The drawings prose block <block> shows; none where it's code.
fn prose_images(block: &Block) -> Option<&Vec<PathBuf>> {
    match block {
        Block::Prose(images) => Some(images),
        _ => None,
    }
}

/// The drawings shown next to a check of them in <blocks>.
pub fn placed(blocks: &[Block]) -> BTreeSet<PathBuf> {
    let mut placed = BTreeSet::new();
    for (at, block) in blocks.iter().enumerate() {
        let Block::Check(checked) = block else {
            continue;
        };
        let before = blocks[..at].iter().rev().map_while(prose_images);
        let after = blocks[at + 1..].iter().map_while(prose_images);
        for image in before.chain(after).flatten() {
            if checked.contains(image) {
                placed.insert(image.clone());
            }
        }
    }
    placed
}

/// Checks pages <pages>: prints each drawing they check that none of them
/// shows next to a check, and returns whether there was none.
pub fn run(pages: &[String]) -> bool {
    // Each checked drawing, with the pages that check it.
    let mut checked: BTreeMap<PathBuf, BTreeSet<String>> = BTreeMap::new();
    let mut shown = BTreeSet::new();
    let mut ok = true;
    for page in pages {
        let Ok(markdown) = std::fs::read_to_string(page) else {
            println!("!!   {page}: can't read it");
            ok = false;
            continue;
        };
        let folder = Path::new(page).parent().unwrap_or(Path::new(""));
        let blocks = read_blocks(&markdown, folder);
        for block in &blocks {
            if let Block::Check(drawings) = block {
                for drawing in drawings {
                    checked
                        .entry(drawing.clone())
                        .or_default()
                        .insert(page.clone());
                }
            }
        }
        shown.extend(placed(&blocks));
    }
    let mut missing = 0;
    for (drawing, pages) in &checked {
        if !shown.contains(drawing) {
            let pages: Vec<&str> = pages.iter().map(String::as_str).collect();
            println!(
                "!!   {}: no image of it is next to its check in {}: show it there, with only prose between",
                drawing.display(),
                pages.join(", ")
            );
            missing += 1;
        }
    }
    if missing == 0 && ok {
        println!(
            "ok   {} drawings: each is shown next to a check of it",
            checked.len()
        );
    }
    missing == 0 && ok
}

#[cfg(test)]
mod tests {
    use super::*;

    fn blocks(markdown: &str) -> Vec<Block> {
        read_blocks(markdown, Path::new("docs/page"))
    }

    fn path(path: &str) -> PathBuf {
        PathBuf::from(path)
    }

    #[test]
    fn a_check_names_its_drawing_from_the_pages_folder() {
        let code = "$ check_drawing \"$TESTDIR/../a.drawio.svg\" \\\n>   a=HEAD\n$ check_drawing \"$TESTDIR/b.drawio.svg\"\n$ git log\n";
        assert_eq!(
            checked_drawings(code, Path::new("docs/page")),
            vec![path("docs/a.drawio.svg"), path("docs/page/b.drawio.svg")]
        );
    }

    #[test]
    fn a_drawing_next_to_its_hidden_check_is_placed() {
        let page = r#"
```text
$ build_scenario x
```

<div align="center">

![x](x.drawio.svg)

</div>

Some prose about it.

<!--
```text
$ check_drawing "$TESTDIR/x.drawio.svg" a=HEAD
```
-->
"#;
        assert_eq!(
            placed(&blocks(page)),
            BTreeSet::from([path("docs/page/x.drawio.svg")])
        );
    }

    #[test]
    fn a_drawing_with_code_between_it_and_its_check_is_not_placed() {
        let page = r#"
![x](x.drawio.svg)

```text
$ git commit -m "b: change"
```

<!--
```text
$ check_drawing "$TESTDIR/x.drawio.svg"
```
-->
"#;
        assert_eq!(placed(&blocks(page)), BTreeSet::new());
    }

    #[test]
    fn hidden_setup_between_a_drawing_and_its_check_counts_as_code() {
        let page = r#"
<!--
```text
$ check_drawing "$TESTDIR/x.drawio.svg"
```
-->

<!--
```text
$ q="$(git rev-parse HEAD)"
```
-->

![x](x.drawio.svg)
"#;
        assert_eq!(placed(&blocks(page)), BTreeSet::new());
    }

    #[test]
    fn code_between_checks_in_one_hidden_block_counts_as_code() {
        let page = r#"
<!--
```text
$ check_drawing "$TESTDIR/x.drawio.svg"
```

```text
$ git switch -q -c feature
```

```text
$ check_drawing "$TESTDIR/y.drawio.svg"
```
-->

![x](x.drawio.svg) ![y](y.drawio.svg)
"#;
        assert_eq!(
            placed(&blocks(page)),
            BTreeSet::from([path("docs/page/y.drawio.svg")])
        );
    }

    #[test]
    fn a_hidden_block_without_code_is_no_code() {
        let page = r#"
![x](x.drawio.svg)

<!-- a note for the authors -->

<!--
```text
$ check_drawing "$TESTDIR/x.drawio.svg"
```
-->
"#;
        assert_eq!(
            placed(&blocks(page)),
            BTreeSet::from([path("docs/page/x.drawio.svg")])
        );
    }

    #[test]
    fn an_image_in_a_hidden_block_shows_nothing() {
        let page = r#"
<!--
![x](x.drawio.svg)

```text
$ check_drawing "$TESTDIR/x.drawio.svg"
```
-->
"#;
        assert_eq!(placed(&blocks(page)), BTreeSet::new());
    }

    #[test]
    fn code_in_a_list_or_quote_counts_as_code() {
        let page = r#"
![x](x.drawio.svg)

- A step:

  ```text
  $ git reset -q --hard HEAD~1
  ```

> ```text
> $ git switch -q main
> ```

<!--
```text
$ check_drawing "$TESTDIR/x.drawio.svg"
```
-->
"#;
        assert_eq!(placed(&blocks(page)), BTreeSet::new());
    }

    #[test]
    fn a_check_in_a_list_places_the_image_next_to_it() {
        let page = r#"
- Check it:

  ```text
  $ check_drawing "$TESTDIR/x.drawio.svg"
  ```

  ![x](x.drawio.svg)
"#;
        assert_eq!(
            placed(&blocks(page)),
            BTreeSet::from([path("docs/page/x.drawio.svg")])
        );
    }

    #[test]
    fn a_check_of_another_drawing_places_nothing() {
        let page = "![x](x.drawio.svg)\n\n<!--\n```text\n$ check_drawing \"$TESTDIR/y.drawio.svg\"\n```\n-->\n";
        assert_eq!(placed(&blocks(page)), BTreeSet::new());
    }
}
