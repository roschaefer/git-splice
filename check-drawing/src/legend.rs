//! The legend every drawing shares: what each fill and outline color says
//! about a commit, the words a drawing's legend writes for it, and the rule
//! that decides it from facts about the commit. check.rs gathers the facts
//! from the drawing and the repository, and compares the colors drawn; trees
//! take their colors and words from here too.

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
    /// A pull stopped at a conflict merges it in.
    pub merged_in: bool,
    /// A rebase stopped at a conflict replays it.
    pub replayed: bool,
    /// Its message, subject and body.
    pub message: String,
    /// A rebuilt copy of another commit, labelled after it with a '.
    pub copy: bool,
}

/// A color a drawing's legend may add to the central legend's: once the
/// legend has a sample of it, every commit with its meaning has it, and no
/// other. A legend may explain any other color too, which nothing checks.
pub struct Mark {
    /// The style key it sets.
    pub attr: &'static str,
    pub color: &'static str,
    pub name: &'static str,
    /// How to give a commit the mark.
    pub fix: &'static str,
    /// What a commit with the mark but without its meaning is told.
    pub unwanted: &'static str,
    /// What a legend writes next to its sample: the first, unless a drawing
    /// shows the situation the others name.
    pub words: &'static [&'static str],
    /// Why a commit has the meaning, if it has.
    rule: fn(&Facts) -> Option<&'static str>,
}

impl Mark {
    pub fn reason(&self, facts: &Facts) -> Option<&'static str> {
        (self.rule)(facts)
    }
}

pub const WALKED_FILL: &str = "#E0E0E0";
pub const CARRIED_OUTLINE: &str = "#E07000";
pub const PULLED_OUTLINE: &str = "#0070E0";
pub const CONFLICT_OUTLINE: &str = "#D00000";
pub const RESOLVED_FILL: &str = "#F8CECC";

/// What a scenario writes into the message of the commit that resolves a
/// conflict, in plain sight in its code block: nothing else in the repository
/// remembers the conflict afterwards.
pub const RESOLVED: &str = "(resolved)";

pub const MARKS: [Mark; 5] = [
    Mark {
        attr: "fillColor",
        color: WALKED_FILL,
        name: "a grey fill",
        fix: "fill it grey",
        unwanted: "is filled, but the rebuild doesn't walk it: leave it white",
        words: &["walked commits"],
        rule: |f| f.walked.then_some("a commit the rebuild walks"),
    },
    Mark {
        attr: "strokeColor",
        color: CARRIED_OUTLINE,
        name: "an orange outline",
        fix: "outline it orange",
        unwanted: "is outlined in color, but the rebuild doesn't carry it across: outline it black",
        words: &["commits carried over"],
        rule: |f| f.carried,
    },
    Mark {
        attr: "strokeColor",
        color: PULLED_OUTLINE,
        name: "a blue outline",
        fix: "outline it blue",
        unwanted:
            "is outlined blue, but it neither records a pull nor came in with one: outline it black",
        words: &["pulled"],
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
    Mark {
        attr: "strokeColor",
        color: CONFLICT_OUTLINE,
        name: "a red outline",
        fix: "outline it red",
        unwanted:
            "is outlined red, but no stopped pull or rebase conflicts on it: outline it black",
        words: &["merged in, conflicts", "replayed, conflicts"],
        rule: |f| {
            if f.replayed {
                Some("the commit a stopped rebase replays")
            } else if f.merged_in {
                Some("the commit a stopped pull merges in")
            } else {
                None
            }
        },
    },
    Mark {
        attr: "fillColor",
        color: RESOLVED_FILL,
        name: "a red fill",
        fix: "fill it red",
        unwanted:
            "is filled red, but its message doesn't say it resolved a conflict: leave it white",
        words: &["stopped at a conflict"],
        rule: |f| {
            (!f.copy && f.message.contains(RESOLVED)).then_some("a commit that resolved a conflict")
        },
    },
];

/// The mark with color <color> as <attr>, if the shared legend has one.
pub fn mark(attr: &str, color: &str) -> Option<&'static Mark> {
    MARKS
        .iter()
        .find(|m| m.attr == attr && m.color.eq_ignore_ascii_case(color))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reason(color: &str, facts: Facts) -> Option<&'static str> {
        MARKS
            .iter()
            .find(|m| m.color == color)
            .unwrap()
            .reason(&facts)
    }

    #[test]
    fn pulled_takes_the_pull_and_what_it_brought_in() {
        let pull = Facts {
            records_pull: true,
            ..Facts::default()
        };
        assert_eq!(
            reason(PULLED_OUTLINE, pull),
            Some("a commit that records a pull")
        );
        let brought = Facts {
            brought_in: true,
            ..Facts::default()
        };
        assert_eq!(
            reason(PULLED_OUTLINE, brought),
            Some("a commit a pull brought in")
        );
        assert_eq!(reason(PULLED_OUTLINE, Facts::default()), None);
    }

    #[test]
    fn red_outline_names_the_stopped_operation() {
        let replayed = Facts {
            replayed: true,
            ..Facts::default()
        };
        assert_eq!(
            reason(CONFLICT_OUTLINE, replayed),
            Some("the commit a stopped rebase replays")
        );
        let merged = Facts {
            merged_in: true,
            ..Facts::default()
        };
        assert_eq!(
            reason(CONFLICT_OUTLINE, merged),
            Some("the commit a stopped pull merges in")
        );
    }

    #[test]
    fn red_fill_is_read_from_the_resolving_commits_message() {
        let resolved = Facts {
            message: format!("m1: a local {RESOLVED}"),
            ..Facts::default()
        };
        assert_eq!(
            reason(RESOLVED_FILL, resolved),
            Some("a commit that resolved a conflict")
        );
        // A fold keeps each pull's subject in its body.
        let folded = Facts {
            message: format!("p\n\npull b\npull c {RESOLVED}\n"),
            ..Facts::default()
        };
        assert!(reason(RESOLVED_FILL, folded).is_some());
        let plain = Facts {
            message: "m1: a local".into(),
            ..Facts::default()
        };
        assert_eq!(reason(RESOLVED_FILL, plain), None);
    }

    #[test]
    fn a_rebuilt_copy_resolved_nothing_though_it_has_the_message() {
        let copy = Facts {
            message: format!("p {RESOLVED}"),
            copy: true,
            ..Facts::default()
        };
        assert_eq!(reason(RESOLVED_FILL, copy), None);
    }

    #[test]
    fn a_mark_is_found_by_its_color_in_any_case() {
        assert_eq!(
            mark("strokeColor", "#0070e0").map(|m| m.name),
            Some("a blue outline")
        );
        assert!(mark("fillColor", PULLED_OUTLINE).is_none());
    }
}
