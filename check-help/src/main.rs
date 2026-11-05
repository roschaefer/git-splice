use std::env;
use std::fs;
use std::io::{self, Read};
use std::process::ExitCode;

const URL_PREFIX: &str = "https://roschaefer.github.io/git-splice/docs/command-reference/";

#[derive(Debug)]
struct Section<'a> {
    anchor: &'a str,
    text: &'a str,
    url: &'a str,
}

fn linked_sections(help: &str) -> Result<Vec<Section<'_>>, String> {
    let mut sections = Vec::new();
    let mut offset = 0;
    let mut section_start = None;
    let mut after_link = false;
    for line in help.split_inclusive('\n') {
        let end = offset + line.len();
        let heading = line.trim_end();
        if is_heading(line) {
            after_link = false;
            if let Some(start) = section_start {
                return Err(format!(
                    "help section has no See also link: {}",
                    help[start..].lines().next().unwrap_or_default()
                ));
            }
            section_start = (!matches!(heading, "NAME" | "SYNOPSIS")).then_some(offset);
        } else if after_link && !heading.is_empty() {
            return Err(format!(
                "help text follows a section's final link: {heading}"
            ));
        }
        let Some(url_start) = line
            .strip_prefix("    See also: ")
            .map(|_| "    See also: ".len())
        else {
            offset = end;
            continue;
        };
        let url = line[url_start..].trim();
        let Some((_, anchor)) = url.rsplit_once("/#") else {
            return Err(format!("invalid See also URL: {url}"));
        };
        let linked_start =
            section_start.ok_or_else(|| format!("link outside a help section: {url}"))?;
        sections.push(Section {
            anchor,
            text: &help[linked_start..end],
            url,
        });
        section_start = None;
        after_link = true;
        offset = end;
    }
    if let Some(start) = section_start {
        return Err(format!(
            "help section has no See also link: {}",
            help[start..].lines().next().unwrap_or_default()
        ));
    }
    if sections.is_empty() {
        return Err("help has no See also links".into());
    }
    Ok(sections)
}

fn linked_options(help: &str) -> Result<Vec<Section<'_>>, String> {
    let mut options = Vec::new();
    let mut offset = 0;
    let mut in_options = false;
    let mut option_start = None;
    for line in help.split_inclusive('\n') {
        let end = offset + line.len();
        let heading = line.trim_end();
        if !line.starts_with(char::is_whitespace) && !heading.is_empty() {
            in_options = heading == "OPTIONS";
        } else if in_options
            && line.starts_with("    ")
            && !line.starts_with("        ")
            && !heading.is_empty()
        {
            option_start = Some(offset);
        }
        if in_options {
            if let Some(url) = line.strip_prefix("        See also: ") {
                let url = url.trim();
                let Some((_, anchor)) = url.rsplit_once("/#") else {
                    return Err(format!("invalid See also URL: {url}"));
                };
                let start = option_start.ok_or_else(|| format!("link outside an option: {url}"))?;
                options.push(Section {
                    anchor,
                    text: &help[start..end],
                    url,
                });
                option_start = None;
            }
        }
        offset = end;
    }
    Ok(options)
}

fn is_heading(line: &str) -> bool {
    let heading = line.trim_end();
    !heading.is_empty()
        && !line.starts_with(char::is_whitespace)
        && heading.chars().all(|ch| !ch.is_ascii_lowercase())
}

fn preamble(help: &str) -> &str {
    let mut offset = 0;
    for line in help.split_inclusive('\n') {
        if is_heading(line) && !matches!(line.trim_end(), "NAME" | "SYNOPSIS") {
            return help[..offset].trim_end();
        }
        offset += line.len();
    }
    help.trim_end()
}

fn section_body(help: &str, section: &Section<'_>) -> Result<String, String> {
    let link = section
        .text
        .rfind("    See also: ")
        .expect("a linked section contains its link");
    let mut text = section.text[..link].to_string();
    if section.anchor == "options" {
        for option in linked_options(help)? {
            text = text.replace(option.text, "");
        }
    }
    Ok(text
        .split_once('\n')
        .expect("a help section has a heading and body")
        .1
        .trim_matches('\n')
        .to_string())
}

fn slug(heading: &str) -> String {
    let heading = heading.trim().trim_matches('`');
    if heading.starts_with('-') && !heading.contains('`') {
        return heading.to_ascii_lowercase();
    }
    let mut result = String::new();
    let mut dash = false;
    for ch in heading.chars().flat_map(char::to_lowercase) {
        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' {
            result.push(ch);
            dash = false;
        } else if !result.is_empty() {
            dash = true;
        }
        if dash && !result.ends_with('-') {
            result.push('-');
        }
    }
    result.trim_matches('-').to_string()
}

#[derive(Default)]
struct Markdown {
    headings: Vec<String>,
    options: Vec<String>,
    commands: Vec<(String, String)>,
}

fn scan_markdown(markdown: &str) -> Markdown {
    let mut result = Markdown::default();
    let mut comment = false;
    let mut fence: Option<(char, usize, bool)> = None;
    let mut heading = String::new();
    for line in markdown.lines() {
        if fence.is_none() {
            let mut visible = line;
            loop {
                if comment {
                    let Some(end) = visible.find("-->") else {
                        break;
                    };
                    comment = false;
                    visible = &visible[end + 3..];
                } else if let Some(start) = visible.find("<!--") {
                    comment = true;
                    visible = &visible[start + 4..];
                } else {
                    break;
                }
            }
            if comment || visible != line {
                continue;
            }
        }
        let trimmed = line.trim_start();
        let marker = trimmed.chars().next().unwrap_or(' ');
        let length = trimmed.chars().take_while(|ch| *ch == marker).count();
        if let Some((opening, count, scrut)) = fence {
            if marker == opening && length >= count && trimmed[length..].trim().is_empty() {
                fence = None;
            } else if scrut && line.starts_with("$ ") {
                result.commands.push((heading.clone(), line.to_string()));
            }
            continue;
        }
        if matches!(marker, '`' | '~') && length >= 3 {
            let language = trimmed[length..].trim();
            let scrut = marker == '`' && (language == "scrut" || language.starts_with("scrut "));
            fence = Some((marker, length, scrut));
        } else if let Some(title) = line.strip_prefix("## ") {
            heading = slug(title);
            result.headings.push(heading.clone());
        } else if let Some(title) = line.strip_prefix("### ") {
            heading = slug(title);
            result.options.push(heading.clone());
        } else if line.starts_with("# ") || line.starts_with("#### ") {
            heading.clear();
        }
    }
    result
}

fn document(help: &str, path: &str) -> Result<(), String> {
    let markdown = fs::read_to_string(path).map_err(|error| format!("{path}: {error}"))?;
    validate_document(help, path, &markdown)
}

fn validate_document(help: &str, path: &str, markdown: &str) -> Result<(), String> {
    let command = path
        .rsplit_once('/')
        .map_or(path, |(_, name)| name)
        .strip_suffix(".md")
        .ok_or_else(|| format!("not a Markdown file: {path}"))?;
    let expected_page = format!("{URL_PREFIX}{command}/");
    let parsed = scan_markdown(markdown);
    let headings = &parsed.headings;
    let sections = linked_sections(help)?;
    let linked_anchors: Vec<_> = sections.iter().map(|section| section.anchor).collect();
    let document_anchors: Vec<_> = headings.iter().map(String::as_str).collect();
    if linked_anchors != document_anchors {
        return Err(format!(
            "help sections {linked_anchors:?} do not match document sections {document_anchors:?}"
        ));
    }
    for section in sections {
        if !section.url.starts_with(&expected_page) {
            return Err(format!("{} links outside {expected_page}", section.url));
        }
        let command_line = format!(
            "$ git splice {command} -h | check-help section {}",
            section.anchor
        );
        if !section_body(help, &section)?.is_empty()
            && !parsed
                .commands
                .contains(&(section.anchor.to_string(), command_line.clone()))
        {
            return Err(format!("missing command: {command_line}"));
        }
    }
    let option_headings = &parsed.options;
    for option in linked_options(help)? {
        if !option.url.starts_with(&expected_page) {
            return Err(format!("{} links outside {expected_page}", option.url));
        }
        if !option_headings.iter().any(|anchor| anchor == option.anchor) {
            return Err(format!("{} has no ### heading", option.url));
        }
        let command_line = format!(
            "$ git splice {command} -h | check-help option {}",
            option.anchor
        );
        if !parsed
            .commands
            .contains(&(option.anchor.to_string(), command_line.clone()))
        {
            return Err(format!("missing command: {command_line}"));
        }
    }
    let preamble_command = format!("$ git splice {command} -h | check-help preamble");
    if !parsed
        .commands
        .contains(&(String::new(), preamble_command.clone()))
    {
        return Err(format!("missing command: {preamble_command}"));
    }
    Ok(())
}

fn run() -> Result<(), String> {
    let mut help = String::new();
    io::stdin()
        .read_to_string(&mut help)
        .map_err(|error| error.to_string())?;
    let args: Vec<_> = env::args().skip(1).collect();
    match args.as_slice() {
        [mode] if mode == "preamble" => println!("{}", preamble(&help)),
        [mode, anchor] if mode == "section" => {
            let sections = linked_sections(&help)?;
            let section = sections
                .iter()
                .find(|section| section.anchor == anchor)
                .ok_or_else(|| format!("help has no section linked to #{anchor}"))?;
            let body = section_body(&help, section)?;
            println!("{body}");
        }
        [mode, anchor] if mode == "option" => {
            let options = linked_options(&help)?;
            let matching: Vec<_> = options
                .iter()
                .filter(|option| option.anchor == anchor)
                .collect();
            if matching.is_empty() {
                return Err(format!("help has no option linked to #{anchor}"));
            }
            let grouped = matching.len() > 1;
            for (index, option) in matching.iter().enumerate() {
                let link = option
                    .text
                    .rfind("        See also: ")
                    .expect("a linked option contains its link");
                let text = option.text[..link].trim_end();
                let body = if grouped {
                    text
                } else {
                    text.split_once('\n')
                        .expect("an option has a name and body")
                        .1
                        .trim_end()
                };
                if index > 0 {
                    println!();
                }
                println!("{body}");
            }
        }
        [mode, path] if mode == "document" => document(&help, path)?,
        _ => {
            return Err(
                "usage: check-help (preamble | section <anchor> | option <anchor> | document <page.md>)".into(),
            )
        }
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("check-help: {error}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HELP: &str = "NAME\n    x\n\nDESCRIPTION\n    Explain x.\n\n    See also: https://roschaefer.github.io/git-splice/docs/command-reference/x/#description\n\nOPTIONS\n    --one\n        Does one.\n\n        See also: https://roschaefer.github.io/git-splice/docs/command-reference/x/#--one\n\n    See also: https://roschaefer.github.io/git-splice/docs/command-reference/x/#options\n";
    const PAGE: &str = "# x\n```scrut\n$ git splice x -h | check-help preamble\n```\n## Description\n```scrut\n$ git splice x -h | check-help section description\n```\n## Options\n### `--one`\n```scrut\n$ git splice x -h | check-help option --one\n```\n";

    #[test]
    fn option_links_must_point_to_the_current_page() {
        let help = HELP.replace("x/#--one", "other/#--one");
        assert!(validate_document(&help, "x.md", PAGE)
            .unwrap_err()
            .contains("links outside"));
    }

    #[test]
    fn hidden_or_misplaced_extraction_commands_do_not_satisfy_the_page() {
        assert!(validate_document(HELP, "x.md", PAGE).is_ok());
        let block = "```scrut\n$ git splice x -h | check-help section description\n```";
        let hidden = PAGE.replace(block, &format!("<!--\n{block}\n-->"));
        assert!(validate_document(HELP, "x.md", &hidden).is_err());
        let misplaced = PAGE
            .replace(block, "")
            .replace("## Options", &format!("## Options\n{block}"));
        assert!(validate_document(HELP, "x.md", &misplaced).is_err());
    }

    #[test]
    fn fenced_examples_do_not_supply_headings() {
        let page = format!("{PAGE}\n````markdown\n## Example\n### Fake option\n```text\noutput\n```\n````\n~~~text\n## Another example\n~~~\n");
        assert!(validate_document(HELP, "x.md", &page).is_ok());
        let fake_option = PAGE.replace("### `--one`", "```text\n### `--one`\n```");
        assert!(validate_document(HELP, "x.md", &fake_option).is_err());
    }

    #[test]
    fn heading_slug_matches_the_help_anchors() {
        assert_eq!(slug("No upstream branch"), "no-upstream-branch");
    }

    #[test]
    fn section_links_must_be_the_last_content_in_their_topic() {
        let trailing = format!("{HELP}    A warning after the link.\n");
        assert!(linked_sections(&trailing)
            .unwrap_err()
            .contains("final link"));
        let middle = HELP.replace(
            "\nOPTIONS\n",
            "\n    A warning after the link.\n\nOPTIONS\n",
        );
        assert!(linked_sections(&middle).unwrap_err().contains("final link"));
    }

    #[test]
    fn tilde_fences_do_not_supply_executable_extractions() {
        let page = PAGE.replace("```scrut", "~~~scrut").replace("```", "~~~");
        assert!(validate_document(HELP, "x.md", &page).is_err());
    }

    #[test]
    fn preamble_stops_at_the_first_topic_whatever_its_name() {
        let intro = "NAME\n    x\n\nSYNOPSIS\n    x [options]";
        for topic in ["DESCRIPTION", "OPTIONS", "OUTPUT"] {
            let help = format!("{intro}\n\n{topic}\n    Details.\n");
            assert_eq!(preamble(&help), intro);
        }
    }

    #[test]
    fn reference_links_use_the_published_command_reference_route() {
        assert!(validate_document(HELP, "docs/06-command-reference/x.md", PAGE).is_ok());
        let shortened = HELP.replace("/docs/command-reference/", "/");
        assert!(validate_document(&shortened, "docs/06-command-reference/x.md", PAGE).is_err());
    }

    #[test]
    fn every_help_topic_requires_a_link_including_the_last_one() {
        assert!(linked_sections(HELP).is_ok());
        let last = format!("{HELP}\nEXTRA\n    More help.\n");
        assert!(linked_sections(&last).unwrap_err().contains("EXTRA"));
        let middle = HELP.replace("OPTIONS\n", "EXTRA\n    More help.\n\nOPTIONS\n");
        assert!(linked_sections(&middle).unwrap_err().contains("EXTRA"));
    }

    #[test]
    fn linked_sections_are_the_complete_top_level_sections() {
        let help = "NAME\n    x\n\nSYNOPSIS\n    x\n\nDESCRIPTION\n    first paragraph\n\n    second paragraph\n\n    See also: https://roschaefer.github.io/git-splice/docs/command-reference/x/#description\n\nOPTIONS\n    --one\n        Does one.\n\n        See also: https://roschaefer.github.io/git-splice/docs/command-reference/x/#--one\n\n    See also: https://roschaefer.github.io/git-splice/docs/command-reference/x/#options\n";
        let sections = linked_sections(help).unwrap();
        assert_eq!(sections.len(), 2);
        assert_eq!(sections[0].anchor, "description");
        assert_eq!(
            sections[0].text,
            "DESCRIPTION\n    first paragraph\n\n    second paragraph\n\n    See also: https://roschaefer.github.io/git-splice/docs/command-reference/x/#description\n"
        );
        assert_eq!(sections[1].anchor, "options");
        let options = linked_options(help).unwrap();
        assert_eq!(options.len(), 1);
        assert_eq!(options[0].anchor, "--one");
    }
}
