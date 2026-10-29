# See README.md in this directory. Each splice has its own upstream, next
# to $2: $2 without .git, then -<name>.git, e.g. upstream-cli.git.
scenario_many_splices() {
  local monorepo="$1" upstream="${2%.git}" name
  init_monorepo "$monorepo"
  for name in cli http parser store; do
    make_bare_repo "$upstream-$name.git"
    seed_bare_repo "$upstream-$name.git" "seed"
    add_splice "$monorepo" "$upstream-$name.git" "libs/$name"
  done
  # theme's upstream calls its default branch master.
  make_bare_repo "$upstream-theme.git" master
  seed_bare_repo "$upstream-theme.git" "seed" master
  (cd "$monorepo" && splice clone "$upstream-theme.git" libs/theme >/dev/null 2>&1)

  # http: two upstream commits to pull.
  seed_bare_repo "$upstream-http.git" "upstream fix"
  seed_bare_repo "$upstream-http.git" "upstream feature"
  fetch_splice "$monorepo" "$upstream-http.git" "libs/http"
  # parser: one local commit to push.
  commit_local "$monorepo" "libs/parser" "local change"
  # store: one of each.
  commit_local "$monorepo" "libs/store" "local change"
  seed_bare_repo "$upstream-store.git" "upstream change"
  fetch_splice "$monorepo" "$upstream-store.git" "libs/store"
}
