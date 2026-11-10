# See README.md in this directory. The upstream of each splice x is the
# bare repository <upstream>-x.git, reached as https://git.example.com/x.git,
# which url.<path>.insteadOf has to map to it: a has b spliced in at b/ and
# d at d/, and b has c at c/. e's upstream exists, but nothing splices it in
# yet.
scenario_recursive_pull() {
  local monorepo="$1" upstream="$2" x work
  for x in a b c d e; do
    make_bare_repo "$upstream-$x.git"
  done
  seed_bare_repo "$upstream-c.git" "c1: c seed"
  seed_bare_repo "$upstream-d.git" "d1: d seed"
  seed_bare_repo "$upstream-e.git" "e1: e seed"
  seed_bare_repo "$upstream-b.git" "b seed"
  seed_bare_repo "$upstream-a.git" "a seed"
  # b's upstream splices c in at c/; a's, b at b/ and d at d/.
  work="$(mktemp -d)"
  git clone -q "$upstream-b.git" "$work/b"
  git -C "$work/b" config user.name "Test"
  git -C "$work/b" config user.email "test@example.com"
  add_splice "$work/b" https://git.example.com/c.git c main "b1: add c"
  git -C "$work/b" push -q origin HEAD:main
  git clone -q "$upstream-a.git" "$work/a"
  git -C "$work/a" config user.name "Test"
  git -C "$work/a" config user.email "test@example.com"
  add_splice "$work/a" https://git.example.com/b.git b main "add b"
  add_splice "$work/a" https://git.example.com/d.git d main "a1: add d"
  git -C "$work/a" push -q origin HEAD:main
  rm -rf "$work"
  init_monorepo "$monorepo"
  add_splice "$monorepo" https://git.example.com/a.git vendor/a
  for x in b c d; do
    fetch_splice "$monorepo" "https://git.example.com/$x.git"
  done
}

# Runs the command after $1 in the monorepo, and records each ref it
# updates, in order, in file $1: "<old> <new> <ref>" per line, as Git's
# reference-transaction hook reports them.
record_refs() {
  local log="$1" hook status
  shift
  hook="$(git rev-parse --git-path hooks)/reference-transaction"
  : >"$log"
  printf '#!/bin/sh\n[ "$1" = committed ] || exit 0\ncat >>"%s"\n' "$log" >"$hook"
  chmod +x "$hook"
  "$@"
  status=$?
  rm -f "$hook"
  rm -f "$log.at"
  return "$status"
}

# Moves the refs recorded in $1 back to where they were before, and the
# working tree with them. Commits the command made stay in the repository.
rewind_refs() {
  local log="$1" old new ref zero=0000000000000000000000000000000000000000
  tac "$log" | while read -r old new ref; do
    [[ "$ref" == refs/* || "$ref" == SPLICE_PULL_START ]] || continue
    if [[ "$old" == "$zero" ]]; then
      git update-ref -d "$ref"
    else
      git update-ref "$ref" "$old"
    fi
  done
  git reset -q --hard
  echo 0 >"$log.at"
}

# Applies the updates recorded in $1 again, from where the last call
# stopped, up to and including the next update of ref $2, or of a ref
# starting with it if it ends in a slash, and as long as only such refs
# follow. Prints each ref it moves, sorted: fetches run in parallel.
replay_refs() {
  local log="$1" want="$2" at line=0 old new ref seen= moved=() zero=0000000000000000000000000000000000000000
  at="$(cat "$log.at" 2>/dev/null || echo 0)"
  while read -r old new ref; do
    line=$((line + 1))
    ((line > at)) || continue
    local match=
    if [[ "$want" == */ ]]; then [[ "$ref" == "$want"* ]] && match=1; else [[ "$ref" == "$want" ]] && match=1; fi
    if [[ -n "$seen" && -z "$match" && "$want" == */ ]]; then
      line=$((line - 1))
      break
    fi
    if [[ "$ref" == refs/* || "$ref" == SPLICE_PULL_START ]]; then
      if [[ "$new" == "$zero" ]]; then
        git update-ref -d "$ref"
      else
        git update-ref "$ref" "$new"
      fi
      moved+=("$ref")
    fi
    if [[ -n "$match" ]]; then
      seen=1
      [[ "$want" == */ ]] || break
    fi
  done <"$log"
  echo "$line" >"$log.at"
  git reset -q --hard
  ((${#moved[@]} == 0)) || printf '%s\n' "${moved[@]}" | LC_ALL=C sort -u
}
