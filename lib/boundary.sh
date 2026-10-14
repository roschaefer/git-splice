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

  git worktree add --detach ../a refs/splices/a/main
  git -C ../a splice boundary b

Purely local, but the synced commit must have been fetched. Writes no
ref and no monorepo commit.
EOF
}

cmd_boundary() {
  parse_args usage_boundary "" "$@"
  [[ -z "$ALL_ARG" ]] || die "boundary takes no --all"
  [[ -z "$BASE_ARG" ]] || die "boundary takes no --base"
  [[ ${#PATH_ARGS[@]} -eq 1 ]] || {
    usage_boundary >&2
    exit 1
  }
  local path
  path="$(normalize_path "${PATH_ARGS[0]}")"
  cd_to_repo_root
  require_head_commit
  discover_splices
  is_splice_path "$path" || die "not a splice: $path"
  splice_start "$path" HEAD
}
