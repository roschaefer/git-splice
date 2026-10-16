# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_merge() {
  cat <<'EOF'
usage: git splice merge [--upstream <name>] [--bump] (<path>... | --all)

Splices already-fetched upstream changes into each splice, as one ordinary
commit per splice. Never touches the network: run 'git splice fetch'
first, or 'git splice pull' to do both.

The upstream branch is the one named like the current branch; on the
monorepo's default branch, the upstream's default-branch if it has one.

--upstream names one of the upstreams a splice's .splice names; without
it, the splice's default upstream. A splice without the named upstream
stops the command before it starts.

Top-down: a splice is merged before the ones below it, since its merge
can move their synced commits, and a failure stops them.

On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
--abort' to give up), then re-run merge for any splices left. When the two
sides share no history at all, merge doesn't guess: it prints the commands
to keep either side.

--bump also moves the synced commit up to the upstream branch when there's
nothing to merge, e.g. right after a push, in a commit that only changes
the splice's .splice, like a submodule bump. Later rebuilds then start
there, instead of rebuilding every pushed commit again.
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

  classify_splice "$path" "$branch" || return 1
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
      if [[ -n "${MERGE_BUMP:-}" ]]; then
        bump_synced "$path"
        return
      fi
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
  local inner
  inner="$(changed_submodule "$merge_base" "$target")"
  if [[ -n "$inner" ]]; then
    log_err "$path: upstream has a submodule, $inner, which nobody could check out in the monorepo -- turn it into a splice in the upstream first"
    return 1
  fi
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
# an ordinary push, T is the rebuild: nothing to record, unless --bump
# asks for it. `verb` as for merge_one.
record_equal_tree() {
  local path="$1" verb="$2" target outcome
  target="$(git rev-parse "$SPLICE_TARGET_REF^{commit}")"
  outcome="$(equal_tree_outcome "$path" "$target")" || return 1
  if [[ "$outcome" != record ]]; then
    if [[ -n "${MERGE_BUMP:-}" ]]; then
      bump_synced "$path"
      return
    fi
    log_ok "$path: nothing to $verb"
    return 0
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

# Prints what a pull does with upstream commit <target> for splice <path>
# whose folder in HEAD has <target>'s files -- record_equal_tree's choice:
#   record  records it as the synced commit: it isn't part of the rebuild,
#           or there's no rebuild to compare with, without the synced
#           commit here
#   bump    only --bump records it: it's part of the rebuild, after the
#           synced commit
#   keep    nothing records it: it's the synced commit or older
# push --rebuilt-commit refuses a commit no pull would record. Returns 1
# if the rebuild fails, after it printed why.
equal_tree_outcome() {
  local path="$1" target="$2" synced rebuilt
  synced="$(splice_config "$path" commit)"
  if [[ -z "$synced" ]] || git cat-file -e "$synced^{commit}" 2>/dev/null; then
    rebuilt="$(rebuild_splice "$path" HEAD)" || return 1
    if [[ -n "$rebuilt" ]] && git merge-base --is-ancestor "$target" "$rebuilt"; then
      if newer_than_synced "$synced" "$target"; then
        echo bump
      else
        echo keep
      fi
      return
    fi
  fi
  echo record
}

# Succeeds if upstream commit <target> is newer than synced commit
# <synced>, or there's no synced commit: the only ones --bump moves to.
newer_than_synced() {
  local synced="$1" target="$2"
  [[ -z "$synced" ]] && return 0
  [[ "$target" != "$synced" ]] && git merge-base --is-ancestor "$synced" "$target"
}

# For --bump: records the upstream branch T as splice <path>'s synced
# commit, in a commit that only changes the state file, though T is
# already part of the rebuild's history (states up-to-date and push). The
# rebuild then starts at T, or, while ahead, continues from the history
# before the bump. Never moves the synced commit backwards, e.g. to a stale
# upstream ref.
bump_synced() {
  local path="$1" target folder base_blob new_blob
  target="$(git rev-parse "$SPLICE_TARGET_REF^{commit}")"
  if [[ "$target" == "$SPLICE_SYNCED" ]]; then
    log_ok "$path: nothing to bump -- already synced at ${target:0:7}"
    return 0
  fi
  if ! newer_than_synced "$SPLICE_SYNCED" "$target"; then
    log_ok "$path: nothing to bump -- the fetched '$SPLICE_UPSTREAM_LABEL' is older than the synced commit"
    return 0
  fi
  folder="$(git rev-parse "HEAD:$path")"
  base_blob="$(git rev-parse "HEAD:$path/$STATE_FILE")"
  new_blob="$(state_blob "$path" "commit=$target")"
  if ! splice_in "$path" "$folder" "$base_blob" "$folder" "$new_blob" \
    "splice: bump $path from $SPLICE_UPSTREAM_LABEL at ${target:0:7}"; then
    log_err "$path: bump failed"
    return 1
  fi
  log_ok "$path: bumped the synced commit to ${target:0:7}"
}

# Succeeds if splice <path>'s synced commit is here, or it has none.
synced_commit_here() {
  local synced
  synced="$(splice_config "$1" commit)"
  [[ -z "$synced" ]] || git cat-file -e "$synced^{commit}" 2>/dev/null
}

# Reads splice <path>'s upstreams again after a merge above changed its
# .splice, and uses the one the command chose (use_upstreams). A pull
# (<verb>) fetches the upstreams it names now, but didn't before: the
# synced commit the merge above moved it to may be in any of them. It
# also fetches the one it uses if that synced commit isn't here: it may
# be on no branch of an upstream it had, e.g. after a force-push, and
# fetch_upstream fetches it by its hash. Fails, saying why, if one can't
# be fetched, if the synced commit is on none of them, or if a merge would
# use one that wasn't.
reload_splice_upstream() {
  local path="$1" branch="$2" verb="$3" names=() name old_urls=() url entries=() i used_is_new=""
  read -r -a names <<<"${SPLICE_UPSTREAM_LISTS[$path]}"
  for name in "${names[@]}"; do
    old_urls+=("${UPSTREAM_URLS["$path:$name"]}")
  done
  load_splice_upstream "$path"
  use_upstreams "$UPSTREAM_ARG" "$path"
  read -r -a names <<<"${SPLICE_UPSTREAM_LISTS[$path]}"
  for name in "${names[@]}"; do
    for url in "${old_urls[@]}"; do
      [[ "$url" == "${UPSTREAM_URLS["$path:$name"]}" ]] && continue 2
    done
    entries+=("$path:$name")
    [[ "$name" != "${SPLICE_UPSTREAM_NAMES[$path]}" ]] || used_is_new=1
  done
  if [[ ${#entries[@]} -eq 0 ]] && ! synced_commit_here "$path"; then
    entries=("$path:${SPLICE_UPSTREAM_NAMES[$path]}")
    used_is_new=1
  fi
  [[ ${#entries[@]} -gt 0 ]] || return 0
  if [[ "$verb" == pull ]]; then
    fetch_all_parallel "$branch" "${entries[@]}"
    for i in "${!entries[@]}"; do
      print_fetch_output "$i"
    done
    [[ ${#FETCH_FAILURES[@]} -eq 0 ]] || return 1
    # A fetch by hash fails quietly when no upstream has the commit any
    # more, e.g. after a gc.
    if ! synced_commit_here "$path"; then
      log_err "$path: its synced commit $(splice_config "$path" commit | cut -c1-7), from a pull above, isn't on its upstream any more"
      return 1
    fi
  elif [[ -n "$used_is_new" ]] && { ! splice_fetched "$path" || ! synced_commit_here "$path"; }; then
    log_warn "$path: not fetched yet -- run 'git splice fetch $(upstream_option "$path")$path' first"
    return 1
  fi
}

# Merges every given path, stopping at the first one that leaves a conflict:
# another cherry-pick can't start before it's resolved. Top-down: a splice
# goes before the ones below it, whose synced commit its pull may move, and
# a failure stops them. `verb` as for merge_one. Exits 1 if anything was
# skipped or failed.
merge_paths() {
  local branch="$1" verb="$2" path failed paths=() failures=() skipped=() loaded
  shift 2
  mapfile -t paths < <(splices_in_order top-down "$@")
  loaded="$(git rev-parse HEAD)"
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
    # ... or changed its upstreams, read before it merged.
    if ! git diff --quiet "$loaded" HEAD -- "$path/$STATE_FILE" &&
      ! reload_splice_upstream "$path" "$branch" "$verb"; then
      failures+=("$path")
      continue
    fi
    merge_one "$path" "$branch" "$verb" || failures+=("$path")
    # Its merge may have replaced the .splice files below it.
    forget_default_branches_below "$path"
  done
  # A pull above may also move the synced commit of a splice below it that
  # isn't pulled itself: fetch that commit too, or the splice would look
  # like it shares no history with its upstream. --upstream names one of
  # the pulled splice's upstreams, so this uses the default one.
  if [[ "$verb" == pull ]] && ! splice_in_progress; then
    for path in "${ALL_PATHS[@]}"; do
      [[ " ${paths[*]} " != *" $path "* ]] || continue
      first_above "$path" "${paths[@]}" >/dev/null || continue
      git cat-file -e "HEAD:$path/$STATE_FILE" 2>/dev/null || continue
      ! git diff --quiet "$loaded" HEAD -- "$path/$STATE_FILE" || continue
      synced_commit_here "$path" && continue
      UPSTREAM_ARG="" reload_splice_upstream "$path" "$branch" pull || failures+=("$path")
    done
  fi

  if [[ ${#skipped[@]} -gt 0 ]]; then
    log_err "Not $(past_tense "$verb") yet: ${skipped[*]} -- resolve the conflict, run 'git commit', then re-run $verb"
  fi
  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
  fi
  [[ ${#skipped[@]} -eq 0 && ${#failures[@]} -eq 0 ]] || exit 1
}

cmd_merge() {
  parse_args usage_merge "--upstream --bump" "$@"
  MERGE_BUMP=""
  has_flag --bump && MERGE_BUMP=1
  open_repository
  select_splices explicit merge
  require_no_splice_in_progress
  merge_paths "$MONOREPO_BRANCH" merge "${SELECTED_PATHS[@]}"
}
