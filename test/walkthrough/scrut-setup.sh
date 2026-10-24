# shellcheck shell=bash
# Sourced by the hidden first scrut block of each walkthrough in this
# folder; see `just docs-check`.
#
# Builds the walkthrough's repositories in the scrut work directory, and
# cds into its monorepo. Dates are fixed and the developer's git config
# is ignored, so commit hashes are the same on every run.

WALKTHROUGH="$PWD"
export WALKTHROUGH
walkthrough_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="$(cd "$walkthrough_dir/../.." && pwd):$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z

"$walkthrough_dir/setup.sh" "$WALKTHROUGH" >/dev/null 2>&1 || return
# Who commits in a clone of an upstream.
export GIT_CONFIG_GLOBAL="$WALKTHROUGH/.gitconfig"
unset walkthrough_dir
cd "$WALKTHROUGH/monorepo" || return

# The walkthroughs show what a terminal shows, stderr included, with the
# work directory's random path as $WALKTHROUGH.
# Git's progress counters rewrite themselves with \r; only what follows
# the last \r of a line stays.
git() {
  command git "$@" 2>&1 |
    sed -E "s#\r\$##; s#.*\r##; s#$WALKTHROUGH#\$WALKTHROUGH#g"
  return "${PIPESTATUS[0]}"
}
