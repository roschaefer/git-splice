# Assumes lib/common.sh, lib/rebuild.sh, lib/state.sh and lib/pager.sh are
# already sourced.

usage_diff() {
  cat <<'EOF'
usage: git splice diff [--base <branch>] [<git diff option>...] [--] [path...]

Shows the file changes 'git splice push' would send to each splice's
upstream, with paths as the upstream sees them. Purely local -- run
'git splice fetch' first for up-to-date results. Defaults to every splice
when no paths are given.

Other options go to 'git diff', e.g. --stat, --name-only or
--name-status. Give each as one word (-U5, --stat=80), since a separate
value would be read as a path. With --exit-code or --quiet, it exits 1
if any splice has changes to push, like 'git diff'. --output=<file>
writes every splice's diff to that one file.

For a splice whose upstream has no branch named like the current one, the
diff is against the monorepo's base branch (--base, else the monorepo's
default branch). On the base branch itself, the whole splice is shown as
new upstream content.
EOF
}

# diff_one's status when 'git diff --exit-code' or '--quiet' found
# changes: a result, not a failure.
DIFF_CHANGED=3

# Shows the upstream-to-local patch for one splice. $3 is an explicit
# --base branch, if any.
diff_one() {
  local path="$1" branch="$2" base="${3:-}" old_tree new_tree

  classify_splice "$path" "$branch"
  case "$SPLICE_STATE" in
    never-fetched)
      log_warn "$path: not fetched -- run 'git splice fetch $path' first"
      return 1
      ;;
    up-to-date | pull)
      return 0
      ;;
    unrelated-history)
      log_warn "$path: upstream and the splice share no history -- no push diff available"
      return 1
      ;;
    missing-branch)
      changes_vs_base "$path" "$base"
      case "$SPLICE_CHANGES_VS_BASE" in
        no)
          return 0
          ;;
        unresolved)
          if [[ -n "$base" ]]; then
            log_err "$path: base branch '$base' not found, or it shares no history with '$branch'"
          else
            log_err "$path: upstream has no '$SPLICE_UPSTREAM_BRANCH' branch and the monorepo's base branch can't be determined -- re-run with --base <branch>"
          fi
          return 1
          ;;
        error)
          log_err "$path: could not compare with base branch '$SPLICE_BASE_BRANCH'"
          return 1
          ;;
        yes)
          content_tree "$SPLICE_BASE_MERGE_BASE" "$path"
          old_tree="$CONTENT_TREE"
          ;;
        self)
          old_tree=""
          ;;
      esac
      ;;
    push | diverged)
      old_tree="$(git rev-parse "$SPLICE_TARGET_REF^{tree}")"
      ;;
  esac

  content_tree HEAD "$path"
  new_tree="$CONTENT_TREE"
  [[ -n "$old_tree" ]] || old_tree="$(git hash-object -t tree /dev/null)"

  has_flag --quiet || log_step "$path"
  git diff "${EXTRA_FLAGS[@]}" "$old_tree" "$new_tree" && return 0
  local rc=$?
  if ((rc == 1)) && { has_flag --exit-code || has_flag --quiet; }; then
    return "$DIFF_CHANGED"
  fi
  return "$rc"
}

# Emits all selected patches. Kept separate from cmd_diff so one pager can
# contain every splice rather than opening a new pager for each one.
diff_paths() {
  local branch="$1" base="$2" path rc changed="" failures=()
  shift 2
  for path in "$@"; do
    if diff_one "$path" "$branch" "$base"; then
      continue
    else
      rc=$?
      ((rc == 141)) && return 141
      if ((rc == DIFF_CHANGED)); then
        changed=1
      else
        failures+=("$path")
      fi
    fi
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    return 1
  fi
  [[ -z "$changed" ]] || return 1
}

# Takes --output=<file> out of EXTRA_FLAGS into DIFF_OUTPUT, as an
# absolute path: each splice's 'git diff' would overwrite the file with
# its own patch, so the whole output goes there instead.
take_output_flag() {
  local flag flags=()
  DIFF_OUTPUT=""
  for flag in "${EXTRA_FLAGS[@]}"; do
    case "$flag" in
      --output=*) DIFF_OUTPUT="${flag#--output=}" ;;
      *) flags+=("$flag") ;;
    esac
  done
  EXTRA_FLAGS=("${flags[@]}")
  [[ -z "$DIFF_OUTPUT" || "$DIFF_OUTPUT" == /* ]] || DIFF_OUTPUT="$PWD/$DIFF_OUTPUT"
}

cmd_diff() {
  parse_args usage_diff "-*" "$@"
  local base="$BASE_ARG" branch
  take_output_flag
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths overview diff
  branch="$(current_branch)"
  if [[ -n "$DIFF_OUTPUT" ]]; then
    diff_paths "$branch" "$base" "${SELECTED_PATHS[@]}" >"$DIFF_OUTPUT"
    return
  fi
  page_git_output diff_paths "$branch" "$base" "${SELECTED_PATHS[@]}"
}
