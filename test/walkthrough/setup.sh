#!/usr/bin/env bash
# Builds the walkthrough's repositories in <dir>: a monorepo and the bare
# repositories that stand in for its splices' upstreams. Sourced through
# scrut-setup.sh by each walkthrough page; `just sandbox walkthrough`
# opens a shell in them.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: test/walkthrough/setup.sh <dir>" >&2
  exit 1
fi
mkdir -p "$1"
dir="$(cd "$1" && pwd)"

# Who commits in a clone of an upstream, which stands in for someone
# else's work.
cat >"$dir/.gitconfig" <<'GITCONFIG'
[user]
	name = Walkthrough
	email = walkthrough@example.com
GITCONFIG
upstream_dir="$dir/upstream"
mono_dir="$dir/monorepo"
mkdir -p "$upstream_dir"

seed_bare_repo() {
  local repo="$1" msg="$2" tmp
  tmp="$(mktemp -d)"
  git clone -q "$repo" "$tmp" 2>/dev/null
  (
    cd "$tmp"
    git config user.name "Walkthrough"
    git config user.email "walkthrough@example.com"
    echo "$msg" >>file.txt
    git add file.txt
    git commit -q -m "$msg"
    git push -q origin HEAD:main
  )
  rm -rf "$tmp"
}

splice="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/git-splice"

git init -q --bare --initial-branch=main "$upstream_dir/pkg-a.git"
seed_bare_repo "$upstream_dir/pkg-a.git" "pkg-a: seed"

git init -q --bare --initial-branch=main "$upstream_dir/pkg-b.git"
seed_bare_repo "$upstream_dir/pkg-b.git" "pkg-b: seed"

# Empty, as created for a folder that's about to be published.
git init -q --bare --initial-branch=main "$upstream_dir/lib-c.git"

git init -q --initial-branch=main "$mono_dir"
(
  cd "$mono_dir"
  git config user.name "Walkthrough"
  git config user.email "walkthrough@example.com"
  # The branch feature branches are cut from; a clone of a real monorepo
  # would find it as origin/HEAD.
  git config init.defaultBranch main
  # Realistic URLs that lead to the bare repositories next door. They also
  # keep the URL in .splice, and so every commit id, the same from run to
  # run.
  git config "url.$upstream_dir/.insteadOf" "https://git.example.com/"
  git commit -q --allow-empty -m "initial commit"

  "$splice" clone https://git.example.com/pkg-a.git vendor/pkg-a >/dev/null

  # A folder that grew in the monorepo, for 'git splice init'.
  mkdir -p libs/c
  echo "lib-c: first version" >libs/c/file.txt
  git add libs/c
  git commit -q -m "lib-c: first version"
)

# A second pkg-a commit, made after the clone above, so 'git splice
# status'/'pull' show a genuine "pull" state right away rather than
# everything starting out in sync. status never fetches on its own, so
# fetch once here too.
seed_bare_repo "$upstream_dir/pkg-a.git" "pkg-a: a second commit, after the clone"
(cd "$mono_dir" && "$splice" fetch >/dev/null)
