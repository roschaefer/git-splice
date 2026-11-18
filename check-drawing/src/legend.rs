//! The legend: what a fill or an outline on a commit says about the
//! repository. check.rs sees only styles, and gathers neutral facts about each
//! drawn commit; this module ties the two together. A drawing's legend picks a
//! meaning by the words next to its sample, and may give it another color than
//! the default one, as a last resort. A sample without words means what its
//! style means by default; one with words no meaning has is left unchecked.

/// What the repository says about one drawn commit, gathered by check.rs.
#[derive(Default)]
pub struct Facts {
    /// The next rebuild walks it: a monorepo commit on the first-parent
    /// history since B.
    pub walked: bool,
    /// Why the next rebuild carries it across, if it does: R copies it, or
    /// it's R's copy of a commit since B.
    pub carried: Option<&'static str>,
    /// Its .splice records another synced commit than its first parent's.
    pub records_pull: bool,
    /// A pull drawn here brought it in.
    pub brought_in: bool,
    /// Its message, subject and body.
    pub message: String,
    /// A rebuilt copy of another drawn commit, labelled after it with a '.
    pub copy: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Attr {
    Fill,
    Outline,
}

pub struct Meaning {
    /// The words a legend writes next to its sample.
    pub words: &'static [&'static str],
    pub attr: Attr,
    /// Its color unless a legend gives it another.
    pub color: &'static str,
    /// What a commit with the color but without the meaning is told.
    pub unwanted: &'static str,
    /// Why a commit has the meaning, if it has.
    rule: fn(&Facts) -> Option<&'static str>,
}

impl Meaning {
    pub fn reason(&self, facts: &Facts) -> Option<&'static str> {
        (self.rule)(facts)
    }
}

/// The marker a scenario writes into the message of the commit that resolves
/// a conflict, visible in its code block.
pub const RESOLVED: &str = "(resolved)";

/// The meanings every drawing shares, unless its legend says otherwise.
pub const DEFAULT: [Meaning; 4] = [
    Meaning {
        words: &["walked commits", "commits the rebuild walks"],
        attr: Attr::Fill,
        color: "#E0E0E0",
        unwanted: "is filled, but the rebuild doesn't walk it: leave it white",
        rule: |f| f.walked.then_some("a commit the rebuild walks"),
    },
    Meaning {
        words: &[
            "commits carried over",
            "carried over",
            "commit to carry over",
        ],
        attr: Attr::Outline,
        color: "#E07000",
        unwanted: "is outlined in color, but the rebuild doesn't carry it across: outline it black",
        rule: |f| f.carried,
    },
    Meaning {
        words: &["pulled", "pulled in"],
        attr: Attr::Outline,
        color: "#0070E0",
        unwanted:
            "is outlined blue, but it neither records a pull nor came in with one: outline it black",
        rule: |f| {
            if f.records_pull {
                Some("a commit that records a pull")
            } else if f.brought_in {
                Some("a commit a pull brought in")
            } else {
                None
            }
        },
    },
    Meaning {
        words: &["stopped at a conflict"],
        attr: Attr::Fill,
        color: "#F8CECC",
        unwanted: "is filled, but its message doesn't say it resolved a conflict: leave it white",
        rule: |f| {
            (!f.copy && f.message.contains(RESOLVED)).then_some("a commit that resolved a conflict")
        },
    },
];

/// The meaning a legend's words name, ignoring case and spaces around them.
pub fn by_words(words: &str) -> Option<&'static Meaning> {
    let words = words.trim().to_lowercase();
    DEFAULT.iter().find(|m| m.words.contains(&words.as_str()))
}

/// The meaning a style has by default.
pub fn by_style(attr: Attr, color: &str) -> Option<&'static Meaning> {
    DEFAULT
        .iter()
        .find(|m| m.attr == attr && m.color.eq_ignore_ascii_case(color))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn facts() -> Facts {
        Facts::default()
    }

    #[test]
    fn words_pick_the_meaning_whatever_their_case() {
        assert_eq!(by_words(" Pulled In ").map(|m| m.color), Some("#0070E0"));
        assert_eq!(by_words("carried over").map(|m| m.color), Some("#E07000"));
        assert!(by_words("found by split").is_none());
    }

    #[test]
    fn a_style_without_words_means_its_default() {
        assert_eq!(
            by_style(Attr::Fill, "#e0e0e0").map(|m| m.words[0]),
            Some("walked commits")
        );
        assert!(by_style(Attr::Outline, "#E0E0E0").is_none());
    }

    #[test]
    fn pulled_takes_the_pull_and_what_it_brought_in() {
        let pulled = by_words("pulled").unwrap();
        assert_eq!(
            pulled.reason(&Facts {
                records_pull: true,
                ..facts()
            }),
            Some("a commit that records a pull")
        );
        assert_eq!(
            pulled.reason(&Facts {
                brought_in: true,
                ..facts()
            }),
            Some("a commit a pull brought in")
        );
        assert_eq!(pulled.reason(&facts()), None);
    }

    #[test]
    fn stopped_at_a_conflict_is_read_from_the_resolving_commits_message() {
        let stopped = by_words("stopped at a conflict").unwrap();
        let resolved = Facts {
            message: format!("p: pull vendor/a {RESOLVED}"),
            ..facts()
        };
        assert_eq!(
            stopped.reason(&resolved),
            Some("a commit that resolved a conflict")
        );
        let folded = Facts {
            message: format!("p\n\npull b\npull c {RESOLVED}\n"),
            ..facts()
        };
        assert!(stopped.reason(&folded).is_some());
        assert_eq!(
            stopped.reason(&Facts {
                message: "p: pull vendor/a".into(),
                ..facts()
            }),
            None
        );
        // Its copy in a splice has the same message, but resolved nothing.
        let copy = Facts {
            message: format!("p {RESOLVED}"),
            copy: true,
            ..facts()
        };
        assert_eq!(stopped.reason(&copy), None);
    }
}
