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

# Keep the previous payload intact while continuation reads it.
pause_pull() {
  local payload="$1" status=0
  shift
  "$@" >"$payload.next" || status=$?
  if [[ -s "$payload.next" ]]; then mv "$payload.next" "$payload"; fi
  return "$status"
}

continue_pull() {
  pause_pull "$1" command git splice pull --continue-from "$1" --exec 'cat; exit 1'
}
