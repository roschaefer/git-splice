# Assumes lib/common.sh, lib/rebuild.sh, lib/state.sh and lib/pager.sh are
# already sourced.

usage_diff() {
  cat <<'EOF'
usage: git splice diff [--upstream <name>] [--stat] [path...]

Shows the file changes 'git splice push' would send to each splice's
upstream, with paths as the upstream sees them. Purely local -- run
'git splice fetch' first for up-to-date results. Defaults to every splice
when no paths are given.

--stat summarizes the changes per file instead, like 'git diff --stat'.

For a splice whose upstream has no branch named like the current one, the
diff covers the commits the push that creates it would publish: those no
upstream branch has yet. With none upstream has, the whole splice is new.

--upstream names one of the upstreams a splice's .splice names; without
it, the splice's default upstream. A splice without the named upstream
stops the command before it starts.
EOF
}

# Shows the upstream-to-local patch for one splice.
diff_one() {
  local path="$1" branch="$2" old_tree new_tree oldest

  classify_splice "$path" "$branch"
  case "$SPLICE_STATE" in
    never-fetched)
      log_warn "$path: not fetched -- run 'git splice fetch $(upstream_option "$path")$path' first"
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
      if ! count_new_commits "$path"; then
        log_err "$path: could not count the commits upstream lacks"
        return 1
      fi
      ((SPLICE_NEW_COMMITS > 0)) || return 0
      # From the commit before the first one upstream lacks, on R's
      # first-parent history; none before it: everything is new.
      oldest="$(git rev-list --first-parent "$SPLICE_REBUILT" --not --glob="$(splice_refs_prefix "$path")*" | tail -n 1)"
      old_tree="$(git rev-parse --quiet --verify "$oldest^^{tree}")" || old_tree=""
      ;;
    push | diverged)
      old_tree="$(git rev-parse "$SPLICE_TARGET_REF^{tree}")"
      ;;
  esac

  content_tree HEAD "$path"
  new_tree="$CONTENT_TREE"
  [[ -n "$old_tree" ]] || old_tree="$(git hash-object -t tree /dev/null)"

  log_step "$path"
  git diff "${EXTRA_FLAGS[@]}" "$old_tree" "$new_tree"
}

# Emits all selected patches. Kept separate from cmd_diff so one pager can
# contain every splice rather than opening a new pager for each one.
diff_paths() {
  local branch="$1" path rc failures=()
  shift
  for path in "$@"; do
    if diff_one "$path" "$branch"; then
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

cmd_diff() {
  parse_args usage_diff "--stat --upstream" "$@"
  local branch
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths overview diff
  use_upstreams "$UPSTREAM_ARG" "${SELECTED_PATHS[@]}"
  branch="$(current_branch)"
  require_upstream_branches "$branch" "${SELECTED_PATHS[@]}"
  page_git_output diff_paths "$branch" "${SELECTED_PATHS[@]}"
}
