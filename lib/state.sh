# Sync state of a splice, and the re-rooted cherry-pick that merge and
# clone use to splice upstream content in. Assumes lib/common.sh and
# lib/rebuild.sh are already sourced.

# Classifies splice <path>'s sync state while the monorepo is on <branch>.
# Sets, as globals, since status, merge, push, diff and log all need them:
#   SPLICE_STATE            see below
#   SPLICE_TARGET_KIND      what this branch syncs with: an upstream branch,
#                           or the tag or commit default-pin names
#                           (resolve_upstream_target)
#   SPLICE_UPSTREAM_BRANCH  its name: the branch's, the tag's, or the
#                           commit id
#   SPLICE_UPSTREAM_LABEL   how messages name it (upstream_branch_label)
#   SPLICE_TARGET_REF       refs/splices/<key>/heads/<branch>,
#                           refs/splices/<key>/tags/<tag>, or the commit id
#   SPLICE_SYNCED           the synced commit U(H) from the state file
#   SPLICE_REBUILT          the rebuild R of HEAD (see splice_rebuild), when
#                           the state needed it
#
# SPLICE_STATE is one of:
#   never-fetched      no upstream branch fetched yet
#   missing-branch     upstream has no branch like this one (or is empty)
#   missing-pin        the tag or commit default-pin names isn't here:
#                      upstream lacks it, or it wasn't fetched yet
#   missing-synced     the synced commit isn't here: a teammate's pull
#                      that wasn't fetched yet, or upstream lacks it
#   up-to-date         the splice's content equals the upstream branch
#   push               pushing fast-forwards the upstream branch
#   pull               the upstream branch has commits this branch lacks
#   diverged           both have commits the other lacks, with a common
#                      ancestor
#   unrelated-history  no common ancestor at all
# Returns 1 if the rebuild fails, after it printed why.
classify_splice() {
  local path="$1" branch="$2"
  require_splice_upstream "$path"
  SPLICE_STATE=""
  SPLICE_TARGET_REF=""
  SPLICE_REBUILT=""
  # Also for a splice a merge above just brought in.
  require_upstream_branches "$branch" "$path"
  resolve_upstream_target "$path" "$branch"
  SPLICE_TARGET_KIND="$TARGET_KIND"
  SPLICE_UPSTREAM_BRANCH="$TARGET_NAME"
  SPLICE_UPSTREAM_LABEL="$(upstream_branch_label "$path" "$(target_label)")"
  SPLICE_SYNCED="$(splice_config "$path" commit)"

  # A pin that's here counts as fetched, though upstream has no branches.
  if ! splice_fetched "$path" &&
    ! { [[ "$SPLICE_TARGET_KIND" != branch ]] && git rev-parse --verify --quiet "$TARGET_REF^{commit}" >/dev/null; }; then
    # Without a synced commit, the splice came from init: its upstream
    # was empty, so a fetch that brings nothing is the expected state. With
    # one that's here, a fetch happened, and the upstream has no branches
    # left. Only a fresh clone of the monorepo has neither refs nor commit.
    # A pin that isn't here then is missing, not a branch.
    if [[ -z "$SPLICE_SYNCED" ]] || git cat-file -e "$SPLICE_SYNCED^{commit}" 2>/dev/null; then
      if [[ "$SPLICE_TARGET_KIND" != branch ]]; then
        SPLICE_STATE="missing-pin"
      else
        SPLICE_STATE="missing-branch"
      fi
    else
      SPLICE_STATE="never-fetched"
    fi
    return
  fi

  SPLICE_TARGET_REF="$TARGET_REF"
  if [[ "$SPLICE_TARGET_KIND" != branch ]]; then
    if ! git rev-parse --verify --quiet "$SPLICE_TARGET_REF^{commit}" >/dev/null; then
      SPLICE_STATE="missing-pin"
      return
    fi
  elif ! git show-ref --verify --quiet "$SPLICE_TARGET_REF"; then
    SPLICE_STATE="missing-branch"
    return
  fi

  local local_tree remote_tree remote_head
  content_tree HEAD "$path" || return 1
  local_tree="$CONTENT_TREE"
  remote_tree="$(git rev-parse "$SPLICE_TARGET_REF^{tree}")"
  # A commit given with push --rebuilt-commit differs in its history, not
  # its files: only comparing commits tells whether it's there yet.
  if [[ -z "${REBUILD_GIVEN[$path]:-}" && -n "$local_tree" && "$local_tree" == "$remote_tree" ]]; then
    SPLICE_STATE="up-to-date"
    return
  fi

  if [[ -n "$SPLICE_SYNCED" ]] && ! git cat-file -e "$SPLICE_SYNCED^{commit}" 2>/dev/null; then
    SPLICE_STATE="missing-synced"
    return
  fi

  SPLICE_REBUILT="$(splice_rebuild "$path")" || return 1
  remote_head="$(git rev-parse "$SPLICE_TARGET_REF^{commit}")"
  if [[ -z "$SPLICE_REBUILT" ]]; then
    SPLICE_STATE="unrelated-history"
  elif [[ "$SPLICE_REBUILT" == "$remote_head" ]]; then
    SPLICE_STATE="up-to-date"
  elif git merge-base --is-ancestor "$remote_head" "$SPLICE_REBUILT"; then
    SPLICE_STATE="push"
  elif git merge-base --is-ancestor "$SPLICE_REBUILT" "$remote_head"; then
    SPLICE_STATE="pull"
  elif git merge-base "$SPLICE_REBUILT" "$remote_head" >/dev/null 2>&1; then
    SPLICE_STATE="diverged"
  else
    SPLICE_STATE="unrelated-history"
  fi
}

# For a splice whose upstream lacks the current branch, compares the
# rebuild with upstream's default branch instead, as a PR from the branch
# would. Sets:
#   SPLICE_REBUILT          the rebuild R (empty: no content)
#   SPLICE_DEFAULT_BRANCH   upstream's default branch, or the tag or commit
#                           default-pin names, for messages
#   SPLICE_DEFAULT_REF      its fetched ref, or the commit; empty if
#                           upstream doesn't have it, e.g. an empty upstream
#                           after init
#   SPLICE_NEW_COMMITS      commits of R the default branch lacks: the
#                           push that creates the branch publishes them
#   SPLICE_BEHIND_COMMITS   commits of the default branch R lacks
#   SPLICE_NO_CHANGES       1 if a PR from R to the default branch would
#                           show no changes: R has the files of the commit
#                           where it meets the default branch. Its commits
#                           may still be new, e.g. a change and its revert.
# Commits from the monorepo branch the current one was cut from count too:
# upstream may never have taken them. Returns 1 if upstream's default
# branch is unknown, or the rebuild or the count fails.
compare_with_default_branch() {
  local path="$1" counts merge_base
  SPLICE_NEW_COMMITS=0 SPLICE_BEHIND_COMMITS=0 SPLICE_DEFAULT_REF="" SPLICE_NO_CHANGES=""
  resolve_default_target "$path"
  [[ -n "$TARGET_NAME" ]] || return 1
  SPLICE_DEFAULT_BRANCH="$(target_label)"
  SPLICE_REBUILT="$(splice_rebuild "$path")" || return 1
  [[ -n "$SPLICE_REBUILT" ]] || return 0
  if git rev-parse --verify --quiet "$TARGET_REF^{commit}" >/dev/null; then
    SPLICE_DEFAULT_REF="$TARGET_REF"
    counts="$(git rev-list --left-right --count "$SPLICE_REBUILT...$SPLICE_DEFAULT_REF")" || return 1
    read -r SPLICE_NEW_COMMITS SPLICE_BEHIND_COMMITS <<<"$counts"
    if merge_base="$(git merge-base "$SPLICE_REBUILT" "$SPLICE_DEFAULT_REF")" &&
      [[ "$(git rev-parse "$SPLICE_REBUILT^{tree}")" == "$(git rev-parse "$merge_base^{tree}")" ]]; then
      SPLICE_NO_CHANGES=1
    fi
  else
    SPLICE_NEW_COMMITS="$(git rev-list --count "$SPLICE_REBUILT")" || return 1
  fi
}

# Prints a tree: commit <rev>'s (default HEAD), with folder <path>
# replaced by <folder-tree> (nothing: no folder) plus state file blob
# <blob> (nothing: none). Uses a temporary index, so neither the worktree
# nor the real index changes.
reroot_tree() {
  local path="$1" folder="$2" blob="$3" rev="${4:-HEAD}" index rc=0
  index="$(mktemp)"
  {
    GIT_INDEX_FILE="$index" git read-tree "$rev" &&
      GIT_INDEX_FILE="$index" git rm -r -q -f --cached --ignore-unmatch -- ":(top,literal)$path" &&
      if [[ -n "$folder" ]]; then
        GIT_INDEX_FILE="$index" git read-tree --prefix="$path/" "$folder"
      fi &&
      if [[ -n "$blob" ]]; then
        GIT_INDEX_FILE="$index" git update-index --add --cacheinfo "100644,$blob,$path/$STATE_FILE"
      fi &&
      GIT_INDEX_FILE="$index" git write-tree
  } || rc=$?
  rm -f "$index"
  return "$rc"
}

# True while a cherry-pick, merge or rebase waits to be concluded. Another one
# can't start then, so the multi-path loops must stop.
splice_in_progress() {
  git rev-parse --quiet --verify CHERRY_PICK_HEAD >/dev/null 2>&1 ||
    git rev-parse --quiet --verify MERGE_HEAD >/dev/null 2>&1 ||
    [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" ]]
}

# Splices upstream content into <path> as one ordinary commit: a three-way
# merge of HEAD's folder with <new-folder>, using <base-folder> as the
# merge base. The state file goes from <base-blob> to <new-blob> in the
# same commit. Both sides are re-rooted into the monorepo's layout as two
# throwaway commits, and the second is cherry-picked:
#
#   base   = HEAD, with <path> = <base-folder> + <base-blob>
#   theirs = HEAD, with <path> = <new-folder>  + <new-blob>, parent: base
#
# Only <path> differs between base and theirs, so only the splice can conflict.
# Returns 1 on a conflict, leaving it to be resolved like any other.
splice_in() {
  local path="$1" base_folder="$2" base_blob="$3" new_folder="$4" new_blob="$5" message="$6"
  local base_tree new_tree base theirs output
  base_tree="$(reroot_tree "$path" "$base_folder" "$base_blob")" || return 1
  new_tree="$(reroot_tree "$path" "$new_folder" "$new_blob")" || return 1
  base="$(git commit-tree --no-gpg-sign "$base_tree" -m "base for $message")" || return 1
  theirs="$(git commit-tree --no-gpg-sign "$new_tree" -p "$base" -m "$message")" || return 1

  # Git's own hints would suggest `cherry-pick --continue` or `--skip`;
  # the message below says what fits a splice instead.
  if output="$(git -c advice.mergeConflict=false -c advice.resolveConflict=false cherry-pick "$theirs" 2>&1)"; then
    return 0
  fi
  # "could not apply <theirs>" names the throwaway commit: no use to anyone.
  printf '%s\n' "$output" | grep -v '^error: could not apply ' >&2
  if git rev-parse --quiet --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
    log_err "$path: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)"
  fi
  return 1
}

# What's known when splice <path>'s synced commit isn't here
# (missing-synced): a fetch gets it unless upstream lacks it.
missing_synced_message() {
  local path="$1"
  printf "synced commit %s isn't here -- run 'git splice fetch %s%s', or check that upstream has it\n" \
    "${SPLICE_SYNCED:0:7}" "$(upstream_option "$path")" "$path"
}

# Prints manual recovery commands for a splice in the "unrelated-history"
# state. With no common ancestor there's no principled automatic merge,
# only a human decision about which side to keep.
print_unrelated_history_guidance() {
  local path="$1" q_path q_url
  q_path="$(shell_quote "$path")"
  q_url="$(shell_quote "${SPLICE_URLS[$path]}")"
  log_warn "$path: upstream and the splice share no history -- pick a side:"
  cat >&2 <<EOF

  # keep the upstream version, discarding local changes under $path:
  git rm -r -q -- $q_path && git commit -m $(shell_quote "remove $path")
  git splice clone -- $q_url $q_path

  # OR: keep both, resolving every file that differs as a conflict:
  git rm -q -- $(shell_quote "$path/$STATE_FILE") && git commit -m $(shell_quote "unsplice $path")
  git splice clone --merge -- $q_url $q_path

  # OR: keep the monorepo version, overwriting upstream's branch:
  git splice push $(selection_options "$path")--force -- $q_path

EOF
}
