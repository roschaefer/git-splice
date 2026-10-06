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
# bats tests call too, and cds into the monorepo it built. The upstream is
# the bare repository $UPSTREAM.
build_scenario() {
  # shellcheck disable=SC1091
  source "$TESTDIR/setup.bash"
  "$1" "$PWD/monorepo" "$UPSTREAM" >/dev/null 2>&1 || return
  cd monorepo || return
  scenario_built=1
}

# Used by this directory's README to keep the executable documentation
# contract honest: its table of contents includes every folder and document,
# every scenario has one loadable setup that sources nothing but its parent
# scenario's, and every document links to and invokes that setup.
check_scenario_setups() {
  local setup directory document name function documents relative toc sources
  toc="$(sed -n '/^## Table of contents$/,/^This check /p' "$TESTDIR/README.md")"
  # Sorted by folder, so a parent scenario comes before its children.
  while IFS= read -r directory; do
    setup="$directory/setup.bash"
    relative="${directory#"$TESTDIR/"}"
    name="$(basename "$directory")"
    function="scenario_${name//-/_}"
    grep -Fq "($relative/)" <<<"$toc" || return
    sources="$(grep -E '^[[:space:]]*(source|\.)[[:space:]]' "$setup")"
    if [[ "$relative" == */* ]]; then
      # shellcheck disable=SC2016 # the literal line a child setup.bash has
      [[ "$sources" == 'source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"' ]] || return
    else
      [[ -z "$sources" ]] || return
    fi
    unset -f "$function"
    # shellcheck disable=SC1090
    source "$setup"
    declare -F "$function" >/dev/null || return
    documents=0
    for document in "$directory"/*.md; do
      [[ -f "$document" ]] || continue
      grep -Fq "(${document#"$TESTDIR/"})" <<<"$toc" || return
      grep -Fq 'setup.bash`](setup.bash)' "$document" || return
      grep -Fq "$ build_scenario $function" "$document" || return
      ((documents += 1))
    done
    ((documents > 0)) || return
    printf 'ok %s (%d document%s)\n' \
      "$relative" "$documents" "$([[ $documents -eq 1 ]] || printf s)"
  done < <(find "$TESTDIR" -mindepth 2 -name setup.bash | sed 's#/setup\.bash$##' | LC_ALL=C sort)
}

# Once the scenario is built, the READMEs show what a terminal shows,
# stderr included, with the upstream's path as $UPSTREAM. Git's progress
# counters rewrite themselves with \r; only what follows the last \r of a
# line stays.
git() {
  if [[ -z "${scenario_built:-}" ]]; then
    command git "$@"
    return
  fi
  command git "$@" 2>&1 |
    sed -E "s#\r\$##; s#.*\r##; s#$UPSTREAM#\$UPSTREAM#g"
  return "${PIPESTATUS[0]}"
}
