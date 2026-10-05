# Assumes lib/common.sh is already sourced.

usage_fetch() {
  cat <<'EOF'
usage: git splice fetch [path...]

Fetches every branch of each splice's upstream into
refs/splices/<key>/-/*, where <key> is the upstream's URL escaped for
a ref name, e.g. https%3A/%/github.com/x/lib.git -- by URL, there is no
Git remote. Branches deleted
upstream are pruned. Defaults to every splice when no paths are given.
Fetches upstreams in parallel, each once, and reports when the branch a
splice syncs with moved.
EOF
}

# Fetches every branch of upstream <url> into <prefix>*, pruning those that
# are gone. The rebuild starts at a splice's synced commit; any <commit>
# given that no branch upstream has any more (e.g. after a force push) is
# fetched by id.
fetch_upstream() {
  local url="$1" prefix="$2" commit
  shift 2
  git fetch --quiet --no-tags --no-write-fetch-head --prune -- "$url" "+refs/heads/*:$prefix*" || return 1
  for commit in "$@"; do
    # A splice made by init has no synced commit until its first pull.
    [[ -n "$commit" ]] || continue
    if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
      git fetch --quiet --no-tags --no-write-fetch-head -- "$url" "$commit" 2>/dev/null || true
    fi
  done
}

# Fetches the upstream that splices <path>... share, and reports for each
# whether the branch it syncs with moved, while the monorepo is on branch
# $1. Writes what to print for path number <i> of the whole fetch to
# $2/<i>.out and $2/<i>.err, and creates $2/<i>.failed if it failed; $3
# holds those numbers, space-separated.
fetch_shared_upstream() {
  local branch="$1" out_dir="$2" indexes=() i=0 path synced=() upstream_branches=() target_refs=() old_shas=() new_sha
  read -r -a indexes <<<"$3"
  shift 3
  for path in "$@"; do
    upstream_branches[i]="$(upstream_branch_for "$path" "$branch")"
    target_refs[i]="$(splice_ref "$path" "${upstream_branches[i]}")"
    old_shas[i]="$(git rev-parse --verify --quiet "${target_refs[i]}" || true)"
    synced+=("$(splice_config "$path" commit)")
    i=$((i + 1))
  done
  local error
  if ! error="$(fetch_upstream "${SPLICE_URLS[$1]}" "$(splice_refs_prefix "$1")" "${synced[@]}" 2>&1)"; then
    for i in "${!indexes[@]}"; do
      {
        [[ -z "$error" ]] || printf '%s\n' "$error"
        log_err "${*:i+1:1} fetch failed"
      } >"$out_dir/${indexes[i]}.err" 2>&1
      : >"$out_dir/${indexes[i]}.out"
      : >"$out_dir/${indexes[i]}.failed"
    done
    return 1
  fi
  i=0
  for path in "$@"; do
    new_sha="$(git rev-parse --verify --quiet "${target_refs[i]}" || true)"
    if [[ -n "${old_shas[i]}" && -n "$new_sha" && "${old_shas[i]}" != "$new_sha" ]]; then
      log_ok "$path fetched (${upstream_branches[i]} moved ${old_shas[i]:0:7}..${new_sha:0:7})"
    else
      log_ok "$path fetched"
    fi >"$out_dir/${indexes[i]}.out"
    # What git printed on success, e.g. an SSH warning, shown once.
    if ((i == 0)) && [[ -n "$error" ]]; then
      printf '%s\n' "$error"
    fi >"$out_dir/${indexes[i]}.err"
    i=$((i + 1))
  done
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

# Fetches the upstreams of every given (distinct) path in parallel, each
# upstream once: splices with the same URL share their fetched refs, and
# two fetches into the same refs would fail on each other's locks. $1 is
# the monorepo's current branch, to report when a splice's counterpart
# moved. Sets FETCH_FAILURES to the paths whose fetch failed, and
# FETCH_OUTPUT/FETCH_STDERR to what to print for each path, in the order
# of the paths.
fetch_all_parallel() {
  local branch="$1"
  shift
  FETCH_FAILURES=()
  FETCH_OUTPUT=()
  FETCH_STDERR=()

  local paths=("$@") i key keys=() members=()
  local -A indexes_of_key=()
  for i in "${!paths[@]}"; do
    key="${SPLICE_KEYS[${paths[$i]}]}"
    [[ -n "${indexes_of_key[$key]+set}" ]] || keys+=("$key")
    indexes_of_key[$key]+="$i "
  done

  local tmp_dir pids=()
  tmp_dir="$(mktemp -d)"
  for key in "${keys[@]}"; do
    members=()
    for i in ${indexes_of_key[$key]}; do
      members+=("${paths[$i]}")
    done
    fetch_shared_upstream "$branch" "$tmp_dir" "${indexes_of_key[$key]}" "${members[@]}" &
    pids+=("$!")
  done
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" || true
  done

  for i in "${!paths[@]}"; do
    FETCH_OUTPUT+=("$(cat "$tmp_dir/$i.out")")
    FETCH_STDERR+=("$(cat "$tmp_dir/$i.err")")
    [[ ! -e "$tmp_dir/$i.failed" ]] || FETCH_FAILURES+=("${paths[$i]}")
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
