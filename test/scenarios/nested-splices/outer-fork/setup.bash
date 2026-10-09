# See README.md in this directory. a's fork is the bare repository
# <upstream>-fork.git, a copy of a's upstream with a commit that changes
# b/; b's fork is <upstream>-b-fork.git, a copy of b's upstream with a
# commit of its own. b's upstream is reached as $3 if given, as in the
# parent scenario.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_outer_fork() {
  local monorepo="$1" upstream="$2" upstream_b="${2%.git}-b.git"
  scenario_nested_splices "$@"
  git clone -q --bare "$upstream" "${upstream%.git}-fork.git"
  seed_bare_repo "${upstream%.git}-fork.git" "a fork patch to b" main b/file.txt
  git clone -q --bare "$upstream_b" "${upstream_b%.git}-fork.git"
  seed_bare_repo "${upstream_b%.git}-fork.git" "b fork patch" main fork.txt
}
