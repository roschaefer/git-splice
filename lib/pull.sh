# Assumes lib/common.sh, lib/fetch.sh and lib/merge.sh are already sourced.

usage_pull() {
  cat <<'EOF'
usage: git splice pull (<path>... | --all)

'git splice fetch' followed by 'git splice merge': fetches the splices'
upstreams in parallel, then splices their changes in, as one ordinary
commit per splice. Also fetches the splices below each: pulling a splice
can move their synced commits. Top-down: a splice is pulled before the
ones below it, and a failed fetch stops the splices above and below it.

On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
--abort' to give up), then re-run pull for any splices left.
EOF
}

# Succeeds if splice <path> is below one in SELECTED_PATHS, but isn't
# selected itself.
below_selected() {
  local selected below=""
  for selected in "${SELECTED_PATHS[@]}"; do
    [[ "$1" != "$selected" ]] || return 1
    [[ "$1" != "$selected"/* ]] || below=1
  done
  [[ -n "$below" ]]
}

cmd_pull() {
  parse_args usage_pull "" "$@"
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths explicit pull
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"
  local branch i path failed fetched=() fetch_paths=("${SELECTED_PATHS[@]}")
  branch="$(current_branch)"

  for path in "${ALL_PATHS[@]}"; do
    below_selected "$path" && fetch_paths+=("$path")
  done
  fetch_all_parallel "$branch" "${fetch_paths[@]}"
  for i in "${!fetch_paths[@]}"; do
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
