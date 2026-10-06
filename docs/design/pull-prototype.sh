#!/usr/bin/env bash
# Prototype: pull a folder from its upstream repository as ONE ordinary
# commit, with Git's normal conflict handling. No `git subtree`, no Git
# remote. Runs in a throwaway directory given as $1 (default: mktemp -d).
#
# The trick: upstream commits have the folder's content at their root, so
# they can't be merged into HEAD directly. Build two throwaway commits with
# monorepo-shaped trees instead,
#   base   = HEAD, with <path>/ replaced by the old upstream commit U
#   theirs = HEAD, with <path>/ replaced by the new upstream commit U2 (parent: base)
# and cherry-pick theirs: a three-way merge with base as merge base, HEAD as
# ours. Only <path>/ differs between base and theirs, so only the
# folder can conflict, and the state file update rides along.
set -euo pipefail

dir="${1:-$(mktemp -d)}"
mkdir -p "$dir"
cd "$dir"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

P=vendor/a
URL=../up.git
STATE=.splice

git init -q --bare -b main up.git
git clone -q up.git upw 2>/dev/null
(cd upw && printf 'a\nb\nc\n' >f && git add . && git commit -qm "up 1" && git push -q origin main)

git init -q -b main mono
cd mono
echo r >README && git add . && git commit -qm init

# The state file for upstream commit $1.
state() { printf '[splice]\n\turl = %s\n\tcommit = %s\n' "$URL" "$1"; }

# Prints a tree: HEAD's, with $P/ replaced by upstream commit $1 plus its
# state file. Uses a temporary index, so the worktree is untouched.
reroot() {
  local idx blob
  idx="$(mktemp)"
  GIT_INDEX_FILE=$idx git read-tree HEAD
  GIT_INDEX_FILE=$idx git rm -rq --cached --ignore-unmatch "$P"
  GIT_INDEX_FILE=$idx git read-tree --prefix="$P/" "$1"
  blob="$(state "$1" | git hash-object -w --stdin)"
  GIT_INDEX_FILE=$idx git update-index --add --cacheinfo "100644,$blob,$P/$STATE"
  GIT_INDEX_FILE=$idx git write-tree
  rm -f "$idx"
}

fetch() { git fetch -q "$URL" "+refs/heads/*:refs/splices/$P/*"; }

echo "=== add: one commit, upstream history stays in refs/splices/"
fetch
U="$(git rev-parse "refs/splices/$P/main")"
git read-tree --prefix="$P/" -u "$U"
state "$U" >"$P/$STATE"
git add "$P"
git commit -qm "splice: add $P at ${U:0:7}"

echo "=== a local and an upstream edit to the same line"
sed -i 's/^b$/b-local/' "$P/f" && git commit -qam "mono: edit f"
(cd ../upw && sed -i 's/^b$/b-upstream/' f && git commit -qam "up 2" && git push -q)

echo "=== pull: cherry-pick a re-rooted upstream change"
fetch
U2="$(git rev-parse "refs/splices/$P/main")"
base="$(git commit-tree "$(reroot "$U")" -p HEAD -m base)"
theirs="$(git commit-tree "$(reroot "$U2")" -p "$base" -m "splice: pull $P to ${U2:0:7}")"
git cherry-pick "$theirs" >/dev/null 2>&1 || true
git status --short
cat "$P/f"

echo "=== resolve as usual"
printf 'a\nb-local-and-upstream\nc\n' >"$P/f"
git add "$P/f"
git -c core.editor=true cherry-pick --continue >/dev/null
git log --oneline --graph
cat "$P/$STATE"
