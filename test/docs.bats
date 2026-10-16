# Guards the executable documentation that `just docs-check` runs through
# scrut: that no document or block is silently left out of the run.

setup() {
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$root"
  fence='```'
  # What scrut runs: a fence whose language is exactly scrut, maybe with a
  # {config} after it. A longer word, e.g. scrutt, is a block it skips.
  scrut_language='^scrut([[:space:]{]|$)'
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
  done < <(git grep --untracked -l -E "^$fence${scrut_language#^}" -- ':!test/docs.bats')
  printf 'not run by docs-check: %s\n' "${missed[@]}" >&2
  [ "${#missed[@]}" -eq 0 ]
}

@test "docs: a command in a code block is in a scrut block, so a mistyped fence can't skip it" {
  local document unchecked
  unchecked="$(
    while IFS= read -r document; do
      awk -v file="$document" -v fence="$fence" -v scrut="$scrut_language" '
        index($0, fence) == 1 {
          if (inside) { inside = 0 } else { inside = 1; info = substr($0, 4) }
          next
        }
        inside && info !~ scrut && /^\$ / { print file ":" NR ": " $0 }
      ' "$document"
    done < <(checked_documents)
  )"
  echo "$unchecked" >&2
  [ -z "$unchecked" ]
}

@test "docs: every scrut document first sources its setup" {
  local document first wrong=()
  while IFS= read -r document; do
    grep -qE "^$fence${scrut_language#^}" "$document" || continue
    first="$(awk -v fence="$fence" -v scrut="$scrut_language" '
      index($0, fence) == 1 {
        if (inside) { inside = 0 } else { inside = substr($0, 4) ~ scrut }
        next
      }
      inside && /^\$ / { print; exit }
    ' "$document")"
    [[ "$first" =~ ^\$\ source\ \"\$TESTDIR/([^\"]*/)?[a-z]+-setup\.sh\" ]] || wrong+=("$document: $first")
  done < <(checked_documents)
  printf 'no setup first: %s\n' "${wrong[@]}" >&2
  [ "${#wrong[@]}" -eq 0 ]
}

# Prints the running text of every Markdown file as "file:line: text",
# for the markup rules in docs/writing.md: without code blocks, indented
# code, HTML comments, inline code, image alt text and link targets.
prose_lines() {
  local file
  while IFS= read -r file; do
    awk -v file="$file" -v fence="$fence" '
      { trimmed = $0; sub(/^[[:space:]]+/, "", trimmed) }
      index(trimmed, fence) == 1 || index(trimmed, "~~~") == 1 { code = !code; next }
      code { next }
      /<!--/ { comment = 1 }
      comment { if (/-->/) comment = 0; next }
      /^    / { next }
      {
        line = $0
        gsub(/`[^`]*`/, "", line)
        gsub(/!\[[^]]*\]/, "", line)
        gsub(/\]\([^)]*\)/, "]", line)
        print file ":" NR ": " line
      }
    ' "$file"
  done < <(git ls-files --cached --others --exclude-standard '*.md' ':!CHANGELOG.md')
}

@test "docs: a role like BOUNDARY or U(H) is plain capitals, never bold" {
  run grep -E '\*\*(U\([^)]*\)|[A-Z][A-Z_]*[0-9'"'"']*)\*\*' < <(prose_lines)
  printf '%s\n' "$output" >&2
  [ "$status" -eq 1 ]
}

@test "docs: a repository or splice isn't named by a letter, as in \"a's upstream\"" {
  # Capitals that name roles may: R's history, T's files.
  run grep -E "(^|[^[:alnum:]_*'/.-])([a-z]|[ACD-GIJKM-QSVWYZ])'s([^[:alnum:]]|$)" < <(prose_lines)
  printf '%s\n' "$output" >&2
  [ "$status" -eq 1 ]
}
