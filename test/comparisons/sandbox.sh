#!/usr/bin/env bash
# Builds the state a comparison page starts from, and opens a shell in it.
# See docs/sandbox.md.
set -euo pipefail

comparisons="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
page=""
dir=""
no_shell=0

usage() {
  cat <<'EOF'
usage: test/comparisons/sandbox.sh <page> [--dir <path>] [--no-shell]

Builds what the comparison page <page> starts from -- e.g. git-submodule,
git-subtree, third-party/git-subrepo -- and drops you into a shell in its
monorepo. That is the page's setup and its commands before its first
section. The shell keeps the page's environment: its commit dates, its
author and its URLs. So the page's commands print the page's output, commit
hashes included.

  --dir <path>   build in <path> instead of a fresh mktemp -d
  --no-shell     print the sandbox path and exit instead of exec'ing a
                 shell into it (the default when not run interactively)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      dir="$2"
      shift 2
      ;;
    --no-shell)
      no_shell=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      page="$1"
      shift
      ;;
  esac
done

markdown="$comparisons/${page%.md}.md"
if [[ -z "$page" || ! -f "$markdown" ]]; then
  echo "no comparison page '$page'; one of:" >&2
  (cd "$comparisons" && find . -name '*.md' ! -name README.md | sed 's#^\./##; s#\.md$##' | sort | sed 's/^/  /') >&2
  exit 1
fi

if [[ -z "$dir" ]]; then
  dir="$(mktemp -d "${TMPDIR:-/tmp}/git-splice-comparison.XXXXXX")"
fi
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"

# The commands of the page's scrut blocks before its first section, as
# scrut runs them: "$ " starts one, "> " continues it. The first block
# sources the setup, which this script does itself.
prelude() {
  awk '
    /^## / { exit }
    /^```scrut/ { in_block = 1; next }
    /^```/ { in_block = 0; next }
    in_block && /^\$ / { if (command != "") print command; command = substr($0, 3); next }
    in_block && /^> / { command = command "\n" substr($0, 3); next }
    END { if (command != "") print command }
  ' "$markdown" | grep -v 'scrut-setup\.sh"$'
}

cd "$dir"
# The page's commands may name files next to it, as scrut lets them.
TESTDIR="$(dirname "$markdown")"
export TESTDIR
# shellcheck source=scrut-setup.sh
source "$comparisons/scrut-setup.sh"
echo "=== building $page in $COMPARISON ==="
if ! output="$(eval "$(prelude)" 2>&1)"; then
  printf '%s\n' "$output" >&2
  echo "the setup of $page failed, see above" >&2
  exit 1
fi
# The page's environment, for a shell of your own.
export -p | grep -E '^declare -x (COMPARISON|PATH|GIT_[A-Z0-9_]+)=' >"$dir/env.sh"

if [[ $no_shell -eq 0 && -t 0 && -t 1 ]]; then
  cat <<EOF

=== $page ready: $PWD ===

Read the page alongside and paste its commands:
  $markdown

Dropping you into a shell there now -- 'exit' to leave it.
(this sandbox ignores your git config, as the page does)
EOF
  exec "${SHELL:-bash}"
fi

cat <<EOF

=== $page ready ===
$PWD

  cd $(printf '%q' "$PWD")
  source $(printf '%q' "$dir/env.sh")   # the page's environment, in bash
EOF
