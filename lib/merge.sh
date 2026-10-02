# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_merge() {
  cat <<'EOF'
usage: git splice merge (<path>... | --all)

Splices already-fetched upstream changes into each splice, as one ordinary
commit per splice. Never touches the network: run 'git splice fetch'
first, or 'git splice pull' to do both.

The upstream branch is the one named like the current branch; on the
monorepo's default branch, the splice's default-branch if it has one.

On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
--abort' to give up), then re-run merge for any splices left. When the two
sides share no history at all, merge doesn't guess: it prints the commands
to keep either side.
EOF
}

# "merge" -> "merged", "pull" -> "pulled".
past_tense() {
  case "$1" in
    merge) echo merged ;;
    *) echo "${1}ed" ;;
  esac
}

# Merges one splice from its already-fetched upstream branch. `verb`
# (merge|pull) only selects the wording of the messages.
merge_one() {
  local path="$1" branch="$2" verb="${3:-merge}"

  classify_splice "$path" "$branch"
  case "$SPLICE_STATE" in
    never-fetched)
      log_warn "$path: not fetched yet -- run 'git splice fetch $path' first"
      return 1
      ;;
    missing-branch)
      log_ok "$path: upstream has no '$SPLICE_UPSTREAM_BRANCH' branch -- nothing to $verb"
      return 0
      ;;
    up-to-date | push)
      log_ok "$path: nothing to $verb"
      return 0
      ;;
    unrelated-history)
      print_unrelated_history_guidance "$path"
      return 1
      ;;
    pull | diverged) ;;
  esac

  # The merge base is the newest upstream commit both sides contain: the
  # synced commit, or a later one this branch pushed since.
  local target merge_base base_folder base_blob new_blob
  target="$(git rev-parse "$SPLICE_TARGET_REF^{commit}")"
  if ! upstream_state_file_free "$target"; then
    log_err "$path: upstream has a $STATE_FILE at its root, which would collide with the splice's own"
    return 1
  fi
  merge_base="$(git merge-base "$SPLICE_REBUILT" "$target")"
  base_folder="$(git rev-parse "$merge_base^{tree}")"
  base_blob="$(git rev-parse "HEAD:$path/$STATE_FILE")"
  new_blob="$(state_blob "$path" "commit=$target")"

  if ! splice_in "$path" "$base_folder" "$base_blob" "$target^{tree}" "$new_blob" \
    "splice: $verb $path from $SPLICE_UPSTREAM_BRANCH at ${target:0:7}"; then
    log_err "$path: $verb failed"
    return 1
  fi
  log_ok "$path: $(past_tense "$verb") ${target:0:7}"
}

# Merges every given path, stopping at the first one that leaves a conflict:
# another cherry-pick can't start before it's resolved. `verb` as for
# merge_one. Exits 1 if anything was skipped or failed.
merge_paths() {
  local branch="$1" verb="$2" path failures=() skipped=()
  shift 2
  for path in "$@"; do
    if splice_in_progress; then
      skipped+=("$path")
      continue
    fi
    merge_one "$path" "$branch" "$verb" || failures+=("$path")
  done

  if [[ ${#skipped[@]} -gt 0 ]]; then
    log_err "Not $(past_tense "$verb") yet: ${skipped[*]} -- resolve the conflict, run 'git commit', then re-run $verb"
  fi
  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
  fi
  [[ ${#skipped[@]} -eq 0 && ${#failures[@]} -eq 0 ]] || exit 1
}

cmd_merge() {
  parse_args usage_merge "" "$@"
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths explicit merge
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"
  merge_paths "$(current_branch)" merge "${SELECTED_PATHS[@]}"
}
