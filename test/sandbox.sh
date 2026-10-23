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

The state is the page's setup: its hidden commands, and the shown ones
that only call a helper of the setup, like a scenario's build_scenario.
So you can run every command the page shows, from the first one. The
shell is bash, with the page's environment, its commit dates, author and
URLs, and its helpers, so the commands print the page's output, commit
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

# The page's scrut blocks, in order: whether the page shows the block or
# hides it in an HTML comment, then its commands as scrut runs them ("$ "
# starts one, "> " continues it). Each block ends with a \x1f.
blocks() {
  awk '
    function flush() { if (command != "") commands = commands command "\n"; command = "" }
    /<!--/ { hidden = 1 }
    /^```scrut/ { in_block = 1; commands = ""; command = ""; next }
    in_block && /^```/ {
      flush()
      printf "%s\n%s\x1f", (hidden ? "hidden" : "shown"), commands
      in_block = 0
      next
    }
    in_block && /^\$ / { flush(); command = substr($0, 3); continued = 1; next }
    in_block && continued && /^> / { command = command "\n" substr($0, 3); next }
    in_block { continued = 0 }
    /-->/ { hidden = 0 }
  ' "$markdown"
}

# A helper is a function of the page's setup, like a scenario's
# build_scenario, rather than a command you'd type, like git.
helper() {
  declare -F "$1" >/dev/null && ! type -P "$1" >/dev/null
}

cd "$dir"
# scrut runs a page's commands in the C locale, in GMT, with TESTDIR, its
# folder.
unset "${!LC_@}"
export LANG=C TZ=GMT
TESTDIR="$(dirname "$markdown")"
export TESTDIR
block="" kind="" commands=""
exported_before="$(export -p)"
variables_before="$(compgen -v)"
functions_before="$(declare -F)"
echo "=== building ${markdown#"$tests/"} in $dir ==="
# The setup is the hidden blocks and the shown ones that only call a
# helper, up to the first command the page shows you to run.
set +eu
while IFS= read -r -d $'\x1f' block; do
  kind="${block%%$'\n'*}"
  commands="${block#*$'\n'}"
  if [[ "$kind" == shown ]] && ! helper "${commands%%[[:space:]]*}"; then
    break
  fi
  if ! eval "$commands" >>"$dir/setup.log" 2>&1; then
    cat "$dir/setup.log" >&2
    echo "the setup of ${markdown#"$tests/"} failed, see above" >&2
    exit 1
  fi
done < <(blocks)
set -eu

# A bash for the page's commands: yours, then the page's environment and
# its functions, e.g. seed_bare_repo, and its git, which prints paths as
# the page does.
{
  declare -p TESTDIR
  comm -13 <(sort <<<"$exported_before") <(export -p | sort)
} >"$dir/env.sh"
# The setup's own variables too, e.g. scenario_built, which tells a
# scenario's git to print paths as the page does.
mapfile -t variables < <(comm -13 <(sort <<<"$variables_before") <(compgen -v | sort) |
  grep -vxE 'BASH_.*|FUNCNAME|PIPESTATUS|_|exported_before|variables_before|functions_before')
for variable in "${variables[@]}"; do
  declare -p "$variable" 2>/dev/null
done >>"$dir/env.sh"
mapfile -t functions < <(comm -13 <(sort <<<"$functions_before") <(declare -F | sort) | awk '{ print $3 }')
if [[ ${#functions[@]} -gt 0 ]]; then
  declare -f "${functions[@]}" >"$dir/functions.sh"
else
  : >"$dir/functions.sh"
fi
cat >"$dir/bashrc" <<EOF
if [[ -f ~/.bashrc ]]; then source ~/.bashrc; fi
source $(printf '%q' "$dir/env.sh")
source $(printf '%q' "$dir/functions.sh")
unset "\${!LC_@}"
export LANG=C TZ=GMT
PS1="(sandbox) \${PS1:-\\\\$ }"
cd $(printf '%q' "$PWD")
EOF

if [[ $no_shell -eq 0 && -t 0 && -t 1 ]]; then
  cat <<EOF

=== sandbox ready: $PWD ===

Run the page's commands, from the first one it shows:
  $markdown

Dropping you into bash there now -- 'exit' to leave it.
(this sandbox ignores your git config, as the page does)
EOF
  exec bash --rcfile "$dir/bashrc" -i
fi

cat <<EOF

=== sandbox ready ===
$PWD

  bash --rcfile $(printf '%q' "$dir/bashrc")   # a shell with the page's environment
EOF
