# See README.md in this directory.
scenario_init_without_commits() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  # Deliberately not init_monorepo, which creates an initial commit.
  git init -q -b main "$monorepo"
  (
    cd "$monorepo"
    git config user.name "Test"
    git config user.email "test@example.com"
  )
  # Deliberately: no remote registered yet -- cmd_init registers it itself.
}
