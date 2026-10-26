# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_merge() {
  cat <<'EOF'
usage: git splice merge [--upstream <name>] [--branch <name>] [--bump | --rebase] [--no-fork-point] (<path>... | --all)
   or: git splice merge [<option>...] -m <message> <path>

Splices already-fetched upstream changes into each splice, as one ordinary
commit per splice. Never touches the network: run 'git splice fetch'
first, or 'git splice pull' to do both.

The upstream branch is the one named like the current branch; on the
monorepo's default branch, the upstream's default-branch if it has one,
or the tag or commit its default-pin names.
--branch names another one for this merge, e.g. the one the default
branch follows, on a pull request's branch the upstream has none for.
It doesn't change .splice, and the splices below keep theirs.

--upstream names one of the upstreams a splice's .splice names; without
it, the splice's default upstream. A splice without the named upstream
stops the command before it starts.

Top-down: a splice is merged before the ones below it, since its merge
can move their synced commits, and a failure stops them.

On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
--abort' to give up), then re-run merge for any splices left. When the two
sides share no history at all, merge doesn't guess: it prints the commands
to keep either side.

When the upstream rewrote its branch, e.g. a fork rebased its patch
branch onto a new release, merge starts at the branch's fork point, like
'git pull --rebase': the newest commit the fetched branch pointed at, by
its reflog, that the folder's history has. Merge then takes the
rewritten branch as it is. If the folder has changes that branch lacks,
it refuses: the next push would publish the rewritten-away commits
again, under them. --rebase redoes them on top instead.
--no-fork-point merges from Git's merge base instead.

--bump also moves the synced commit up to the upstream branch when there's
nothing to merge, e.g. right after a push, in a commit that only changes
the splice's .splice, like a submodule bump. Later rebuilds then start
there, instead of rebuilding every pushed commit again.

--rebase rebases instead, like 'git pull --rebase': it takes the
upstream branch in on top of the newest commit whose folder has exactly
the synced commit's files, and rebases the monorepo branch's commits
since then onto that, with 'git rebase'. The next push then sends the
folder's changes as commits on top of the upstream branch, also after
the upstream rewrote it. It rewrites the branch, so it refuses when a
remote-tracking branch has any of those commits, and when one of them is
a merge, whose own changes a rebase would drop. rebase.autoStash and
rebase.updateRefs don't apply: it neither stashes nor moves other
branches. On a conflict, resolve it and run 'git rebase --continue' (or
'git rebase --abort' to give up).

-m gives the commit this message instead of the default one, which
names the upstream branch and commit; with --rebase, the commit the
rebased ones go on top of. It takes one splice: each gets a commit of
its own. Nothing reads the message back: .splice records the synced
commit. On a conflict, 'git commit' keeps the message.
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
    missing-pin)
      log_err "$path: $(target_description) isn't here -- run 'git splice fetch $(upstream_option "$path")$path', or check that upstream has it"
      return 1
      ;;
    missing-branch)
      if branch_arg_applies "$path"; then
        log_err "$path: upstream has no '$SPLICE_UPSTREAM_LABEL' branch, which --branch names"
        return 1
      fi
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
  if [[ -n "${MERGE_REBASE:-}" ]]; then
    rebase_onto_pull "$path" "$branch" "$verb"
    return
  fi

  # The merge base is the newest upstream commit both sides contain: the
  # synced commit, or a later one this branch pushed since. After a
  # rewrite upstream, e.g. a patch branch rebased onto a new release, Git's
  # merge base is older, and the patches would look like changes on both
  # sides. Like git pull --rebase, the merge then starts at the fork point
  # (fork_point): where the fetched branch was before the rewrite.
  local target merge_base base_folder base_blob new_blob fork
  target="$(git rev-parse "$SPLICE_TARGET_REF^{commit}")"
  if upstream_has_state_file "$target"; then
    log_err "$path: upstream has a $STATE_FILE at its root, which would replace $path/$STATE_FILE"
    return 1
  fi
  fork="$(fork_point)"
  if [[ -n "$fork" ]]; then
    merge_base="$fork"
    # Only a folder that ends up with exactly the rewritten branch's files
    # lets the rebuild start there again. Anything else is rebuilt on top
    # of the fork point, and joined in as a merge.
    if ! merge_gives "$merge_base" "$target"; then
      log_err "$path: upstream rewrote '$SPLICE_UPSTREAM_LABEL' since ${fork:0:7}, and the folder has changes '$SPLICE_UPSTREAM_LABEL' lacks -- run 'git splice $verb --rebase $(selection_options "$path")$(shell_quote "$path")' to redo them on top: a $verb now would publish the rewritten-away commits again with the next push"
      return 1
    fi
  else
    merge_base="$(git merge-base "$SPLICE_REBUILT" "$target")"
  fi
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
    "$(commit_message "splice: $verb $path from $SPLICE_UPSTREAM_LABEL at ${target:0:7}")"; then
    log_err "$path: $verb failed"
    return 1
  fi
  log_ok "$path: $(past_tense "$verb") ${target:0:7}"
}

# For --rebase: takes splice <path>'s upstream branch in on top of X, the
# newest first-parent commit since the synced commit was recorded whose
# folder has exactly its files, and rebases the commits after X onto that.
# From X's folder, the synced commit, the upstream branch merges without a
# conflict, as it does in merge_one: the pull commit gets exactly its
# files, so the rebuild starts there, and the rebased commits follow it.
# `branch` and `verb` as for merge_one.
rebase_onto_pull() {
  local path="$1" branch="$2" verb="$3" target synced_tree base="" commit count published
  target="$(git rev-parse "$SPLICE_TARGET_REF^{commit}")"
  if upstream_has_state_file "$target"; then
    log_err "$path: upstream has a $STATE_FILE at its root, which would replace $path/$STATE_FILE"
    return 1
  fi
  if [[ -z "$SPLICE_SYNCED" ]]; then
    log_err "$path: no synced commit recorded yet, e.g. after init -- nothing to rebase onto; $verb without --rebase"
    return 1
  fi
  synced_tree="$(git rev-parse "$SPLICE_SYNCED^{tree}")"
  while IFS= read -r commit; do
    [[ "$(splice_config "$path" commit "$commit")" == "$SPLICE_SYNCED" ]] || break
    content_tree "$commit" "$path"
    if [[ "$CONTENT_TREE" == "$synced_tree" ]]; then
      base="$commit"
      break
    fi
  done < <(git rev-list --first-parent HEAD)
  if [[ -z "$base" ]]; then
    log_err "$path: no commit since the synced commit ${SPLICE_SYNCED:0:7} has exactly its files, e.g. after a $verb that merged local changes -- nothing to rebase onto; $verb without --rebase"
    return 1
  fi
  if [[ "$base" == "$(git rev-parse HEAD)" ]]; then
    MERGE_REBASE="" merge_one "$path" "$branch" "$verb"
    return
  fi
  local inner
  inner="$(changed_submodule "$SPLICE_SYNCED" "$target")"
  if [[ -n "$inner" ]]; then
    log_err "$path: upstream has a submodule, $inner, which nobody could check out in the monorepo -- turn it into a splice in the upstream first"
    return 1
  fi
  if [[ "$(git rev-list --min-parents=2 --count "$base..HEAD")" -gt 0 ]]; then
    log_err "$path: there's a merge commit since ${base:0:7}, whose own changes --rebase would drop -- $verb without --rebase"
    return 1
  fi
  # Without merges, a remote-tracking branch that has any of the commits
  # has the oldest one.
  commit="$(git rev-list "$base..HEAD" | tail -n 1)"
  published="$(git for-each-ref --count=1 --contains "$commit" --format='%(refname:short)' refs/remotes/)"
  if [[ -n "$published" ]]; then
    log_err "$path: '$published' has commits since ${base:0:7}, which --rebase would rewrite -- $verb on a branch nobody else has, e.g. a pull request's"
    return 1
  fi
  local blob tree message pull
  blob="$(rebase_state_blob "$path" "$base" "$target")" || return 1
  tree="$(reroot_tree "$path" "$target^{tree}" "$blob" "$base")" || return 1
  message="$(commit_message "splice: $verb $path from $SPLICE_UPSTREAM_LABEL at ${target:0:7}")"
  pull="$(git commit-tree "$tree" -p "$base" -m "$message")" || return 1
  count="$(git rev-list --count "$base..HEAD")"
  if ! git -c advice.mergeConflict=false rebase -q --no-update-refs --no-autostash --onto "$pull" "$base"; then
    if [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" ]]; then
      log_err "$path: conflict while rebasing onto the $verb -- resolve it, then 'git rebase --continue' (or 'git rebase --abort' to give up)"
    else
      log_err "$path: git rebase didn't start, see above -- nothing changed"
    fi
    return 1
  fi
  log_ok "$path: $(past_tense "$verb") ${target:0:7}, and rebased $count commit$([[ "$count" -eq 1 ]] || echo s) onto it"
}

# Prints the blob of splice <path>'s state file in commit <rev>, with
# upstream commit <target> as the synced commit.
rebase_state_blob() {
  local path="$1" rev="$2" target="$3" tmp
  tmp="$(mktemp)"
  git cat-file blob "$rev:$path/$STATE_FILE" >"$tmp" &&
    git config --file "$tmp" splice.commit "$target" &&
    git hash-object -w "$tmp"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

# Succeeds if merging upstream commit <target> into the rebuild
# (SPLICE_REBUILT) from <base> gives exactly <target>'s files, without a
# conflict.
merge_gives() {
  local base="$1" target="$2" tree
  tree="$(git merge-tree --write-tree --merge-base="$base" "$SPLICE_REBUILT" "$target" 2>/dev/null)" || return 1
  [[ "${tree%%$'\n'*}" == "$(git rev-parse "$target^{tree}")" ]]
}

# Prints where the fetched upstream branch (SPLICE_TARGET_REF) was before
# a rewrite took the rebuild's commits out of it: its fork point, git
# merge-base --fork-point, the newest commit the branch's reflog has that
# the rebuild has too, if the branch doesn't have it any more. Prints
# nothing without a rewrite, without a reflog, e.g. in a clone that
# fetched only after the rewrite, or with --no-fork-point.
fork_point() {
  local fork
  [[ -z "${MERGE_NO_FORK_POINT:-}" ]] || return 0
  fork="$(git merge-base --fork-point "$SPLICE_TARGET_REF" "$SPLICE_REBUILT" 2>/dev/null)" || return 0
  git merge-base --is-ancestor "$fork" "$SPLICE_TARGET_REF" || printf '%s\n' "$fork"
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
    "$(commit_message "splice: $verb $path from $SPLICE_UPSTREAM_LABEL at ${target:0:7}")"; then
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
    "$(commit_message "splice: bump $path from $SPLICE_UPSTREAM_LABEL at ${target:0:7}")"; then
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

# Succeeds if the tag or commit the default-pin of splice <path>'s
# upstream in use names is here, or it has none.
pin_here() {
  local pin
  pin="$(upstream_config "$1" "${SPLICE_UPSTREAM_NAMES[$1]:-}" default-pin)"
  if [[ -z "$pin" ]]; then
    return 0
  elif is_commit_id "$pin"; then
    git cat-file -e "$pin^{commit}" 2>/dev/null
  else
    git show-ref --verify --quiet "refs/splices/${SPLICE_KEYS[$1]:-.}/tags/$pin"
  fi
}

# Reads splice <path>'s upstreams again after a merge above changed its
# .splice, and uses the one the command chose (use_upstreams). A pull
# (<verb>) fetches the upstreams it names now, but didn't before: the
# synced commit the merge above moved it to may be in any of them. It
# also fetches the one it uses if that synced commit isn't here: it may
# be on no branch of an upstream it had, e.g. after a force-push, and
# fetch_upstream fetches it by its hash; or if the merge pinned it at a
# tag or commit that isn't here. Fails, saying why, if one can't
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
  if [[ ${#entries[@]} -eq 0 ]] && { ! synced_commit_here "$path" || ! pin_here "$path"; }; then
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
    if [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" ]]; then
      log_err "Not $(past_tense "$verb") yet: ${skipped[*]} -- resolve the conflict, run 'git rebase --continue', then re-run $verb"
    else
      log_err "Not $(past_tense "$verb") yet: ${skipped[*]} -- resolve the conflict, run 'git commit', then re-run $verb"
    fi
  fi
  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
  fi
  [[ ${#skipped[@]} -eq 0 && ${#failures[@]} -eq 0 ]] || exit 1
}

cmd_merge() {
  parse_args usage_merge "--upstream --branch --bump --rebase --no-fork-point -m" "$@"
  require_one_splice_for_message
  REBUILD_JOINS_REWRITTEN=1
  MERGE_BUMP=""
  has_flag --bump && MERGE_BUMP=1
  MERGE_NO_FORK_POINT=""
  has_flag --no-fork-point && MERGE_NO_FORK_POINT=1
  MERGE_REBASE=""
  has_flag --rebase && MERGE_REBASE=1
  [[ -z "$MERGE_BUMP" || -z "$MERGE_REBASE" ]] || die "--bump and --rebase don't go together"
  open_repository
  # Before select_splices: a rebase in progress has detached HEAD.
  require_no_splice_in_progress
  select_splices explicit merge
  merge_paths "$MONOREPO_BRANCH" merge "${SELECTED_PATHS[@]}"
}
