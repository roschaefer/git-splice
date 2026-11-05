#!/usr/bin/env bash
# Prototype: compare a first-parent push rebuild with `git subtree split`,
# the test oracle. Runs in a throwaway directory given as $1 (default:
# mktemp -d).
#
# Scenario 1 (linear history): both produce identical SHAs.
# Scenario 2 (merge of main into feature): an approved divergence. split
# keeps the merge's shape; the first-parent rebuild turns the merge into one
# ordinary commit. Everything before the merge still has identical SHAs.
set -euo pipefail

dir="${1:-$(mktemp -d)}"
mkdir -p "$dir"
cd "$dir"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A fake clock, one minute per commit, so the run is reproducible.
n=0
tick() {
  n=$((n + 1))
  GIT_AUTHOR_DATE="2026-01-01T00:$(printf %02d $n):00"
  GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
  export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
}
c() { tick && git commit -q "$@"; }

git init -q -b main up
(cd up && echo one >f && git add . && c -m "up 1")
git init -q -b main mono
cd mono
echo r >README && git add . && c -m init
tick
git subtree add -q --prefix=vendor/a ../up main --squash >/dev/null 2>&1

# The rebuild's inputs: boundary B and upstream commit U. In the real tool
# they come from the .splice file; here, from the `git subtree add` above,
# so that split (which knows nothing of .splice) sees the same history.
B="$(git rev-parse HEAD)"
U="$(git rev-parse FETCH_HEAD)"

# One upstream commit per first-parent commit after B that touched the
# path. Author and committer, with dates, are copied like split's
# copy_commit, so the result is deterministic. Note --pretty=format: (no
# trailing newline), not --format= (tformat), as split does.
rebuild() {
  local prev="$U" commit
  for commit in $(git rev-list --reverse --first-parent "$B..HEAD" -- vendor/a); do
    prev="$(git log -1 --pretty=format:'%an%n%ae%n%aD%n%cn%n%ce%n%cD%n%B' "$commit" | {
      read -r an && read -r ae && read -r ad && read -r cn && read -r ce && read -r cd
      GIT_AUTHOR_NAME=$an GIT_AUTHOR_EMAIL=$ae GIT_AUTHOR_DATE=$ad \
        GIT_COMMITTER_NAME=$cn GIT_COMMITTER_EMAIL=$ce GIT_COMMITTER_DATE=$cd \
        git commit-tree "$commit:vendor/a" -p "$prev"
    })"
  done
  echo "$prev"
}

show() {
  echo "--- git subtree split (oracle):"
  git log --graph --format='%h %s' "$(git subtree split -q --prefix=vendor/a HEAD)"
  echo "--- first-parent rebuild:"
  git log --graph --format='%h %s' "$(rebuild)"
}

echo "##### Scenario 1: linear history -- identical SHAs"
echo two >>vendor/a/f && c -am "f1"
echo x >other && git add . && c -m "outside the splice"
echo three >>vendor/a/f && c -am "f2"
show

echo
echo "##### Scenario 2: merge main into feature -- approved divergence"
git switch -qc feature
echo f >vendor/a/g && git add . && c -m "feature: g"
git switch -q main
echo m >vendor/a/h && git add . && c -m "main: h"
git switch -q feature
tick
git merge -q --no-edit main
echo k >>vendor/a/g && c -am "feature: after merge"
show
