#!/usr/bin/env bash
# Clones, pushes and pulls a splice with the git-splice in folder $1, against
# local repositories: the commands every platform's binary must run, for the
# binaries job in ci.yml. The full tests run on Linux only.
set -euo pipefail

PATH="$(cd "$1" && pwd):$PATH"
export GIT_AUTHOR_NAME=Smoke GIT_AUTHOR_EMAIL=smoke@example.com
export GIT_COMMITTER_NAME=Smoke GIT_COMMITTER_EMAIL=smoke@example.com
work="$(mktemp -d)"
cd "$work"

git init -q --bare -b main upstream.git
git clone -q upstream.git seed 2>/dev/null
(
  cd seed
  echo one >file.txt
  git add file.txt
  git commit -q -m one
  git push -q origin main
)

git init -q -b main monorepo
cd monorepo
git commit -q --allow-empty -m "initial commit"
# Git for Windows sets core.autocrlf=true; git-splice's temporary files must
# not show up in its line-ending warnings.
git splice clone "$work/upstream.git" vendor/a 2>"$work/stderr"
cat "$work/stderr" >&2
if grep -q "git-splice-" "$work/stderr"; then
  echo "clone warned about a temporary file of git-splice's" >&2
  exit 1
fi
grep -q one vendor/a/file.txt

echo two >>vendor/a/file.txt
git commit -q -am two
git splice push vendor/a 2>"$work/stderr"
cat "$work/stderr" >&2
if grep -q "git-splice-" "$work/stderr"; then
  echo "push warned about a temporary file of git-splice's" >&2
  exit 1
fi
git -C ../seed pull -q
grep -q two ../seed/file.txt

(
  cd ../seed
  echo three >>file.txt
  git commit -q -am three
  git push -q origin main
)
git splice pull vendor/a
grep -q three vendor/a/file.txt

git splice status
echo "smoke test passed"
