# Assumes lib/common.sh is already sourced.

usage_fetch() {
  cat <<'EOF'
NAME
    git-splice-fetch - Fetch splice upstreams

SYNOPSIS
    git splice fetch [--upstream <name>] [--branch <name> --track | --no-track] [path...]

DESCRIPTION
    Fetches every branch of each splice's upstreams into
    refs/splices/<key>/heads/*, where <key> is the upstream's key in this
    repository, e.g. lib for https://github.com/x/lib.git -- by URL, there is
    no Git remote; 'git splice key' prints and renames keys. Branches deleted
    upstream are pruned. Defaults to every splice when no paths are given.
    Fetches upstreams in parallel, each once, and reports when the branch a
    splice syncs with has moved.

    A splice whose .splice names several upstreams has each fetched, unless
    --upstream names one.

    --branch <name> --track also tracks that upstream branch on the current
    branch, without a pull or push: from then on, every command syncs the
    splice with it there, and 'git splice status' compares with it.
    --no-track stops tracking one, so the splice syncs with the branch named
    like the current one again. See 'git splice merge --help'.
EOF
}

# Fetches every branch of upstream <url> into <prefix>*, pruning those that
# are gone, with a reflog for each, as Git keeps for refs/remotes/: merge
# finds a rewritten branch's fork point in it. The rebuild starts at a
# splice's synced commit; any <commit> given that no branch upstream has
# any more (e.g. after a force push) is fetched by id.
fetch_upstream() {
  local url="$1" prefix="$2" commit
  shift 2
  git -c core.logAllRefUpdates=always fetch --quiet --no-recurse-submodules --no-tags --no-write-fetch-head --prune -- "$url" "+refs/heads/*:$prefix*" || return 1
  for commit in "$@"; do
    # A splice made by init has no synced commit until its first pull.
    [[ -n "$commit" ]] || continue
    if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
      git fetch --quiet --no-recurse-submodules --no-tags --no-write-fetch-head -- "$url" "$commit" 2>/dev/null || true
    fi
  done
}

# Fetches tag <tag> of upstream <url> into <key-prefix>tags/<tag>, if
# upstream has it. Git doesn't move a fetched tag that moved upstream, and
# neither does this: it keeps the commit the tag named, and prints
# "<old> <new>" then.
fetch_tag() {
  local url="$1" ref="$2tags/$3" old new
  old="$(git rev-parse --verify --quiet "$ref" || true)"
  git -c core.logAllRefUpdates=always fetch --quiet --no-recurse-submodules --no-tags --no-write-fetch-head -- "$url" "+refs/tags/$3:$ref" 2>/dev/null || return 0
  new="$(git rev-parse --verify --quiet "$ref")"
  if [[ -n "$old" && "$new" != "$old" ]]; then
    git update-ref "$ref" "$old"
    printf '%s %s\n' "$old" "$new"
  fi
}

# Fetches upstream <url>, with key <key>, that the splices of <entry>...
# share, each "<path>:<name>" of the upstream, and reports for each
# whether the branch it syncs with moved, while the monorepo is on branch
# $1. Writes what to print for entry number <i> of the whole fetch to
# $2/<i>.out and $2/<i>.err, and creates $2/<i>.failed if it failed; $3
# holds those numbers, space-separated.
fetch_shared_upstream() {
  local branch="$1" out_dir="$2" indexes=() key="$4" url="$5" i=0 entry path from synced=() labels=() failed_labels=() upstream_branches=() target_refs=() old_shas=() new_sha tags=() tag_of=() paths=() pin moved
  read -r -a indexes <<<"$3"
  shift 5
  for entry in "$@"; do
    path="${entry%%:*}"
    paths[i]="$path"
    from=""
    has_several_upstreams "$path" && from=" from ${entry#*:}"
    labels[i]="$path fetched$from"
    failed_labels[i]="$path fetch$from failed"
    # Empty if the upstreams of the splice above disagree on it, and none
    # is its default: the commands that need it refuse then.
    upstream_branches[i]="$(upstream_branch_for "$path" "$branch" "${entry#*:}" 2>/dev/null)" || true
    tag_of[i]=""
    # Only a default-pin fetches a tag or a commit. Every branch fetches
    # it: a feature branch compares with it when upstream has no branch
    # like it (compare_with_default_branch).
    pin="$(upstream_config "$path" "${entry#*:}" default-pin)"
    if is_commit_id "$pin"; then
      synced+=("$pin")
    else
      tag_of[i]="$pin"
    fi
    [[ -z "${tag_of[i]}" || " ${tags[*]} " == *" ${tag_of[i]} "* ]] || tags+=("${tag_of[i]}")
    # A splice pinned on this branch has no branch that could move.
    target_refs[i]=""
    if [[ -z "$pin" ]] || branch_arg_applies "$path" ||
      { [[ "${entry#*:}" == "${SPLICE_UPSTREAM_NAMES[$path]:-}" ]] && named_branch "$path" "$branch" >/dev/null; } || [[ "$branch" != "$(monorepo_default_branch)" ]]; then
      target_refs[i]="refs/splices/$key/heads/${upstream_branches[i]}"
    fi
    old_shas[i]="$(git rev-parse --verify --quiet "${target_refs[i]}" || true)"
    synced+=("$(splice_config "$path" commit)")
    i=$((i + 1))
  done
  local error
  if ! error="$(fetch_upstream "$url" "refs/splices/$key/heads/" "${synced[@]}" 2>&1)"; then
    for i in "${!indexes[@]}"; do
      {
        [[ -z "$error" ]] || printf '%s\n' "$error"
        log_err "${failed_labels[i]}"
      } >"$out_dir/${indexes[i]}.err" 2>&1
      : >"$out_dir/${indexes[i]}.out"
      : >"$out_dir/${indexes[i]}.failed"
    done
    return 1
  fi
  local tag
  local -A moved_tags=()
  for tag in "${tags[@]}"; do
    moved_tags[$tag]="$(fetch_tag "$url" "refs/splices/$key/" "$tag")"
  done
  for i in "${!indexes[@]}"; do
    new_sha="$(git rev-parse --verify --quiet "${target_refs[i]}" || true)"
    if [[ -n "${old_shas[i]}" && -n "$new_sha" && "${old_shas[i]}" != "$new_sha" ]]; then
      log_ok "${labels[i]} (${upstream_branches[i]} moved ${old_shas[i]:0:7}..${new_sha:0:7})"
    else
      log_ok "${labels[i]}"
    fi >"$out_dir/${indexes[i]}.out"
    {
      # What git printed on success, e.g. an SSH warning, shown once.
      if ((i == 0)) && [[ -n "$error" ]]; then
        printf '%s\n' "$error"
      fi
      moved="${tag_of[i]:+${moved_tags[${tag_of[i]}]}}"
      if [[ -n "$moved" ]]; then
        new_sha="${moved#* }"
        log_warn "${paths[i]}: the tag '${tag_of[i]}' moved upstream, from ${moved:0:7} to ${new_sha:0:7} -- kept ${moved:0:7}; to take the new one: git update-ref refs/splices/$key/tags/${tag_of[i]} $new_sha"
      fi
    } >"$out_dir/${indexes[i]}.err" 2>&1
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

# Fetches the upstreams of every given (distinct) entry in parallel, each
# "<path>:<name>" of an upstream of a splice, and each upstream once:
# splices with the same URL share their fetched refs, and two fetches into
# the same refs would fail on each other's locks. $1 is the monorepo's
# current branch, to report when a splice's counterpart moved. Sets
# FETCH_FAILURES to the paths whose fetch failed, and
# FETCH_OUTPUT/FETCH_STDERR to what to print for each entry, in their
# order.
fetch_all_parallel() {
  local branch="$1"
  shift
  FETCH_FAILURES=()
  FETCH_OUTPUT=()
  FETCH_STDERR=()

  local entries=("$@") i key keys=() members=() path
  local -A indexes_of_key=() url_of_key=()
  # Before the fetches start in parallel, which would race to record keys.
  for i in "${!entries[@]}"; do
    path="${entries[i]%%:*}"
    require_splice_upstream_list "$path"
    create_upstream_key "${UPSTREAM_URLS[${entries[i]}]}"
    key="$UPSTREAM_KEY"
    [[ -n "${indexes_of_key[$key]+set}" ]] || keys+=("$key")
    indexes_of_key[$key]+="$i "
    url_of_key[$key]="${UPSTREAM_URLS[${entries[i]}]}"
  done
  # Splices whose upstream in use just got its key.
  for path in "${!SPLICE_URLS[@]}"; do
    [[ -z "${SPLICE_URLS[$path]}" || -n "${SPLICE_KEYS[$path]}" ]] || {
      upstream_key "${SPLICE_URLS[$path]}"
      SPLICE_KEYS[$path]="$UPSTREAM_KEY"
    }
  done

  local tmp_dir pids=()
  tmp_dir="$(mktemp -d)"
  for key in "${keys[@]}"; do
    members=()
    for i in ${indexes_of_key[$key]}; do
      members+=("${entries[i]}")
    done
    fetch_shared_upstream "$branch" "$tmp_dir" "${indexes_of_key[$key]}" "$key" "${url_of_key[$key]}" "${members[@]}" &
    pids+=("$!")
  done
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" || true
  done

  for i in "${!entries[@]}"; do
    FETCH_OUTPUT+=("$(cat "$tmp_dir/$i.out")")
    FETCH_STDERR+=("$(cat "$tmp_dir/$i.err")")
    path="${entries[i]%%:*}"
    [[ ! -e "$tmp_dir/$i.failed" ]] || fetch_failed_for_path "$path" || FETCH_FAILURES+=("$path")
  done
  rm -rf "$tmp_dir"
}

# Prints an entry for fetch_all_parallel, "<path>:<name>", for each
# upstream of each splice <path>...
every_upstream_entry() {
  local path name names=()
  for path in "$@"; do
    require_splice_upstream_list "$path"
    read -r -a names <<<"${SPLICE_UPSTREAM_LISTS[$path]}"
    for name in "${names[@]}"; do
      printf '%s:%s\n' "$path" "$name"
    done
  done
}

# Prints an entry for fetch_all_parallel for the upstream each splice
# <path>... uses (use_upstreams).
used_upstream_entry() {
  local path
  for path in "$@"; do
    printf '%s:%s\n' "$path" "${SPLICE_UPSTREAM_NAMES[$path]}"
  done
}

cmd_fetch() {
  parse_args usage_fetch "--upstream --branch --track --no-track" "$@"
  require_branch_for_track
  open_repository
  select_paths overview fetch
  local branch i path entries=() failures=()
  branch="$(current_branch)"

  # Tracking is per upstream in use, so only that one is fetched.
  if [[ -n "$UPSTREAM_ARG" ]] || has_flag --track || has_flag --no-track; then
    use_upstreams "$UPSTREAM_ARG" "${SELECTED_PATHS[@]}"
    mapfile -t entries < <(used_upstream_entry "${SELECTED_PATHS[@]}")
  else
    mapfile -t entries < <(every_upstream_entry "${SELECTED_PATHS[@]}")
  fi
  fetch_all_parallel "$branch" "${entries[@]}"
  for i in "${!entries[@]}"; do
    print_fetch_output "$i"
  done
  failures=("${FETCH_FAILURES[@]}")

  for path in "${SELECTED_PATHS[@]}"; do
    fetch_failed_for_path "$path" && continue
    if has_flag --track; then
      if ! git rev-parse --verify --quiet "refs/splices/${SPLICE_KEYS[$path]}/heads/$BRANCH_ARG" >/dev/null; then
        log_err "$path: upstream has no '$BRANCH_ARG' branch to track"
        failures+=("$path")
      else
        track_branch "$path" "$branch" "$BRANCH_ARG" || failures+=("$path")
      fi
    elif has_flag --no-track; then
      untrack_branch "$path" "$branch" || failures+=("$path")
    fi
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
