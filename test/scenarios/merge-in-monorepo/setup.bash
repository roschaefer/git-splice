# Shared by every Markdown scenario in this directory.
scenario_merge_in_monorepo() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  # Two lines of work under vendor/a, joined by a merge in the monorepo.
  git -C "$monorepo" checkout -q -b feature
  commit_local "$monorepo" "vendor/a" "feature work" feature.txt
  git -C "$monorepo" checkout -q main
  commit_local "$monorepo" "vendor/a" "main work" main.txt
  git -C "$monorepo" checkout -q feature
  git -C "$monorepo" merge -q --no-edit main
  commit_local "$monorepo" "vendor/a" "after the merge" feature.txt
}

merge_main_into_feature_again() {
  local monorepo="$1"
  git -C "$monorepo" checkout -q main
  commit_local "$monorepo" "vendor/a" "second main work" main.txt
  git -C "$monorepo" checkout -q feature
  git -C "$monorepo" merge -q --no-edit main
  commit_local "$monorepo" "vendor/a" "after the second merge" feature.txt
}
