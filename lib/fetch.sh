# Assumes lib/common.sh is already sourced.

usage_fetch() {
  cat <<'EOF'
usage: git splice fetch [path...]

Fetches every branch of each splice's upstream into refs/splices/<path>/*,
by URL -- there is no Git remote. Branches deleted upstream are pruned.
Defaults to every splice when no paths are given. Runs fetches in parallel
and reports when the branch this one syncs with moved.
EOF
}

# Fetches one splice's upstream: every branch, pruning those that are gone.
# $2 is the monorepo's current branch, to report when its counterpart moved.
fetch_one() {
  local path="$1" branch="$2" url synced target_ref old_sha new_sha upstream_branch
  url="$(splice_config "$path" url)"
  [[ -n "$url" ]] || {
    log_err "$path: no url in $path/$STATE_FILE"
    return 1
  }
  upstream_branch="$(upstream_branch_for "$path" "$branch")"
  target_ref="$(splice_ref "$path" "$upstream_branch")"
  old_sha="$(git rev-parse --verify --quiet "$target_ref" || true)"

  if ! git fetch --quiet --no-tags --no-write-fetch-head --prune -- \
    "$url" "+refs/heads/*:refs/splices/$path/*"; then
    log_err "$path fetch failed"
    return 1
  fi

  # The rebuild starts at the synced commit. If no branch upstream has it
  # any more (e.g. after a force push), try fetching it by id.
  synced="$(splice_config "$path" commit)"
  if [[ -n "$synced" ]] && ! git cat-file -e "$synced^{commit}" 2>/dev/null; then
    git fetch --quiet --no-tags --no-write-fetch-head -- "$url" "$synced" 2>/dev/null || true
  fi

  new_sha="$(git rev-parse --verify --quiet "$target_ref" || true)"
  if [[ -n "$old_sha" && -n "$new_sha" && "$old_sha" != "$new_sha" ]]; then
    log_ok "$path fetched ($upstream_branch moved ${old_sha:0:7}..${new_sha:0:7})"
  else
    log_ok "$path fetched"
  fi
}

declare -ga FETCH_FAILURES=()
declare -ga FETCH_OUTPUT=()
declare -ga FETCH_STDERR=()

fetch_failed_for_path() {
  local path="$1" failed_path
  for failed_path in "${FETCH_FAILURES[@]}"; do
    [[ "$failed_path" == "$path" ]] && return 0
  done
  return 1
}

print_fetch_output() {
  local idx="$1"
  [[ -n "${FETCH_OUTPUT[$idx]}" ]] && printf '%s\n' "${FETCH_OUTPUT[$idx]}"
  [[ -n "${FETCH_STDERR[$idx]}" ]] && printf '%s\n' "${FETCH_STDERR[$idx]}" >&2
  return 0
}

# Fetches every given (distinct) path in parallel, while the monorepo is on
# branch $1. Sets FETCH_FAILURES to the paths whose fetch failed, and
# FETCH_OUTPUT/FETCH_STDERR to each job's captured stdout/stderr, in the
# order of the paths.
fetch_all_parallel() {
  local branch="$1"
  shift
  FETCH_FAILURES=()
  FETCH_OUTPUT=()
  FETCH_STDERR=()

  local tmp_dir pids=() i=0 path
  tmp_dir="$(mktemp -d)"
  for path in "$@"; do
    fetch_one "$path" "$branch" >"$tmp_dir/$i.out" 2>"$tmp_dir/$i.err" &
    pids+=("$!")
    i=$((i + 1))
  done

  local paths=("$@")
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" || FETCH_FAILURES+=("${paths[$i]}")
    FETCH_OUTPUT+=("$(cat "$tmp_dir/$i.out")")
    FETCH_STDERR+=("$(cat "$tmp_dir/$i.err")")
  done
  rm -rf "$tmp_dir"
}

cmd_fetch() {
  parse_args usage_fetch "" "$@"
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths overview fetch
  local branch i
  branch="$(current_branch)"

  fetch_all_parallel "$branch" "${SELECTED_PATHS[@]}"
  for i in "${!SELECTED_PATHS[@]}"; do
    print_fetch_output "$i"
  done

  if [[ ${#FETCH_FAILURES[@]} -gt 0 ]]; then
    log_err "Failed: ${FETCH_FAILURES[*]}"
    exit 1
  fi
}
