#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF_USAGE'
usage: bench/run.sh [--compare <git-splice>] [--runs <n>]

Times git splice commands with hyperfine on the fixture bench/setup.sh
builds, and prints the results as Markdown tables, one per command.

The commands run with this checkout's git-splice. With --compare, each
table also has a row for <git-splice> -- another checkout's entry point,
e.g. a worktree of main -- and hyperfine reports how the two relate.

The fixture is built once per BENCH_SPLICES/BENCH_COMMITS/BENCH_LATENCY
combination and kept in $BENCH_DIR [${TMPDIR:-/tmp}/git-splice-bench];
see bench/setup.sh --help. The timed commands only read it, apart from
fetch updating refs/splices/ to what they already are. pull isn't timed:
it's fetch plus a merge whose work depends on how a version classifies the
fixture, so versions wouldn't do the same work.

Options:
  --compare <git-splice>    also time this entry point
  --runs <n>                runs per command [3]
EOF_USAGE
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
head_entrypoint="$here/../git-splice"
compare_entrypoint=""
runs=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --compare)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 1
      }
      compare_entrypoint="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
      shift
      ;;
    --runs)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 1
      }
      runs="$2"
      shift
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

export BENCH_SPLICES="${BENCH_SPLICES:-5}"
export BENCH_COMMITS="${BENCH_COMMITS:-10}"
export BENCH_LATENCY="${BENCH_LATENCY:-0.2}"
fixture="${BENCH_DIR:-${TMPDIR:-/tmp}/git-splice-bench}/s$BENCH_SPLICES-c$BENCH_COMMITS-l$BENCH_LATENCY"
if [[ ! -e "$fixture/complete" ]]; then
  "$here/setup.sh" "$fixture" >&2
fi

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
cd "$fixture/monorepo"

printf '%d splices, each with %d commits since it was cloned and %d since its push; %ss latency per upstream connection; %s, bash %s.\n' \
  "$BENCH_SPLICES" "$BENCH_COMMITS" "$((BENCH_COMMITS - BENCH_COMMITS / 2))" "$BENCH_LATENCY" \
  "$(git --version)" "${BASH_VERSION%%(*}"

table="$(mktemp)"
trap 'rm -f "$table"' EXIT
for cmd in status diff log fetch; do
  # hyperfine runs each command through a shell, so the paths are quoted.
  args=(--warmup 1 --runs "$runs" --style none --export-markdown "$table"
    -n this "$(printf '%q' "$head_entrypoint") $cmd")
  [[ -n "$compare_entrypoint" ]] && args+=(-n compared "$(printf '%q' "$compare_entrypoint") $cmd")
  hyperfine "${args[@]}" >/dev/null
  printf '\n### git splice %s\n\n' "$cmd"
  cat "$table"
done
