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

# Runs git splice "$@", shows its stderr, and fails if a warning names one of
# git-splice's temporary files (#431).
splice() {
  local status=0
  git splice "$@" 2>"$work/stderr" || status=$?
  cat "$work/stderr" >&2
  if grep -q "git-splice-" "$work/stderr"; then
    echo "git splice $1 warned about a temporary file of its own" >&2
    return 1
  fi
  return "$status"
}

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
# Git for Windows' default, set here so every platform checks the warnings.
git config core.autocrlf true
splice clone "$work/upstream.git" vendor/a
grep -q one vendor/a/file.txt

echo two >>vendor/a/file.txt
git commit -q -am two
splice push vendor/a
git -C ../seed pull -q
grep -q two ../seed/file.txt

(
  cd ../seed
  echo three >>file.txt
  git commit -q -am three
  git push -q origin main
)
splice pull vendor/a
grep -q three vendor/a/file.txt

splice status
echo "smoke test passed"
