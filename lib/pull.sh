# Assumes lib/common.sh, lib/fetch.sh and lib/merge.sh are already sourced.

usage_pull() {
  cat <<'EOF'
usage: git splice pull (<path>... | --all)

'git splice fetch' followed by 'git splice merge': fetches the splices'
upstreams in parallel, then splices their changes in, as one ordinary
commit per splice. Also fetches the splices nested in each: pulling a
splice can move their synced commits.

On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
--abort' to give up), then re-run pull for any splices left.
EOF
}

# Succeeds if splice <path> is nested in one in SELECTED_PATHS, but isn't
# selected itself.
nested_in_selected() {
  local selected nested=""
  for selected in "${SELECTED_PATHS[@]}"; do
    [[ "$1" != "$selected" ]] || return 1
    [[ "$1" != "$selected"/* ]] || nested=1
  done
  [[ -n "$nested" ]]
}

# Prints the first splice nested in <path> whose fetch failed, or fails if
# there's none.
nested_fetch_failure() {
  local failed_path
  for failed_path in "${FETCH_FAILURES[@]}"; do
    [[ "$failed_path" != "$1"/* ]] || {
      printf '%s\n' "$failed_path"
      return 0
    }
  done
  return 1
}

cmd_pull() {
  parse_args usage_pull "" "$@"
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths explicit pull
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"
  local branch i path nested fetched=() fetch_paths=("${SELECTED_PATHS[@]}")
  branch="$(current_branch)"

  for path in "${ALL_PATHS[@]}"; do
    nested_in_selected "$path" && fetch_paths+=("$path")
  done
  fetch_all_parallel "$branch" "${fetch_paths[@]}"
  for i in "${!fetch_paths[@]}"; do
    print_fetch_output "$i"
  done
  for path in "${SELECTED_PATHS[@]}"; do
    fetch_failed_for_path "$path" && continue
    if nested="$(nested_fetch_failure "$path")"; then
      # Its pull could move $nested's synced commit to one that wasn't fetched.
      log_err "$path: not pulled, since $nested wasn't fetched -- 'git splice merge $path' merges what was fetched anyway"
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
