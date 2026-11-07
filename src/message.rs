//! --message-template and splice.messageTemplate: the message of the commits
//! clone, init, merge and pull write, with placeholders each commit fills in.

use crate::util::*;

/// The message of clone's, merge's and pull's commits without -m or
/// --message-template.
pub const DEFAULT: &str = "splice: {command} {path} from {upstream} at {new}";
/// The default for clone --from-submodule, which has no upstream branch.
pub const DEFAULT_FROM_SUBMODULE: &str = "splice: clone {path} from submodule at {new}";
/// The default for init, which has no synced commit yet.
pub const DEFAULT_INIT: &str = "splice: init {path}";
/// The git config key with the template for commands given neither -m nor
/// --message-template.
pub const KEY: &str = "splice.messageTemplate";

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
    /// The value of placeholder <name>, which Template::missing found it has;
    /// fails the splice if Git can't list the commits {count} and
    /// {shortlog} need.
    fn value(&self, name: &str) -> Res<String> {
        let old = self.old.unwrap_or_default();
        let new = self.new.unwrap_or_default();
        let range = format!("{old}..{new}");
        let listed = |output: Option<String>| match output {
            Some(output) => Ok(output),
            None => fail(format!(
                "{}: can't list the commits {}..{} for {{{name}}}",
                self.path,
                short(old),
                short(new)
            )),
        };
        Ok(match name {
            "command" => self.command.to_string(),
            "path" => self.path.to_string(),
            "upstream" => self.upstream.unwrap_or_default().to_string(),
            "old" => short(old).to_string(),
            "new" => short(new).to_string(),
            "full-old" => old.to_string(),
            "full-new" => new.to_string(),
            "count" => listed(
                git(&["rev-list", "--count", "--no-merges", &range])
                    .q()
                    .out(),
            )?,
            "shortlog" => shortlog(&listed(
                git(&[
                    "log",
                    "--no-show-signature",
                    "--no-merges",
                    "--format=%s",
                    &format!("--max-count={}", SHORTLOG_LIMIT + 1),
                    &range,
                ])
                .q()
                .out(),
            )?),
            _ => String::new(),
        })
    }
}

/// <subjects>, newest first, as 'git merge --log' lists them: one per line,
/// indented, and "..." after the first SHORTLOG_LIMIT.
fn shortlog(subjects: &str) -> String {
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

    /// One of the default templates above.
    pub fn default(text: &str) -> Res<Template> {
        Template::parse("default message", text)
            .or_else(|problem| die(format!("default message: {problem}")))
    }

    /// The template splice.messageTemplate sets, or nothing if it's unset.
    pub fn configured() -> Res<Option<Template>> {
        let Some(text) = git(&["config", "--get", KEY]).q().out() else {
            return Ok(None);
        };
        if text.trim().is_empty() {
            return die(format!(
                "{KEY}: it's empty -- unset it for the default messages"
            ));
        }
        match Template::parse(KEY, &text) {
            Ok(template) => Ok(Some(template)),
            Err(problem) => die(format!("{KEY}: {problem}")),
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
                Piece::Placeholder(name) => text.push_str(&message.value(name)?),
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
    fn the_defaults_are_templates_that_fill_in_the_former_fixed_messages() {
        let pull = Message {
            command: "pull",
            path: "vendor/a",
            upstream: Some("main"),
            old: Some("1111111aaaa"),
            new: Some("2222222bbbb"),
        };
        assert_eq!(
            render(DEFAULT, &pull),
            "splice: pull vendor/a from main at 2222222"
        );
        let submodule = Message {
            command: "clone",
            path: "vendor/a",
            new: Some("2222222bbbb"),
            ..Message::default()
        };
        assert_eq!(
            render(DEFAULT_FROM_SUBMODULE, &submodule),
            "splice: clone vendor/a from submodule at 2222222"
        );
        let init = Message {
            command: "init",
            path: "lib/a",
            ..Message::default()
        };
        assert_eq!(render(DEFAULT_INIT, &init), "splice: init lib/a");
    }

    #[test]
    fn count_and_shortlog_fail_if_git_cant_list_the_commits() {
        let unknown = Message {
            command: "pull",
            path: "vendor/a",
            upstream: Some("main"),
            old: Some("0000000000000000000000000000000000000001"),
            new: Some("0000000000000000000000000000000000000002"),
        };
        for template in ["{count}", "{shortlog}"] {
            let template = Template::parse("test", template).ok().unwrap();
            assert!(template.render(&unknown).is_err());
        }
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
