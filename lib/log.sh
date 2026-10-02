# Assumes lib/common.sh, lib/rebuild.sh, lib/state.sh and lib/pager.sh are
# already sourced.

usage_log() {
  cat <<'EOF'
usage: git splice log [path...]

Shows the commits between each splice and the upstream branch it syncs
with, in both directions:

  <  a commit 'git splice push' would publish
  >  a commit 'git splice pull' would bring in
  =  the same change on both sides, e.g. cherry-picked upstream

Each line shows the author, who is published along with the commit. Purely
local -- run 'git splice fetch' first. Defaults to every splice when no
paths are given.
EOF
}

LOG_FORMAT='%m %h %s  (%an <%ae>)'

log_one() {
  local path="$1" branch="$2"

  classify_splice "$path" "$branch"
  case "$SPLICE_STATE" in
    never-fetched)
      log_warn "$path: not fetched -- run 'git splice fetch $path' first"
      return 1
      ;;
    missing-branch)
      log_step "$path (upstream has no '$SPLICE_UPSTREAM_BRANCH' branch)"
      SPLICE_REBUILT="$(rebuild_splice "$path" HEAD)"
      [[ -n "$SPLICE_REBUILT" ]] || return 0
      # Everything no upstream branch has yet; all of it would be pushed.
      git log --format="${LOG_FORMAT/\%m/<}" "$SPLICE_REBUILT" --not --glob="refs/splices/$path/*"
      return
      ;;
    up-to-date)
      [[ -n "$SPLICE_REBUILT" ]] || return 0
      ;;
    unrelated-history)
      [[ -n "$SPLICE_REBUILT" ]] || {
        log_warn "$path: upstream and the splice share no history"
        return 1
      }
      ;;
  esac

  log_step "$path ($SPLICE_UPSTREAM_BRANCH)"
  git log --left-right --cherry-mark --format="$LOG_FORMAT" "$SPLICE_REBUILT...$SPLICE_TARGET_REF"
}

log_paths() {
  local branch="$1" path rc failures=()
  shift
  for path in "$@"; do
    if log_one "$path" "$branch"; then
      continue
    else
      rc=$?
      ((rc == 141)) && return 141
      failures+=("$path")
    fi
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    return 1
  fi
}

cmd_log() {
  parse_args usage_log "" "$@"
  [[ -z "$BASE_ARG" ]] || die "log takes no --base"
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths overview log
  page_git_output log_paths "$(current_branch)" "${SELECTED_PATHS[@]}"
}
