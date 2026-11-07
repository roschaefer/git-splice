//! --message-template: the message of the commits clone, init, merge and pull
//! write, with placeholders each commit fills in.

use crate::util::*;

/// At most this many commits in {shortlog}, like 'git merge --log'.
const SHORTLOG_LIMIT: usize = 20;

const PLACEHOLDERS: [&str; 9] = [
    "command", "path", "upstream", "old", "new", "full-old", "full-new", "count", "shortlog",
];

/// What a command fills a template with. None: the command has no such value,
/// e.g. no old synced commit for clone.
#[derive(Clone, Copy, Default)]
pub struct Message<'a> {
    pub command: &'a str,
    pub path: &'a str,
    pub upstream: Option<&'a str>,
    pub old: Option<&'a str>,
    pub new: Option<&'a str>,
}

/// For the check before a command writes anything: which values it has, not
/// what they are.
pub const KNOWN: Option<&str> = Some("");

impl Message<'_> {
    fn value(&self, name: &str) -> Option<String> {
        let range = || Some(format!("{}..{}", self.old?, self.new?));
        match name {
            "command" => Some(self.command.to_string()),
            "path" => Some(self.path.to_string()),
            "upstream" => self.upstream.map(str::to_string),
            "old" => self.old.map(|old| short(old).to_string()),
            "new" => self.new.map(|new| short(new).to_string()),
            "full-old" => self.old.map(str::to_string),
            "full-new" => self.new.map(str::to_string),
            "count" => {
                let range = range()?;
                Some(
                    git(&["rev-list", "--count", "--no-merges", &range])
                        .out()
                        .unwrap_or_default(),
                )
            }
            "shortlog" => Some(shortlog(&range()?)),
            _ => None,
        }
    }
}

/// The commits in <range> as 'git merge --log' lists them: one subject per
/// line, indented, newest first, without merge commits, and "..." after the
/// first SHORTLOG_LIMIT.
fn shortlog(range: &str) -> String {
    let limit = format!("--max-count={}", SHORTLOG_LIMIT + 1);
    let subjects = git(&["log", "--no-merges", "--format=%s", &limit, range])
        .out()
        .unwrap_or_default();
    let mut lines: Vec<String> = subjects.lines().map(|s| format!("  {s}")).collect();
    if lines.len() > SHORTLOG_LIMIT {
        lines.truncate(SHORTLOG_LIMIT);
        lines.push("  ...".to_string());
    }
    lines.join("\n")
}

enum Piece {
    Text(String),
    Placeholder(String),
}

pub struct Template {
    /// Where the template comes from, for messages: the option or the key.
    source: &'static str,
    pieces: Vec<Piece>,
}

impl Template {
    /// The template --message-template gives, or nothing without one.
    pub fn given(text: &str) -> Res<Option<Template>> {
        if text.is_empty() {
            return Ok(None);
        }
        let source = "--message-template";
        match Template::parse(source, text) {
            Ok(template) => Ok(Some(template)),
            Err(problem) => die(format!("{source}: {problem}")),
        }
    }

    /// <text> as text and {placeholder}s; {{ and }} are literal braces.
    fn parse(source: &'static str, text: &str) -> Result<Template, String> {
        if text.trim().is_empty() {
            return Err("it's empty".to_string());
        }
        let mut pieces = Vec::new();
        let mut literal = String::new();
        let mut chars = text.chars().peekable();
        while let Some(c) = chars.next() {
            match c {
                '{' if chars.peek() == Some(&'{') => {
                    chars.next();
                    literal.push('{');
                }
                '}' if chars.peek() == Some(&'}') => {
                    chars.next();
                    literal.push('}');
                }
                '{' => {
                    let mut name = String::new();
                    loop {
                        match chars.next() {
                            Some('}') => break,
                            Some(c) => name.push(c),
                            None => {
                                return Err(format!(
                                "'{{{name}' has no closing '}}' -- write '{{{{' for a literal '{{'"
                            ))
                            }
                        }
                    }
                    if !PLACEHOLDERS.contains(&name.as_str()) {
                        return Err(format!(
                            "unknown placeholder {{{name}}} -- the placeholders are {}",
                            PLACEHOLDERS.map(|p| format!("{{{p}}}")).join(" ")
                        ));
                    }
                    if !literal.is_empty() {
                        pieces.push(Piece::Text(std::mem::take(&mut literal)));
                    }
                    pieces.push(Piece::Placeholder(name));
                }
                '}' => return Err("'}' has no opening '{' -- write '}}' for a literal '}'".into()),
                c => literal.push(c),
            }
        }
        if !literal.is_empty() {
            pieces.push(Piece::Text(literal));
        }
        Ok(Template { source, pieces })
    }

    /// The first placeholder <message> has no value for.
    fn missing(&self, message: &Message) -> Option<&str> {
        self.pieces.iter().find_map(|piece| match piece {
            Piece::Placeholder(name) => {
                let known = match name.as_str() {
                    "upstream" => message.upstream.is_some(),
                    "old" | "full-old" => message.old.is_some(),
                    "new" | "full-new" => message.new.is_some(),
                    "count" | "shortlog" => message.old.is_some() && message.new.is_some(),
                    _ => true,
                };
                (!known).then_some(name.as_str())
            }
            Piece::Text(_) => None,
        })
    }

    /// Ends the command if it can't fill in every placeholder; <message> says
    /// which values it has.
    pub fn require(&self, message: &Message) -> Res<()> {
        match self.missing(message) {
            Some(name) => die(format!(
                "{}: {} has no value for {{{name}}} -- give the commit a message with -m",
                self.source, message.command
            )),
            None => Ok(()),
        }
    }

    /// The message for <message>'s commit; fails the splice if a value is
    /// missing here, e.g. {old} for a splice with no synced commit yet.
    pub fn render(&self, message: &Message) -> Res<String> {
        if let Some(name) = self.missing(message) {
            return fail(format!(
                "{}: no value for {{{name}}} in {} -- give the commit a message with -m",
                message.path, self.source
            ));
        }
        let mut text = String::new();
        for piece in &self.pieces {
            match piece {
                Piece::Text(literal) => text.push_str(literal),
                Piece::Placeholder(name) => text.push_str(&message.value(name).unwrap_or_default()),
            }
        }
        Ok(text.trim_end().to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn render(template: &str, message: &Message) -> String {
        Template::parse("test", template)
            .ok()
            .and_then(|t| t.render(message).ok())
            .unwrap_or_default()
    }

    #[test]
    fn fills_in_placeholders_and_keeps_doubled_braces_literal() {
        let message = Message {
            command: "pull",
            path: "vendor/a",
            upstream: Some("main"),
            old: Some("1111111aaaa"),
            new: Some("2222222bbbb"),
        };
        assert_eq!(
            render(
                "{{x}} {command} {path} {upstream} {old}..{new} {full-new}",
                &message
            ),
            "{x} pull vendor/a main 1111111..2222222 2222222bbbb"
        );
    }

    #[test]
    fn refuses_unknown_placeholders_and_unbalanced_braces() {
        for template in ["{nope}", "a {path", "a } b", "", "  \n"] {
            assert!(Template::parse("test", template).is_err(), "{template:?}");
        }
    }

    #[test]
    fn a_placeholder_without_a_value_is_missing() {
        let template = Template::parse("test", "{command} {path} {shortlog}")
            .ok()
            .unwrap();
        let init = Message {
            command: "init",
            path: "a",
            ..Message::default()
        };
        assert_eq!(template.missing(&init), Some("shortlog"));
        let known = Message {
            old: KNOWN,
            new: KNOWN,
            ..init
        };
        assert_eq!(template.missing(&known), None);
    }
}
