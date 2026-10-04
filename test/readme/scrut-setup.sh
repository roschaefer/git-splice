# shellcheck shell=bash
# Sourced by the hidden first scrut block of the repository's README.md;
# see `just docs-check`.
#
# Builds the README's example in the scrut work directory: a monorepo with
# an app, and the upstream x/lib with one release. The monorepo reaches
# x/lib as https://github.com/x/lib.git, which url.<base>.insteadOf maps to
# a bare repository next door. Dates are fixed and the developer's git
# config is ignored, so commit hashes are the same on every run.

PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd):$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z

# shellcheck source=test/helpers/fixtures.bash
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/fixtures.bash"

{
  make_bare_repo "$PWD/github.com/x/lib.git" &&
    seed_bare_repo "$PWD/github.com/x/lib.git" "release 1.2" main src/parse.txt &&
    init_monorepo monorepo &&
    git -C monorepo config "url.$PWD/github.com/.insteadOf" https://github.com/ &&
    mkdir monorepo/app &&
    echo "app" >monorepo/app/main.txt &&
    git -C monorepo add app &&
    git -C monorepo commit -q -m "app: initial commit"
} >/dev/null 2>&1 || return
cd monorepo || return

# The README shows what a terminal shows, stderr included.
git() {
  command git "$@" 2>&1
}
