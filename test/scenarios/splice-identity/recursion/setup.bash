# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"
scenario_recursion() {
  local monorepo="$1" upstream="$2" work
  scenario_splice_identity "$monorepo" "$upstream"
  add_splice "$monorepo" https://git.example.com/a.git vendor/a
  # The monorepo is published too, as m.
  make_bare_repo "$upstream-m"
  git -C "$monorepo" config "url.$upstream-m.insteadOf" https://git.example.com/m.git
  git -C "$monorepo" push -q https://git.example.com/m.git main
  # a's upstream splices the monorepo in at i/.
  work="$(mktemp -d)"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name "Test"
  git -C "$work" config user.email "test@example.com"
  git -C "$work" config "url.$upstream-m.insteadOf" https://git.example.com/m.git
  add_splice "$work" https://git.example.com/m.git i
  git -C "$work" push -q origin HEAD:main
  rm -rf "$work"
}
