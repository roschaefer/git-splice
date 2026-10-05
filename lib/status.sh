# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_status() {
  cat <<'EOF'
usage: git splice status [--base <branch>] [path...]

Shows the sync state of every splice. Purely local -- run 'git splice
fetch' first for up-to-date results. Defaults to every splice when no
paths are given.

Like 'git status' against a tracking branch, it counts commits: "ahead"
is how many 'git splice push' would publish, "behind" how many 'git
splice pull' would bring in. 'git splice diff --stat' shows the files.

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
  local path="$1" base="$2" prefix="$1 -> $SPLICE_UPSTREAM_BRANCH"
  changes_vs_base "$path" "$base"
  case "$SPLICE_CHANGES_VS_BASE" in
    no)
      log_ok "$prefix (upstream has no such branch; unchanged since '$SPLICE_BASE_BRANCH')"
      ;;
    yes)
      log_ok "$prefix (upstream has no such branch; $(new_branch_count "$path")since '$SPLICE_BASE_BRANCH' -- push would create it)"
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

# Prints "ahead <n> " for a splice whose upstream lacks the current
# branch: the commits the push that creates it would publish, i.e. those
# of the rebuild on no fetched upstream branch. Prints "changed " if
# there are none to count, e.g. right after cloning on a feature branch:
# the push would create the branch at a commit upstream already has.
new_branch_count() {
  local path="$1" rebuilt count
  rebuilt="$(rebuild_splice "$path" HEAD)"
  if [[ -z "$rebuilt" ]] || ! count="$(git rev-list --count "$rebuilt" --not --glob="refs/splices/$path/*")" || ((count == 0)); then
    printf 'changed '
    return
  fi
  printf 'ahead %s ' "$count"
}

# Classifies and prints the status of one splice.
format_status_line() {
  local path="$1" branch="$2" base="${3:-}" ahead behind rc=0
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
      # Ahead: commits of the rebuild R the upstream branch T lacks, which
      # push publishes. Behind: commits of T that R lacks, which pull
      # brings in.
      read -r ahead behind < <(git rev-list --left-right --count "$SPLICE_REBUILT...$SPLICE_TARGET_REF")
      case "$SPLICE_STATE" in
        push) log_ok "$prefix (push: ahead $ahead)" ;;
        pull) log_ok "$prefix (pull: behind $behind)" ;;
        diverged) log_ok "$prefix (diverged: ahead $ahead, behind $behind)" ;;
      esac
      ;;
    unrelated-history)
      status_warn "$prefix (unrelated history -- see 'git splice merge $path' for options)"
      ;;
  esac
  has_uncommitted_changes "$path" || rc=$?
  case "$rc" in
    0) status_warn "$path has uncommitted changes -- push only sends committed ones" ;;
    2) status_warn "$path: could not check for uncommitted changes (git status failed)" ;;
  esac
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
