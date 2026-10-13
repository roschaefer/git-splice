# See README.md in this directory. Commits are named as in the sync
# model's drawing after a pull, docs/images/sync-model-after-pull.svg.
scenario_rebuild_start() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "k" main k.txt
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  commit_local "$monorepo" "vendor/a" "b" b.txt
  commit_local "$monorepo" "other" "c" c.txt
  commit_local "$monorepo" "vendor/a" "d" d.txt
  seed_bare_repo "$upstream" "l" main l.txt
  seed_bare_repo "$upstream" "m" main m.txt
  seed_bare_repo "$upstream" "n" main n.txt
  (cd "$monorepo" && splice pull vendor/a >/dev/null 2>&1)
}
