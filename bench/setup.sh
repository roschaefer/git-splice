#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: bench/setup.sh <dir>

Builds a synthetic monorepo for bench/run.sh in <dir>/monorepo: splices
packages/sub1, packages/sub2, ..., each with local commits since it was
cloned. Halfway through, every splice was pushed, so each upstream holds
the monorepo's own push and the monorepo has changed since -- the usual
state after working on a branch for a while.

Every upstream is reached through git's ext:: transport with a delay per
connection, so network round trips cost something, as they do over SSH.
With plain local paths, fetching would look free.

Environment (defaults in brackets):
  BENCH_SPLICES   number of splices [5]
  BENCH_COMMITS   local commits per splice since it was cloned [10]
  BENCH_LATENCY   seconds of delay per remote connection [0.2]
EOF
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && {
  usage
  exit 0
}
[[ $# -eq 1 && "$1" != -* ]] || {
  usage >&2
  exit 1
}

dir="$1"
splices="${BENCH_SPLICES:-5}"
commits="${BENCH_COMMITS:-10}"
latency="${BENCH_LATENCY:-0.2}"

# The fixture must not depend on, or be slowed down by, the user's config.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Bench GIT_AUTHOR_EMAIL=bench@example.com
export GIT_COMMITTER_NAME=Bench GIT_COMMITTER_EMAIL=bench@example.com

# Quotes a path for the sh -c command in an ext:: URL: single quotes for
# sh, then ext::'s own escapes, "%%" for "%" and "% " for a space.
ext_quote() {
  local quoted="'${1//\'/\'\\\'\'}'"
  quoted="${quoted//%/%%}"
  printf '%s' "${quoted// /% }"
}

rm -rf "$dir"
mkdir -p "$dir/upstream"
dir="$(cd "$dir" && pwd)"

splice="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/git-splice"

git init -q -b main "$dir/monorepo"
cd "$dir/monorepo"
git config protocol.ext.allow always
git config init.defaultBranch main
git commit -q --allow-empty -m "initial commit"

for ((i = 1; i <= splices; i++)); do
  upstream="$dir/upstream/sub$i.git"
  git init -q --bare -b main "$upstream"
  seed="$(mktemp -d)"
  git -C "$seed" init -q -b main
  echo "sub$i" >"$seed/README"
  git -C "$seed" add README
  git -C "$seed" commit -q -m "seed sub$i"
  git -C "$seed" push -q "$upstream" main
  rm -rf "$seed"

  "$splice" clone "ext::sh -c sleep% $latency;% exec% %S% $(ext_quote "$upstream")" "packages/sub$i" >/dev/null
done

# One commit per splice per round, plus unrelated work in between, so the
# history since each sync interleaves all splices like a real monorepo.
commit_round() {
  local round="$1" i
  for ((i = 1; i <= splices; i++)); do
    echo "round $round" >>"packages/sub$i/README"
    git add "packages/sub$i/README"
    git commit -q -m "sub$i: round $round"
  done
  echo "round $round" >>app.txt
  git add app.txt
  git commit -q -m "app: round $round"
}

for ((round = 1; round <= commits / 2; round++)); do
  commit_round "$round"
done
"$splice" push --all >/dev/null 2>&1
for ((round = commits / 2 + 1; round <= commits; round++)); do
  commit_round "$round"
done

# Marks the fixture complete, so an interrupted build is never reused.
touch "$dir/complete"
