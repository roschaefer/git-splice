# shellcheck shell=bash
# Sourced by the hidden first scrut block of each comparison in this
# folder and in third-party/; see `just docs-check`.
#
# Builds, in the scrut work directory:
#   upstream/lib.git  a library with 30 commits by three developers
#   monorepo/         an app with 40 commits, and the current directory
#   splice-monorepo/  a copy of monorepo/, to show git-splice side by side
# The monorepo reaches the library as https://git.example.com/lib.git, so
# URLs and commit hashes are the same on every run.

COMPARISON="$PWD"
export COMPARISON
PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd):$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
# Stand-ins for a global git config. Submodules run git in their own
# repositories, which see these but not the monorepo's config.
export GIT_CONFIG_COUNT=5
export GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0="App Dev"
export GIT_CONFIG_KEY_1=user.email GIT_CONFIG_VALUE_1=app@example.com
export GIT_CONFIG_KEY_2="url.$COMPARISON/upstream/.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/
# Submodules refuse local paths by default since Git 2.38.1.
export GIT_CONFIG_KEY_3=protocol.file.allow GIT_CONFIG_VALUE_3=always
export GIT_CONFIG_KEY_4=init.defaultBranch GIT_CONFIG_VALUE_4=main

{
  git init -q --bare -b main upstream/lib.git &&
    git clone -q upstream/lib.git lib-work &&
    (
      cd lib-work &&
        mkdir src &&
        for i in $(seq 1 30); do
          echo "line $i" >>src/parse.txt
          git add src
          GIT_AUTHOR_NAME="Lib Dev $((i % 3 + 1))" GIT_AUTHOR_EMAIL=lib@example.com \
            git commit -q -m "lib commit $i" || exit
        done &&
        git push -q origin main
    ) &&
    rm -rf lib-work &&
    git init -q -b main monorepo &&
    (
      cd monorepo &&
        mkdir app &&
        for i in $(seq 1 40); do
          echo "line $i" >>app/main.txt
          git add app
          git commit -q -m "app commit $i" || exit
        done
    ) &&
    git clone -q --no-local monorepo splice-monorepo
} >/dev/null 2>&1 || return
cd monorepo || return

# The comparisons show what a terminal shows, stderr included, with the
# work directory as $COMPARISON. Git's progress counters rewrite
# themselves with \r; only what follows the last \r of a line stays.
git() {
  command git "$@" 2>&1 |
    sed -E "s#\r\$##; s#.*\r##; s#$COMPARISON#\$COMPARISON#g"
  return "${PIPESTATUS[0]}"
}

# Prints how many monorepo commits `git subtree split --prefix=<path>`
# walks, from its progress counter "<done>/<total>".
subtree_split_walks() {
  command git subtree split --prefix="$1" 2>&1 >/dev/null |
    tr '\r' '\n' | sed -n 's#^[0-9]*/\([0-9]*\) .*#\1#p' | tail -1
}
