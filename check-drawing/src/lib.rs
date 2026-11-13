//! check-drawing: checks a draw.io drawing of commit graphs against the
//! repositories it shows. See README.md next to src/ for the drawing's
//! vocabulary and its limits.
//!
//! What it reads about a splice, its boundary, rebuild, keys and the folders
//! it had, comes from git-splice's own code, so a drawing is checked against
//! what the tool really does.

pub mod check;
pub mod diagram;
pub mod history;
pub mod labels;
pub mod placement;
pub mod tree;
