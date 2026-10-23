# Assumes lib/common.sh and lib/rebuild.sh are already sourced.

usage_boundary() {
  cat <<'EOF'
usage: git splice boundary <path>

Prints the commit the rebuild of splice <path> starts from, B. The
rebuild copies the commits after it on the current branch's
first-parent history that change the folder's files:

  git log --first-parent "$(git splice boundary <path>)"..HEAD -- <path> ':!<path>/.splice'

Usually B is the last pull, merge, clone or init. After a pull that
merged commits that were never pushed, it's an earlier one, where the
folder was the upstream commit .splice recorded.

For a nested splice, run it in a worktree of a fetched commit of the
upstream above, with the path there, to get where that upstream's
rebuild of it starts:

  git worktree add --detach ../a refs/splices/a/heads/main
  git -C ../a splice boundary b

Purely local, but the synced commit must have been fetched. Writes no
ref and no monorepo commit.
EOF
}

cmd_boundary() {
  parse_args usage_boundary "" "$@"
  require_args usage_boundary boundary 1 1
  local path
  path="$(normalize_path "${PATH_ARGS[0]}")"
  open_repository
  require_splice "$path"
  splice_start "$path" HEAD
}
