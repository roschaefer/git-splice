#!/usr/bin/env bash
# Builds the state a docs page starts from, and opens a shell in it.
# See docs/sandbox.md.
set -euo pipefail

tests="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
page=""
dir=""
no_shell=0

usage() {
  cat <<'EOF'
usage: test/sandbox.sh <page> [--dir <path>] [--no-shell]

Builds the state the docs page <page> starts from, and drops you into a
shell there. <page> is its path under test/, with or without .md, e.g.
comparisons/git-submodule or scenarios/02-starting-a-splice/01-clone-copied-content.

The state is what the page's commands make before the first one that
prints something: its setup. The shell keeps the page's environment, its
commit dates, author and URLs, so the page's commands print the page's
output, commit hashes included.

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
      page="${1%/}"
      shift
      ;;
  esac
done

markdown=""
if [[ -n "$page" ]]; then
  page="${page#test/}"
  for candidate in "$tests/$page" "$tests/$page.md" "$tests/$page/README.md"; do
    if [[ -f "$candidate" && "$candidate" == *.md ]]; then
      markdown="$candidate"
      break
    fi
  done
fi
if [[ -z "$markdown" ]]; then
  echo "no docs page '$page' under test/; e.g.:" >&2
  (cd "$tests" && grep -rlF --include='*.md' '```scrut' . | sed 's#^\./##; s#/README\.md$##; s#\.md$##' | sort | sed 's/^/  /') >&2
  exit 1
fi

if ! grep -qF '```scrut' "$markdown"; then
  echo "${markdown#"$tests/"} has no commands to start from; the pages it links to may" >&2
  exit 1
fi

if [[ -z "$dir" ]]; then
  dir="$(mktemp -d "${TMPDIR:-/tmp}/git-splice-sandbox.XXXXXX")"
fi
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"

# The commands of the page's scrut blocks, as scrut runs them ("$ " starts
# one, "> " continues it), up to the first block that prints something.
setup() {
  awk '
    function flush() { if (command != "") commands = commands command "\n"; command = "" }
    /^```scrut/ { in_block = 1; commands = ""; command = ""; output = 0; next }
    in_block && /^```/ {
      flush()
      if (output) exit
      printf "%s", commands
      in_block = 0
      next
    }
    in_block && /^\$ / { flush(); command = substr($0, 3); next }
    in_block && /^> / { command = command "\n" substr($0, 3); next }
    in_block { output = 1 }
  ' "$markdown"
}

cd "$dir"
# scrut runs a page's commands with TESTDIR, its folder.
TESTDIR="$(dirname "$markdown")"
export TESTDIR
before="$(export -p)"
echo "=== building ${markdown#"$tests/"} in $dir ==="
if ! eval "$(setup)" >"$dir/setup.log" 2>&1; then
  cat "$dir/setup.log" >&2
  echo "the setup of ${markdown#"$tests/"} failed, see above" >&2
  exit 1
fi
# The variables the setup exported, for a shell of your own.
comm -13 <(sort <<<"$before") <(export -p | sort) >"$dir/env.sh"

if [[ $no_shell -eq 0 && -t 0 && -t 1 ]]; then
  cat <<EOF

=== sandbox ready: $PWD ===

Read the page alongside and paste its commands:
  $markdown

Dropping you into a shell there now -- 'exit' to leave it.
(this sandbox ignores your git config, as the page does)
EOF
  exec "${SHELL:-bash}"
fi

cat <<EOF

=== sandbox ready ===
$PWD

  cd $(printf '%q' "$PWD")
  source $(printf '%q' "$dir/env.sh")   # the page's environment, in bash
EOF
