# Assumes lib/common.sh, lib/rebuild.sh, lib/state.sh and lib/pager.sh are
# already sourced.

usage_diff() {
  cat <<'EOF'
NAME
    git-splice-diff - Show the changes push would send

SYNOPSIS
    git splice diff [--upstream <name>] [--stat] [path...]

DESCRIPTION
    Shows the file changes 'git splice push' would send to each splice's
    upstream, with paths as the upstream sees them. Purely local -- run
    'git splice fetch' first for up-to-date results. Defaults to every splice
    when no paths are given.

    --stat summarizes the changes per file instead, like 'git diff --stat'.

    For a splice whose upstream has no branch named like the current one, the
    diff is against upstream's default branch, from where the two meet, as a
    PR from the new branch would show it. Without a default branch upstream,
    the whole splice is new.

    --upstream names one of the upstreams a splice's .splice names; without
    it, the splice's default upstream. A splice without the named upstream
    stops the command before it starts.
EOF
}

# Shows the upstream-to-local patch for one splice.
diff_one() {
  local path="$1" branch="$2" old_tree new_tree merge_base

  classify_splice "$path" "$branch" || return 1
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
    missing-synced)
      log_warn "$path: $(missing_synced_message "$path")"
      return 1
      ;;
    missing-pin)
      log_err "$path: $(target_description) isn't here -- run 'git splice fetch $(upstream_option "$path")$path', or check that upstream has it"
      return 1
      ;;
    missing-branch)
      if ! compare_with_default_branch "$path"; then
        log_err "$path: could not compare with upstream's default branch${SPLICE_DEFAULT_BRANCH:+ '$SPLICE_DEFAULT_BRANCH'}"
        return 1
      fi
      ((SPLICE_NEW_COMMITS > 0)) || return 0
      # As a PR shows it: from where R and the default branch meet.
      old_tree=""
      if [[ -n "$SPLICE_DEFAULT_REF" ]] && merge_base="$(git merge-base "$SPLICE_REBUILT" "$SPLICE_DEFAULT_REF")"; then
        old_tree="$(git rev-parse "$merge_base^{tree}")"
      fi
      ;;
    push | diverged)
      old_tree="$(git rev-parse "$SPLICE_TARGET_REF^{tree}")"
      ;;
  esac

  content_tree HEAD "$path" || return 1
  new_tree="$CONTENT_TREE"
  [[ -n "$old_tree" ]] || old_tree="$(git hash-object -t tree /dev/null)"

  log_step "$path"
  git diff "${EXTRA_FLAGS[@]}" "$old_tree" "$new_tree"
}

cmd_diff() {
  parse_args usage_diff "--stat --upstream" "$@"
  open_repository
  select_splices overview diff
  page_git_output run_each_splice diff_one "$MONOREPO_BRANCH" "${SELECTED_PATHS[@]}"
}
