# Shared by every Markdown scenario in this directory.
scenario_copybara_contributor_workflow() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "published library"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"

  # An external contributor opens a feature branch in the public repository.
  seed_bare_repo "$upstream" "external contribution" contribution
  git -C "$monorepo" checkout -q -b contribution
}

merge_contribution_upstream() {
  local upstream="$1" checkout
  checkout="$(mktemp -d)"
  git clone -q "$upstream" "$checkout"
  git -C "$checkout" config user.name "Upstream maintainer"
  git -C "$checkout" config user.email "maintainer@example.com"
  git -C "$checkout" merge -q --no-ff origin/contribution -m "Merge external contribution"
  git -C "$checkout" push -q origin main
  rm -rf "$checkout"
}
