use std::env;
use std::fs;
use std::io::{self, Read};
use std::process::ExitCode;

const URL_PREFIX: &str = "https://roschaefer.github.io/git-splice/";

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
    for line in help.split_inclusive('\n') {
        let end = offset + line.len();
        let heading = line.trim_end();
        if !heading.is_empty()
            && !line.starts_with(char::is_whitespace)
            && heading.chars().all(|ch| !ch.is_ascii_lowercase())
        {
            section_start = Some(offset);
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
        offset = end;
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

fn preamble(help: &str) -> &str {
    let description = help.find("\nDESCRIPTION\n").unwrap_or(help.len());
    help[..description].trim_end()
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

fn document(help: &str, path: &str) -> Result<(), String> {
    let markdown = fs::read_to_string(path).map_err(|error| format!("{path}: {error}"))?;
    let command = path
        .rsplit_once('/')
        .map_or(path, |(_, name)| name)
        .strip_suffix(".md")
        .ok_or_else(|| format!("not a Markdown file: {path}"))?;
    let expected_page = format!("{URL_PREFIX}{command}/");
    let headings: Vec<_> = markdown
        .lines()
        .filter_map(|line| line.strip_prefix("## ").map(slug))
        .collect();
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
            && !markdown.lines().any(|line| line == command_line)
        {
            return Err(format!("missing command: {command_line}"));
        }
    }
    let option_headings: Vec<_> = markdown
        .lines()
        .filter_map(|line| line.strip_prefix("### ").map(slug))
        .collect();
    for option in linked_options(help)? {
        if !option_headings.iter().any(|anchor| anchor == option.anchor) {
            return Err(format!("{} has no ### heading", option.url));
        }
        let command_line = format!(
            "$ git splice {command} -h | check-help option {}",
            option.anchor
        );
        if !markdown.lines().any(|line| line == command_line) {
            return Err(format!("missing command: {command_line}"));
        }
    }
    let preamble_command = format!("$ git splice {command} -h | check-help preamble");
    if !markdown.lines().any(|line| line == preamble_command) {
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

    #[test]
    fn heading_slug_matches_the_help_anchors() {
        assert_eq!(slug("No upstream branch"), "no-upstream-branch");
    }

    #[test]
    fn linked_sections_are_the_complete_top_level_sections() {
        let help = "NAME\n    x\n\nSYNOPSIS\n    x\n\nDESCRIPTION\n    first paragraph\n\n    second paragraph\n\n    See also: https://roschaefer.github.io/git-splice/x/#description\n\nOPTIONS\n    --one\n        Does one.\n\n        See also: https://roschaefer.github.io/git-splice/x/#--one\n\n    See also: https://roschaefer.github.io/git-splice/x/#options\n";
        let sections = linked_sections(help).unwrap();
        assert_eq!(sections.len(), 2);
        assert_eq!(sections[0].anchor, "description");
        assert_eq!(
            sections[0].text,
            "DESCRIPTION\n    first paragraph\n\n    second paragraph\n\n    See also: https://roschaefer.github.io/git-splice/x/#description\n"
        );
        assert_eq!(sections[1].anchor, "options");
        let options = linked_options(help).unwrap();
        assert_eq!(options.len(), 1);
        assert_eq!(options[0].anchor, "--one");
    }
}
