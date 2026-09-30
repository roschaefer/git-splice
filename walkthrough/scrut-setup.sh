# shellcheck shell=bash
# Sourced by the hidden first scrut block of each walkthrough in this
# folder; see `just docs-check`.
#
# Builds a fresh sandbox in the scrut work directory, like `just
# walkthrough`, and cds into its monorepo. Dates are fixed and the
# developer's git config is ignored, so commit hashes are the same on
# every run.

WALKTHROUGH="$PWD"
export WALKTHROUGH
walkthrough_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$(dirname "$walkthrough_dir"):$walkthrough_dir:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z

"$walkthrough_dir/setup.sh" --dir "$WALKTHROUGH" --no-shell >/dev/null 2>&1 || return
unset walkthrough_dir
cd "$WALKTHROUGH/monorepo" || return

# The walkthroughs show what a terminal shows, stderr included, with the
# sandbox's random path as $WALKTHROUGH, as `just walkthrough` exports it.
# git subtree split's progress counter rewrites itself with \r; only what
# follows the last \r of a line stays.
git() {
  command git "$@" 2>&1 |
    sed -E "s#\r\$##; s#.*\r##; s#$WALKTHROUGH#\$WALKTHROUGH#g"
  return "${PIPESTATUS[0]}"
}
