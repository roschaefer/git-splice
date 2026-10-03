# Shared by every Markdown scenario in this directory.
scenario_clone_without_commits() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  # Deliberately not init_monorepo, which creates an initial commit.
  git init -q -b main "$monorepo"
  git -C "$monorepo" config user.name "Test"
  git -C "$monorepo" config user.email "test@example.com"
}
