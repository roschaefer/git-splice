//! Typed observations around synchronization steps.

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FetchedUpstream {
    pub path: String,
    pub upstream: String,
    pub url: String,
    /// The download report failed; this does not describe synced-history validity.
    pub failed: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ExecutionEvent {
    /// All batch workers have joined; reporting, key cleanup and validation may follow.
    AfterFetch { fetched: Vec<FetchedUpstream> },
    /// HEAD changed without an unresolved splice conflict; discovery may follow.
    AfterMerge {
        path: String,
        head_before: String,
        head_after: String,
    },
    /// A commit is prepared for publication; this step has not pushed it yet.
    AfterRebuild { path: String, commit: String },
    /// Publication and its local fetched-ref update succeeded.
    AfterPush { path: String, commit: String },
    /// The fold stage is about to run, including when it has nothing to fold.
    BeforeFold { roots: Vec<String>, head: String },
    /// Folding returned successfully; rebase replay and cleanup may follow.
    AfterFold {
        roots: Vec<String>,
        head_before: String,
        head_after: String,
    },
}

/// Result of driving an operation to completion or a requested event boundary.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ExecutionOutcome {
    Paused(ExecutionEvent),
    Complete(i32),
}
