# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_status() {
  cat <<'EOF'
usage: git splice status [--base <branch>] [path...]

Shows the sync state of every splice. Purely local -- run 'git splice
fetch' first for up-to-date results. Defaults to every splice when no
paths are given.

For a splice whose upstream has no branch named like the current one, the
state is whether the splice changed on this branch compared with the
monorepo's base branch (--base, else the monorepo's default branch).

Like every command, status reads splices from the last commit. It warns
about uncommitted changes in a splice's folder, which push leaves out.
EOF
}

status_warn() { printf '??   %s\n' "$*"; }

# Prints the status of a splice whose upstream has no branch like the
# current one: what changed on this branch compared with the base branch.
format_missing_branch_line() {
  local path="$1" base="$2" prefix="$1 -> $SPLICE_UPSTREAM_BRANCH" pathspec=()
  changes_vs_base "$path" "$base"
  case "$SPLICE_CHANGES_VS_BASE" in
    no)
      log_ok "$prefix (upstream has no such branch; unchanged since '$SPLICE_BASE_BRANCH')"
      ;;
    yes)
      log_ok "$prefix (upstream has no such branch; changed since '$SPLICE_BASE_BRANCH' -- push would create it)"
      mapfile -t pathspec < <(content_pathspec "$path")
      git --no-pager diff --stat --relative="$path" "$SPLICE_BASE_MERGE_BASE" HEAD -- "${pathspec[@]}" 2>/dev/null || true
      ;;
    self)
      status_warn "$prefix (upstream has no such branch -- push would create it)"
      ;;
    error)
      status_warn "$prefix (upstream has no such branch; could not compare with base branch '$SPLICE_BASE_BRANCH')"
      ;;
    unresolved)
      if [[ -n "$base" ]]; then
        status_warn "$prefix (upstream has no such branch; base branch '$base' not found, or it shares no history)"
      else
        status_warn "$prefix (upstream has no such branch; monorepo base branch unknown -- pass --base <branch>)"
      fi
      ;;
  esac
}

# Classifies and prints the status of one splice.
format_status_line() {
  local path="$1" branch="$2" base="${3:-}" local_tree
  classify_splice "$path" "$branch"
  local prefix="$path -> $SPLICE_UPSTREAM_BRANCH"

  case "$SPLICE_STATE" in
    never-fetched)
      status_warn "$prefix (never fetched -- run 'git splice fetch $path')"
      ;;
    missing-branch)
      format_missing_branch_line "$path" "$base"
      ;;
    up-to-date)
      log_ok "$prefix (up to date)"
      ;;
    push | pull | diverged)
      log_ok "$prefix ($SPLICE_STATE)"
      content_tree HEAD "$path"
      local_tree="$CONTENT_TREE"
      # Diff order follows what the pending operation would apply, so
      # insertions always mean "content gained": push diffs upstream to
      # local, pull local to upstream. diverged has no single right
      # direction; upstream to local is picked for consistency.
      case "$SPLICE_STATE" in
        pull) git --no-pager diff --stat "$local_tree" "$SPLICE_TARGET_REF" 2>/dev/null || true ;;
        *) git --no-pager diff --stat "$SPLICE_TARGET_REF" "$local_tree" 2>/dev/null || true ;;
      esac
      ;;
    unrelated-history)
      status_warn "$prefix (unrelated history -- see 'git splice merge $path' for options)"
      ;;
  esac
  if has_uncommitted_changes "$path"; then
    status_warn "$path has uncommitted changes -- push only sends committed ones"
  fi
}

cmd_status() {
  parse_args usage_status "" "$@"
  local base="$BASE_ARG" branch path
  cd_to_repo_root
  require_head_commit
  discover_splices
  if [[ ${#ALL_PATHS[@]} -eq 0 && ${#PATH_ARGS[@]} -eq 0 ]]; then
    log_ok "no splices -- 'git splice clone <url> <path>' adds one"
    return 0
  fi
  select_paths overview status
  branch="$(current_branch)"
  for path in "${SELECTED_PATHS[@]}"; do
    format_status_line "$path" "$branch" "$base"
  done
}
