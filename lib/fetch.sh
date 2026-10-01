# Assumes lib/common.sh is already sourced.

usage_fetch() {
  cat <<'EOF'
usage: git subtrees fetch [path...]

Fetches every subtree's remote, updating refs/remotes/<name>/* only --
never FETCH_HEAD. Defaults to every discovered subtree when no paths are
given. Runs fetches in parallel and reports when a remote branch matching
the current branch moved.
EOF
}

# Single synchronous fetch of one subtree's remote. Factored out so it can
# be invoked directly (e.g. from tests) without the parallel/wait plumbing
# in fetch_all_parallel.
fetch_one() {
  local remote="$1" branch="${2:-}"
  if [[ -n "$branch" ]]; then
    local target_ref old_sha
    target_ref="$(target_ref_for "$remote" "$branch")"
    old_sha="$(git rev-parse --verify "$target_ref" 2>/dev/null || true)"
    fetch_branch "$remote" "$branch" || {
      log_err "$remote fetch failed"
      return 1
    }
    log_fetch_success "$remote" "$branch" "$old_sha" "$target_ref"
    return 0
  fi

  # A normal fetch follows all of the remote's configured refspecs. Snapshot
  # the branch matching the monorepo's current branch so the otherwise quiet
  # fetch can still call out the update users are most likely interested in.
  branch="$(git symbolic-ref --quiet HEAD 2>/dev/null || true)"
  branch="${branch#refs/heads/}"
  local target_ref="" old_sha=""
  if [[ -n "$branch" ]]; then
    target_ref="$(target_ref_for "$remote" "$branch")"
    old_sha="$(git rev-parse --verify "$target_ref" 2>/dev/null || true)"
  fi
  if git fetch --quiet --no-write-fetch-head -- "$remote"; then
    log_fetch_success "$remote" "$branch" "$old_sha" "$target_ref"
  else
    log_err "$remote fetch failed"
    return 1
  fi
}

log_fetch_success() {
  local remote="$1" branch="$2" old_sha="$3" target_ref="$4" new_sha=""
  [[ -n "$target_ref" ]] && new_sha="$(git rev-parse --verify "$target_ref" 2>/dev/null || true)"

  if [[ -n "$old_sha" && -n "$new_sha" && "$old_sha" != "$new_sha" ]]; then
    log_ok "$remote fetched ($branch moved ${old_sha:0:7}..${new_sha:0:7})"
  else
    log_ok "$remote fetched"
  fi
}

fetch_branch() {
  local remote="$1" branch="$2" target_ref
  target_ref="$(target_ref_for "$remote" "$branch")"

  git fetch --quiet --no-write-fetch-head -- "$remote" "+refs/heads/$branch:$target_ref"
}

# True if <remote>'s <branch> is absent upstream -- an ls-remote miss,
# distinct from a transport/auth failure. Only probed after fetch_branch
# already failed, so the common (branch exists) case never pays this
# extra round trip.
remote_missing_branch() {
  local remote="$1" branch="$2"
  git ls-remote --exit-code --heads -- "$remote" "refs/heads/$branch" >/dev/null 2>&1
  [[ $? -eq 2 ]]
}

# Like fetch_one <remote> <branch>, but returns 2 if the remote has no such
# branch (e.g. a feature branch not pushed there yet), and 1 only on any
# other failure.
fetch_branch_or_missing() {
  local remote="$1" branch="$2"
  # Deferred: `git fetch` and fetch_one's own log_err already write a fatal
  # diagnostic to stderr the moment the branch fetch fails, before we get a
  # chance to check whether that's actually the missing-branch case.
  # Capture it instead of letting it print immediately, and only replay it
  # once remote_missing_branch has ruled that out.
  local fetch_err fetch_status=0
  {
    fetch_err="$(fetch_one "$remote" "$branch" 2>&1 1>&3)" || fetch_status=$?
  } 3>&1
  ((fetch_status == 0)) && return 0
  if remote_missing_branch "$remote" "$branch"; then
    # A tracking ref left from an earlier fetch would make status and push
    # compare against a branch the remote no longer has.
    git update-ref -d "$(target_ref_for "$remote" "$branch")" || return 1
    return 2
  fi
  printf '%s\n' "$fetch_err" >&2
  return 1
}

declare -ga FETCH_FAILURES=()
declare -ga FETCH_MISSING=()
declare -ga FETCH_PATHS=()
declare -ga FETCH_OUTPUT=()
declare -ga FETCH_STDERR=()

fetch_failed_for_path() {
  local path="$1" failed_path
  for failed_path in "${FETCH_FAILURES[@]}"; do
    [[ "$failed_path" == "$path" ]] && return 0
  done
  return 1
}

fetch_missing_for_path() {
  local path="$1" missing_path
  for missing_path in "${FETCH_MISSING[@]}"; do
    [[ "$missing_path" == "$path" ]] && return 0
  done
  return 1
}

print_fetch_output() {
  local idx="$1"
  [[ -n "${FETCH_OUTPUT[$idx]}" ]] && printf '%s\n' "${FETCH_OUTPUT[$idx]}"
  [[ -n "${FETCH_STDERR[$idx]}" ]] && printf '%s\n' "${FETCH_STDERR[$idx]}" >&2
  return 0
}

# Fetches every given path's remote in parallel. Sets FETCH_PATHS to the
# deduplicated job list, FETCH_FAILURES to the paths whose fetch failed,
# FETCH_MISSING to the paths whose remote has no given branch, and
# FETCH_OUTPUT/FETCH_STDERR to each job's captured stdout/stderr.
#
# A path repeated in the argument list (e.g. `pull vendor/a vendor/a`)
# spawns only one `git fetch` job for it -- two concurrent fetches of the
# same tracking ref can race and fail with a ref-lock error.
fetch_all_parallel() {
  fetch_all_parallel_for_branch "" "$@"
}

fetch_all_parallel_for_branch() {
  local branch="$1"
  shift

  FETCH_FAILURES=()
  FETCH_MISSING=()
  FETCH_PATHS=()
  FETCH_OUTPUT=()
  FETCH_STDERR=()

  local -A seen=()
  local path
  for path in "$@"; do
    [[ -n "${seen[$path]:-}" ]] && continue
    seen[$path]=1
    FETCH_PATHS+=("$path")
  done

  local tmp_dir
  tmp_dir="$(mktemp -d)"

  local pids=() i=0
  for path in "${FETCH_PATHS[@]}"; do
    if [[ -n "$branch" ]]; then
      fetch_branch_or_missing "$path" "$branch" >"$tmp_dir/$i.out" 2>"$tmp_dir/$i.err" &
    else
      fetch_one "$path" >"$tmp_dir/$i.out" 2>"$tmp_dir/$i.err" &
    fi
    pids+=("$!")
    i=$((i + 1))
  done

  local job_status=() idx=0 pid
  for pid in "${pids[@]}"; do
    job_status[idx]=0
    wait "$pid" || job_status[idx]=$?
    idx=$((idx + 1))
  done

  local failures=() out err
  for i in "${!FETCH_PATHS[@]}"; do
    out="$(cat "$tmp_dir/$i.out")"
    err="$(cat "$tmp_dir/$i.err")"
    FETCH_OUTPUT+=("$out")
    FETCH_STDERR+=("$err")
    case "${job_status[i]}" in
      0) ;;
      2) FETCH_MISSING+=("${FETCH_PATHS[$i]}") ;;
      *) failures+=("${FETCH_PATHS[$i]}") ;;
    esac
  done
  rm -rf "$tmp_dir"

  FETCH_FAILURES=("${failures[@]}")
}

cmd_fetch() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage_fetch
    exit 0
  fi
  [[ "${1:-}" == "--" ]] && shift

  cd_to_repo_root
  discover_subtrees

  local paths=("$@")
  if [[ ${#paths[@]} -eq 0 ]]; then
    paths=("${ALL_PATHS[@]}")
  fi
  if [[ ${#paths[@]} -eq 0 ]]; then
    die "no subtrees discovered -- nothing to fetch"
  fi

  local path
  for path in "${paths[@]}"; do
    is_subtree_path "$path" || die "not a subtree path: $path"
  done

  fetch_all_parallel "${paths[@]}"
  local i
  for i in "${!FETCH_PATHS[@]}"; do
    print_fetch_output "$i"
  done

  if [[ ${#FETCH_FAILURES[@]} -gt 0 ]]; then
    log_err "Failed: ${FETCH_FAILURES[*]}"
    exit 1
  fi
}
