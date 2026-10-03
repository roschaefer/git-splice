# Assumes lib/common.sh, lib/fetch.sh and lib/merge.sh are already sourced.

usage_pull() {
  cat <<'EOF'
usage: git splice pull (<path>... | --all)

'git splice fetch' followed by 'git splice merge': fetches the splices'
upstreams in parallel, then splices their changes in, as one ordinary
commit per splice.

On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
--abort' to give up), then re-run pull for any splices left.
EOF
}

cmd_pull() {
  parse_args usage_pull "" "$@"
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths explicit pull
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"
  local branch i fetched=()
  branch="$(current_branch)"

  fetch_all_parallel "$branch" "${SELECTED_PATHS[@]}"
  for i in "${!SELECTED_PATHS[@]}"; do
    print_fetch_output "$i"
    fetch_failed_for_path "${SELECTED_PATHS[$i]}" || fetched+=("${SELECTED_PATHS[$i]}")
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
