# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_push() {
  cat <<'EOF'
usage: git splice push [--upstream <name>] [--force] (<path>... | --all)
       git splice push [--upstream <name>] [--force] --rebuilt-commit <commit> <path>

Publishes each splice's local changes: rebuilds the commits that changed
it since its boundary, without its .splice file, and pushes them to its
upstream URL. Nothing is written to the monorepo.

Bottom-up: a splice below another is pushed first, since the push of the
one above publishes its .splice, and a failed push stops the splices
above it.

If the upstream has no branch named like the current one, push creates it
-- but only if it has commits upstream's default branch lacks, so working
on a feature branch doesn't spawn empty branches upstream. Commits the
feature branch got from the branch it was cut from count too: when
upstream takes changes only through PRs, that's how they get there.

--force overwrites the upstream branch with the monorepo's side: when the
two share no history, or to discard commits only upstream has.

--rebuilt-commit pushes <commit> instead of the rebuild, e.g. one whose
history was edited after 'git splice rebuild <path>' printed it:
messages reworded, commits squashed. Only the history: its files must be
the folder's, and it must contain the synced commit -- with --force, it
may also replace commits the upstream already has. Either way, a pull
must be able to record it: a commit of the rebuild's history that isn't
newer than the synced commit is refused. push checks only that; the
rest of <commit>'s history -- its parents, the files of the commits
before it -- is pushed as it is, as with 'git push'. Like every
push, it records no sync point: the monorepo keeps rebuilding the
original commits, and a later push publishes them too, unless 'git
splice pull --bump <path>' records <commit> as the synced commit before
the next change, as push reminds you.

Only committed changes are pushed; push warns about uncommitted ones in a
splice's folder.

--upstream names one of the upstreams a splice's .splice names; without
it, the splice's default upstream. A splice without the named upstream
stops the command before it starts.
EOF
}

# Pushes one splice. $3 is "force" for --force.
push_one() {
  local path="$1" branch="$2" force="${3:-}" rc=0

  has_uncommitted_changes "$path" || rc=$?
  case "$rc" in
    0) log_warn "$path: uncommitted changes aren't pushed -- commit them first" ;;
    2) log_warn "$path: could not check for uncommitted changes (git status failed) -- only committed ones are pushed" ;;
  esac
  classify_splice "$path" "$branch" || return 1
  local upstream_branch="$SPLICE_UPSTREAM_BRANCH" label="$SPLICE_UPSTREAM_LABEL" option
  option="$(upstream_option "$path")"
  case "$SPLICE_STATE" in
    never-fetched)
      log_warn "$path: not fetched -- run 'git splice fetch $option$path' first"
      return 1
      ;;
    up-to-date)
      log_ok "$path: nothing to push"
      remind_pull "$path" "$option"
      return 0
      ;;
    pull)
      if [[ -z "$force" ]]; then
        log_ok "$path: nothing to push (upstream is ahead -- 'git splice pull $option$path' brings it in)"
        return 0
      fi
      ;;
    diverged)
      if [[ -z "$force" ]]; then
        log_err "$path: upstream has commits this branch lacks -- run 'git splice pull $option$path' first"
        return 1
      fi
      ;;
    unrelated-history)
      if [[ -z "$force" ]]; then
        print_unrelated_history_guidance "$path"
        return 1
      fi
      [[ -n "$SPLICE_REBUILT" ]] || SPLICE_REBUILT="$(REBUILD_WITHOUT_SYNCED=1 splice_rebuild "$path")" || return 1
      ;;
    missing-branch)
      if ! compare_with_default_branch "$path"; then
        if [[ -z "$SPLICE_DEFAULT_BRANCH" ]]; then
          log_err "$path: upstream has no '$label' branch, and its default branch is unknown -- not creating '$label'"
        else
          log_err "$path: could not compare with upstream's '$SPLICE_DEFAULT_BRANCH' -- not creating '$label'"
        fi
        return 1
      fi
      # A commit given with --rebuilt-commit is pushed even if upstream's
      # default branch has it: it was asked for, and needs recording.
      if [[ -n "$SPLICE_REBUILT" && -z "${REBUILD_GIVEN[$path]:-}" ]] && ((SPLICE_NEW_COMMITS == 0)); then
        log_ok "$path: nothing to push (upstream has no '$label' branch, and '$SPLICE_DEFAULT_BRANCH' has every commit)"
        return 0
      fi
      [[ -z "$SPLICE_REBUILT" ]] || log_warn "$path: upstream has no '$label' branch yet -- this push creates it"
      ;;
    push) ;;
  esac

  if [[ -z "$SPLICE_REBUILT" ]]; then
    log_ok "$path: nothing to push (no content)"
    return 0
  fi

  local url force_flag=()
  url="${SPLICE_URLS[$path]}"
  [[ -n "$force" ]] && force_flag=(--force)
  # Before the push, so a failure to record the key can't follow a push
  # that already happened.
  ensure_splice_key "$path"
  if ! git push "${force_flag[@]}" --quiet -- "$url" "$SPLICE_REBUILT:refs/heads/$upstream_branch"; then
    log_err "$path: push failed"
    return 1
  fi
  # Pushing to a URL updates no ref here, so record what upstream has now.
  if ! git update-ref "$(splice_ref "$path" "$upstream_branch")" "$SPLICE_REBUILT"; then
    log_err "$path: pushed, but couldn't record it in $(splice_ref "$path" "$upstream_branch") -- run 'git splice fetch $option$path'"
    return 1
  fi
  log_ok "$path: pushed ${SPLICE_REBUILT:0:7} to $label"
  remind_pull "$path" "$option"
}

# Reminds to record the commit given for splice <path> with a pull, if
# one was given and the monorepo's rebuild isn't that commit already.
# Also after a retry that finds it upstream: the earlier push may have
# gone through without its reminder. $2 is the --upstream option, if any.
remind_pull() {
  local path="$1" option="$2"
  [[ -z "${REBUILD_GIVEN[$path]:-}" ]] || given_is_rebuild "$path" ||
    log_warn "$path: run 'git splice pull --bump $option$path' before the next change to it -- that records ${REBUILD_GIVEN[$path]:0:7} as the synced commit"
}

# Succeeds if the commit given for splice <path> is the monorepo's own
# rebuild, which needs no record. Any other, even an ancestor of the
# rebuild with the same files, leaves the rebuild with commits the
# upstream doesn't have, which the next push would publish. Without the
# synced commit here, there's no rebuild to compare with.
given_is_rebuild() {
  local path="$1" synced
  synced="$(splice_config "$path" commit)"
  [[ -z "$synced" ]] || git cat-file -e "$synced^{commit}" 2>/dev/null || return 1
  [[ "${REBUILD_GIVEN[$path]}" == "$(rebuild_splice "$path" HEAD)" ]]
}

# Records <commit> as the rebuild push sends for splice <path>
# (REBUILD_GIVEN), after checking that it differs from the rebuild only in
# its history: the same files as <path> in HEAD, on top of the synced
# commit -- unless $3 is "force", which may replace the published history
# too. An upstream that has moved on is left to the push to reject.
give_rebuild() {
  local path="$1" commit="$2" force="${3:-}" rebuilt synced outcome
  rebuilt="$(git rev-parse --verify --quiet "$commit^{commit}")" ||
    die "--rebuilt-commit: unknown commit: $commit"
  content_tree HEAD "$path"
  [[ "$(git rev-parse "$rebuilt^{tree}")" == "$CONTENT_TREE" ]] ||
    die "$path: ${rebuilt:0:7} has other files than the folder -- --rebuilt-commit only takes edits to the history; commit changes to files in the monorepo"
  synced="$(splice_config "$path" commit)"
  # The monorepo's own rebuild needs no record, even where it's the
  # synced commit, e.g. with an upstream that's ahead.
  outcome="$(equal_tree_outcome "$path" "$rebuilt")" || exit 1
  [[ "$outcome" != keep || "$rebuilt" == "$(rebuild_splice "$path" HEAD)" ]] ||
    die "$path: pull can't record ${rebuilt:0:7} as the synced commit -- it isn't newer than ${synced:0:7}, so the next push would publish the rebuild's commits after it again"
  if [[ -n "$synced" && -z "$force" ]]; then
    git cat-file -e "$synced^{commit}" 2>/dev/null ||
      die "$path: synced commit ${synced:0:7} isn't available locally -- run 'git splice fetch $(upstream_option "$path")$path'"
    git merge-base --is-ancestor "$synced" "$rebuilt" ||
      die "$path: ${rebuilt:0:7} doesn't contain the synced commit ${synced:0:7} -- edit only the commits after it, or replace published ones with --force"
  fi
  REBUILD_GIVEN[$path]="$rebuilt"
}

cmd_push() {
  parse_args usage_push "--force --upstream --rebuilt-commit" "$@"
  local force=""
  has_flag --force && force=force
  open_repository
  select_splices explicit push
  if [[ -n "$REBUILT_COMMIT_ARG" ]]; then
    [[ -z "$ALL_ARG" && ${#SELECTED_PATHS[@]} -eq 1 ]] ||
      die "--rebuilt-commit takes exactly one splice"
    give_rebuild "${SELECTED_PATHS[0]}" "$REBUILT_COMMIT_ARG" "$force"
  fi
  local branch="$MONOREPO_BRANCH" path failed paths=() failures=()

  # Pushes to the same host share one SSH connection.
  local ssh_control_dir
  ssh_control_dir="$(mktemp -d)"
  # Expanded now: the local is gone by the time the shell exits.
  # shellcheck disable=SC2064
  trap "rm -rf -- $(printf '%q' "$ssh_control_dir")" EXIT
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=$ssh_control_dir/%r@%h:%p"

  # Bottom-up: a splice's push publishes the .splice files below it, which
  # should point at what their own pushes published.
  mapfile -t paths < <(splices_in_order bottom-up "${SELECTED_PATHS[@]}")
  for path in "${paths[@]}"; do
    if failed="$(first_below "$path" "${failures[@]}")"; then
      log_err "$path: not pushed, since $failed below it failed"
      failures+=("$path")
      continue
    fi
    push_one "$path" "$branch" "$force" || failures+=("$path")
  done
  rm -rf "$ssh_control_dir"

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
