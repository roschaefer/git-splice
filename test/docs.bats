# Guards the executable documentation that `just docs-check` runs through
# scrut: that no document or block is silently left out of the run.

setup() {
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$root"
  fence='```'
  # The paths `just docs-check` hands scrut, read from the justfile so the
  # two can't drift apart.
  read -r -a docs_paths < <(sed -n 's/.*elif ! scrut test \(.*\); then.*/\1/p' justfile)
  [ "${#docs_paths[@]}" -gt 0 ]
}

# Prints every Markdown file under the paths `just docs-check` runs.
checked_documents() {
  find "${docs_paths[@]}" -name '*.md' | LC_ALL=C sort
}

@test "docs: every file with a scrut block is a Markdown file that docs-check runs" {
  local file path checked missed=()
  while IFS= read -r file; do
    checked=""
    for path in "${docs_paths[@]}"; do
      [[ "$file" == "$path" || "$file" == "$path"/* ]] && checked=1
    done
    [[ -n "$checked" && "$file" == *.md ]] || missed+=("$file")
  done < <(git grep --untracked -l -E "^$fence"scrut -- ':!test/docs.bats')
  printf 'not run by docs-check: %s\n' "${missed[@]}" >&2
  [ "${#missed[@]}" -eq 0 ]
}

@test "docs: a command in a code block is in a scrut block, so a mistyped fence can't skip it" {
  local document unchecked
  unchecked="$(
    while IFS= read -r document; do
      awk -v file="$document" -v fence="$fence" '
        index($0, fence) == 1 {
          if (inside) { inside = 0 } else { inside = 1; info = substr($0, 4) }
          next
        }
        inside && info !~ /^scrut/ && /^\$ / { print file ":" NR ": " $0 }
      ' "$document"
    done < <(checked_documents)
  )"
  echo "$unchecked" >&2
  [ -z "$unchecked" ]
}

@test "docs: every scrut document first sources its setup" {
  local document first wrong=()
  while IFS= read -r document; do
    grep -q "^$fence"scrut "$document" || continue
    first="$(awk -v fence="$fence" '
      index($0, fence "scrut") == 1 { inside = 1; next }
      index($0, fence) == 1 { inside = 0 }
      inside && /^\$ / { print; exit }
    ' "$document")"
    [[ "$first" =~ ^\$\ source\ \"\$TESTDIR/([^\"]*/)?[a-z]+-setup\.sh\" ]] || wrong+=("$document: $first")
  done < <(checked_documents)
  printf 'no setup first: %s\n' "${wrong[@]}" >&2
  [ "${#wrong[@]}" -eq 0 ]
}
