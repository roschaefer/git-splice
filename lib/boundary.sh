# Assumes lib/common.sh and lib/rebuild.sh are already sourced.

usage_boundary() {
  cat <<'EOF'
usage: git splice boundary <path>

Prints the monorepo commit where splice <path> last synced with its
upstream: the newest commit on the current branch's first-parent history
that changed <path>/.splice -- the last pull, merge, clone or init, or a
commit that edited .splice by hand. What changed in the folder since then
is what push would publish.

  git show "$(git splice boundary <path>)"
  git log "$(git splice boundary <path>)"..HEAD -- <path>

Purely local; writes nothing.
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
  splice_boundary "$path" HEAD
}
