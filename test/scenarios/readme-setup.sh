# shellcheck shell=bash
# Sourced by the hidden scrut block of each scenario's README.md, which
# then calls build_scenario with its scenario function; see `just
# docs-check`.
#
# Dates are fixed and the developer's git config is ignored, so commit
# hashes are the same on every run.

PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd):$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
UPSTREAM="$PWD/upstream"
export UPSTREAM

# shellcheck source=test/helpers/fixtures.bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/fixtures.bash"

# Runs scenario function $1 from the README's setup.bash, the function the
# bats tests call too, and cds into the monorepo it built. The remote is
# the bare repository $UPSTREAM.
build_scenario() {
  # shellcheck disable=SC1091
  source "$TESTDIR/setup.bash"
  "$1" "$PWD/monorepo" "$UPSTREAM" >/dev/null 2>&1 || return
  cd monorepo || return
  scenario_built=1
}

# Once the scenario is built, the READMEs show what a terminal shows,
# stderr included, with the remote's path as $UPSTREAM. git subtree
# split's progress counter rewrites itself with \r; only what follows the
# last \r of a line stays.
git() {
  if [[ -z "${scenario_built:-}" ]]; then
    command git "$@"
    return
  fi
  command git "$@" 2>&1 |
    sed -E "s#\r\$##; s#.*\r##; s#$UPSTREAM#\$UPSTREAM#g"
  return "${PIPESTATUS[0]}"
}
