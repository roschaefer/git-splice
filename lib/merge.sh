# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_merge() {
  cat <<'EOF'
usage: git splice merge [--upstream <name>] (<path>... | --all)

Splices already-fetched upstream changes into each splice, as one ordinary
commit per splice. Never touches the network: run 'git splice fetch'
first, or 'git splice pull' to do both.

The upstream branch is the one named like the current branch; on the
monorepo's default branch, the splice's default-branch if it has one.

--upstream names one of the upstreams a splice's .splice names; without
it, the splice's default upstream. A splice without the named upstream
stops the command before it starts.

Top-down: a splice is merged before the ones below it, since its merge
can move their synced commits, and a failure stops them.

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
      log_warn "$path: not fetched yet -- run 'git splice fetch $(upstream_option "$path")$path' first"
      return 1
      ;;
    missing-branch)
      log_ok "$path: upstream has no '$SPLICE_UPSTREAM_LABEL' branch -- nothing to $verb"
      return 0
      ;;
    up-to-date)
      record_equal_tree "$path" "$verb"
      return
      ;;
    push)
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
  if upstream_has_state_file "$target"; then
    log_err "$path: upstream has a $STATE_FILE at its root, which would replace $path/$STATE_FILE"
    return 1
  fi
  merge_base="$(git merge-base "$SPLICE_REBUILT" "$target")"
  base_folder="$(git rev-parse "$merge_base^{tree}")"
  base_blob="$(git rev-parse "HEAD:$path/$STATE_FILE")"
  new_blob="$(state_blob "$path" "commit=$target")"

  if ! splice_in "$path" "$base_folder" "$base_blob" "$target^{tree}" "$new_blob" \
    "splice: $verb $path from $SPLICE_UPSTREAM_LABEL at ${target:0:7}"; then
    log_err "$path: $verb failed"
    return 1
  fi
  log_ok "$path: $(past_tense "$verb") ${target:0:7}"
}

# For splice <path> in state up-to-date: records the upstream branch T as
# the synced commit, in a commit that only changes the state file, if the
# folder already has T's files but T isn't part of the rebuild's history.
# That happens when the upstream rewrote its history to the same files
# (#17), squash-merged what this branch pushed, or got the rebuild edited
# before the push. Without the record, the rebuild would keep the
# monorepo's original commits, and publish them with the next push. After
# an ordinary push, T is the rebuild: nothing to record. `verb` as for
# merge_one.
record_equal_tree() {
  local path="$1" verb="$2" target rebuilt
  target="$(git rev-parse "$SPLICE_TARGET_REF^{commit}")"
  if [[ "$target" == "$SPLICE_SYNCED" ]]; then
    log_ok "$path: nothing to $verb"
    return 0
  fi
  # Without the synced commit there's no rebuild to compare with, and the
  # folder matches T: recording it is all that's left.
  if [[ -z "$SPLICE_SYNCED" ]] || git cat-file -e "$SPLICE_SYNCED^{commit}" 2>/dev/null; then
    rebuilt="$(rebuild_splice "$path" HEAD)"
    if [[ -n "$rebuilt" ]] && git merge-base --is-ancestor "$target" "$rebuilt"; then
      log_ok "$path: nothing to $verb"
      return 0
    fi
  fi
  local folder base_blob new_blob
  folder="$(git rev-parse "$target^{tree}")"
  base_blob="$(git rev-parse "HEAD:$path/$STATE_FILE")"
  new_blob="$(state_blob "$path" "commit=$target")"
  if ! splice_in "$path" "$folder" "$base_blob" "$folder" "$new_blob" \
    "splice: $verb $path from $SPLICE_UPSTREAM_LABEL at ${target:0:7}"; then
    log_err "$path: $verb failed"
    return 1
  fi
  log_ok "$path: recorded ${target:0:7} as the synced commit -- the folder already has its files"
}

# Merges every given path, stopping at the first one that leaves a conflict:
# another cherry-pick can't start before it's resolved. Top-down: a splice
# goes before the ones below it, whose synced commit its pull may move, and
# a failure stops them. `verb` as for merge_one. Exits 1 if anything was
# skipped or failed.
merge_paths() {
  local branch="$1" verb="$2" path failed paths=() failures=() skipped=()
  shift 2
  mapfile -t paths < <(splices_in_order top-down "$@")
  for path in "${paths[@]}"; do
    if splice_in_progress; then
      skipped+=("$path")
      continue
    fi
    if failed="$(first_above "$path" "${failures[@]}")"; then
      log_err "$path: not $(past_tense "$verb"), since $failed above it failed"
      failures+=("$path")
      continue
    fi
    # A pull of a splice above this one may have removed it.
    if ! git cat-file -e "HEAD:$path/$STATE_FILE" 2>/dev/null; then
      log_ok "$path: not a splice any more -- nothing to $verb"
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
  parse_args usage_merge "--upstream" "$@"
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths explicit merge
  use_upstreams "$UPSTREAM_ARG" "${SELECTED_PATHS[@]}"
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"
  local branch
  branch="$(current_branch)"
  merge_paths "$branch" merge "${SELECTED_PATHS[@]}"
}
