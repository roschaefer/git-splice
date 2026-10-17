# Shared by every Markdown scenario in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_merge_in_monorepo() {
  local monorepo="$1" upstream="$2"
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  # Two lines of work under vendor/a, joined by a merge in the monorepo.
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
