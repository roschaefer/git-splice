# Assumes lib/common.sh, lib/fetch.sh and lib/merge.sh are already sourced.

usage_pull() {
  cat <<'EOF'
NAME
    git-splice-pull - Fetch and splice in upstream changes

SYNOPSIS
    git splice pull [--upstream <name>] [--branch <name>] [--bump | --rebase] [--no-fork-point] (<path>... | --all)
    git splice pull [<option>...] -m <message> <path>

DESCRIPTION
    'git splice fetch' followed by 'git splice merge': fetches the splices'
    upstreams in parallel, then splices their changes in, as one ordinary
    commit per splice. Also fetches the splices below each: pulling a splice
    can move their synced commits. Top-down: a splice is pulled before the
    ones below it, and a failed fetch stops the splices above and below it.

    On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
    --abort' to give up), then re-run pull for any splices left. With
    --rebase, it's 'git rebase --continue' (or 'git rebase --abort').

    --upstream names one of the upstreams a splice's .splice names; without
    it, the splice's default upstream. A splice without the named upstream
    stops the command before it starts. The splices below, selected or not,
    are fetched from every upstream they name: names are only unique within one .splice, and
    any of them may have the synced commit the pull moves to.

    --branch names the upstream branch to pull, for this pull only; --rebase
    rebases instead of merging, like 'git pull --rebase'; see 'git splice
    merge --help' for both.

    --bump also moves the synced commit up to the upstream branch when there's
    nothing to pull, e.g. right after a push; see 'git splice merge --help'.

    --no-fork-point merges a rewritten upstream branch from Git's merge base,
    not from where the branch was before the rewrite; see 'git splice merge
    --help'.

    -m gives the commit this message, for one splice; see 'git splice merge
    --help'.
EOF
}

# Succeeds if splice <path> is below one in SELECTED_PATHS, selected
# itself or not: a pull above can move its synced commit.
below_selected() {
  local selected
  for selected in "${SELECTED_PATHS[@]}"; do
    [[ "$1" != "$selected"/* ]] || return 0
  done
  return 1
}

cmd_pull() {
  parse_args usage_pull "--upstream --branch --bump --rebase --no-fork-point -m" "$@"
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
  select_splices explicit pull
  local branch="$MONOREPO_BRANCH" i path failed fetched=() top=() below=() entries=()

  for path in "${SELECTED_PATHS[@]}"; do
    below_selected "$path" || top+=("$path")
  done
  for path in "${ALL_PATHS[@]}"; do
    below_selected "$path" && below+=("$path")
  done
  mapfile -t entries < <(
    used_upstream_entry "${top[@]}"
    every_upstream_entry "${below[@]}"
  )
  fetch_all_parallel "$branch" "${entries[@]}"
  for i in "${!entries[@]}"; do
    print_fetch_output "$i"
  done
  for path in "${SELECTED_PATHS[@]}"; do
    fetch_failed_for_path "$path" && continue
    if failed="$(first_above "$path" "${FETCH_FAILURES[@]}")"; then
      log_err "$path: not pulled, since $failed above it wasn't fetched"
      continue
    fi
    # Its pull could move the synced commit of $failed to one that wasn't
    # fetched.
    if failed="$(first_below "$path" "${FETCH_FAILURES[@]}")"; then
      log_err "$path: not pulled, since $failed below it wasn't fetched -- 'git splice merge $path' merges what was fetched anyway"
      continue
    fi
    fetched+=("$path")
  done

  local status=0
  if [[ ${#fetched[@]} -gt 0 ]]; then
    (merge_paths "$branch" pull "${fetched[@]}") || status=$?
  fi
  if [[ ${#FETCH_FAILURES[@]} -gt 0 ]]; then
    log_err "Not fetched: ${FETCH_FAILURES[*]}"
    status=1
  fi
  exit "$status"
}
