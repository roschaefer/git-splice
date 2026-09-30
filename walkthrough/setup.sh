#!/usr/bin/env bash
# Builds a throwaway sandbox for manually exercising the dev version of
# git-subtrees. Run this from inside `nix develop` (which puts the repo
# root, and so the dev entrypoint, on PATH).
set -euo pipefail

dir=""
dir_given=0
no_shell=0

usage() {
  cat <<'EOF'
usage: walkthrough/setup.sh [--dir <path>] [--no-shell]

Builds a scratch monorepo plus fixture bare "upstream" repos for manually
running git-subtrees commands against realistic state. When run
interactively, drops you straight into a shell inside the built monorepo
-- there's no path to copy-paste.

  --dir <path>   build in <path> instead of a fresh mktemp -d
  --no-shell     print the sandbox path and exit instead of exec'ing a
                 shell into it (the default when not run interactively)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      dir="$2"
      dir_given=1
      shift 2
      ;;
    --no-shell)
      no_shell=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$dir" ]]; then
  dir="$(mktemp -d "${TMPDIR:-/tmp}/git-subtrees-walkthrough.XXXXXX")"
fi

mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
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

echo "=== building fixture upstream repos ==="
git init -q --bare --initial-branch=main "$upstream_dir/pkg-a.git"
seed_bare_repo "$upstream_dir/pkg-a.git" "pkg-a: seed"

git init -q --bare --initial-branch=main "$upstream_dir/pkg-b.git"
seed_bare_repo "$upstream_dir/pkg-b.git" "pkg-b: seed"

echo "=== building monorepo ==="
git init -q --initial-branch=main "$mono_dir"
(
  cd "$mono_dir"
  git config user.name "Walkthrough"
  git config user.email "walkthrough@example.com"
  git commit -q --allow-empty -m "initial commit"

  git remote add vendor/pkg-a "$upstream_dir/pkg-a.git"
  git fetch -q vendor/pkg-a
  git subtree add -q --prefix=vendor/pkg-a vendor/pkg-a main --squash

  # vendor/pkg-b: remote registered but deliberately NOT connected, so you
  # can manually walk through 'git subtrees init' yourself.
  git remote add vendor/pkg-b "$upstream_dir/pkg-b.git"

  # A remote with no matching directory, to demonstrate status's
  # "no mapping" line.
  git remote add ghost "$upstream_dir/pkg-a.git"
)

# A second pkg-a commit, made after the subtree was connected above, so
# 'git subtrees status'/'pull' show a genuine "pull available" state right
# away rather than everything starting out already in sync. status never
# fetches on its own, so fetch once here too -- otherwise the freshly
# built sandbox would still report "up to date" until the user fetches.
seed_bare_repo "$upstream_dir/pkg-a.git" "pkg-a: a second commit, after connecting"
git -C "$mono_dir" fetch -q vendor/pkg-a

# Commands that open each chapter of the walkthrough, rendered by glow
# (in `nix develop`) or as plain Markdown in less.
print_chapters() {
  local docs reader=less chapter
  docs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if command -v glow >/dev/null; then
    reader="glow -p"
  fi
  echo "Read the walkthrough alongside, one chapter at a time:"
  for chapter in README feature-branches diverged; do
    printf '  %s %q\n' "$reader" "$docs/$chapter.md"
  done
}

print_reminder() {
  if [[ $dir_given -eq 0 ]]; then
    echo
    echo "(this is a fresh mktemp -d sandbox -- re-run this script any time for a clean one)"
  fi
}

if [[ $no_shell -eq 0 && -t 0 && -t 1 ]]; then
  cat <<EOF

=== walkthrough ready: $mono_dir ===

$(print_chapters)

Or start with:
  git subtrees status
  git subtrees init vendor/pkg-b "\$WALKTHROUGH/upstream/pkg-b.git"
  simulate-remote-change vendor/pkg-a   # push a commit upstream, as if someone else had

Dropping you into a shell there now -- 'exit' to leave it.
EOF
  print_reminder
  cd "$mono_dir"
  WALKTHROUGH="$dir" exec "${SHELL:-bash}"
fi

# Non-interactive (piped, scripted, or --no-shell): print the path instead
# of exec'ing into it, so the caller can still find and use the sandbox.
cat <<EOF

=== walkthrough ready ===
$mono_dir

  cd $(printf '%q' "$mono_dir")
  export WALKTHROUGH=$(printf '%q' "$dir")

$(print_chapters)

Or start with:
  git subtrees status
  git subtrees init vendor/pkg-b "\$WALKTHROUGH/upstream/pkg-b.git"
  simulate-remote-change vendor/pkg-a   # push a commit upstream, as if someone else had
EOF

print_reminder
