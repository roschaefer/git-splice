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
if any splice has changes to push, like 'git diff'; with --check, it exits
2 if any has whitespace errors. --output=<file> writes every splice's diff to that
one file. -z isn't supported.

For a splice whose upstream has no branch named like the current one, the
diff is against the monorepo's base branch (--base, else the monorepo's
default branch). On the base branch itself, the whole splice is shown as
new upstream content.
EOF
}

# diff_one's status when 'git diff --exit-code' or '--quiet' found
# changes, or '--check' found problems: a result, not a failure. Git's
# status for it, 1 for changes plus 2 for problems, is in DIFF_RESULT.
DIFF_CHANGED=4

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
  local rc=$? results=0
  { has_flag --exit-code || has_flag --quiet; } && results=1
  has_flag --check && ((results |= 2))
  if ((rc & ~results)); then
    return "$rc"
  fi
  DIFF_RESULT="$rc"
  return "$DIFF_CHANGED"
}

# Emits all selected patches. Kept separate from cmd_diff so one pager can
# contain every splice rather than opening a new pager for each one.
diff_paths() {
  local branch="$1" base="$2" path rc result=0 failures=()
  shift 2
  for path in "$@"; do
    if diff_one "$path" "$branch" "$base"; then
      continue
    else
      rc=$?
      ((rc == 141)) && return 141
      if ((rc == DIFF_CHANGED)); then
        ((result |= DIFF_RESULT))
      else
        failures+=("$path")
      fi
    fi
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    return 1
  fi
  return "$result"
}

# Prints $1 as an absolute path: Git reads the file names its diff options
# take relative to where it was run, but cmd_diff runs it from the root.
absolute_path() {
  [[ "$1" == /* ]] && printf '%s\n' "$1" || printf '%s\n' "$PWD/$1"
}

# Readies EXTRA_FLAGS for 'git diff' run at the repository root, once per
# splice. --output=<file> moves to DIFF_OUTPUT, since each 'git diff' would
# overwrite the file with its own patch; the whole output goes there
# instead. -O<orderfile> gets an absolute path. -z is rejected, since the
# headings between splices would break its NUL-delimited format.
prepare_diff_flags() {
  local flag flags=()
  DIFF_OUTPUT=""
  for flag in "${EXTRA_FLAGS[@]}"; do
    case "$flag" in
      --output=*)
        [[ -n "${flag#--output=}" ]] || die "--output needs a file"
        DIFF_OUTPUT="$(absolute_path "${flag#--output=}")"
        ;;
      -O?*) flags+=("-O$(absolute_path "${flag#-O}")") ;;
      -z) die "-z isn't supported: the headings between splices would break its format" ;;
      *) flags+=("$flag") ;;
    esac
  done
  EXTRA_FLAGS=("${flags[@]}")
}

cmd_diff() {
  parse_args usage_diff "-*" "$@"
  local base="$BASE_ARG" branch
  prepare_diff_flags
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
