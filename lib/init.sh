# Assumes lib/common.sh (and, via fetch_one, lib/fetch.sh) is already sourced.

usage_init() {
  cat <<'EOF'
usage: git subtrees init [--base <branch>] <path> <url>

One-time bootstrap adding/adopting worktree directory <path> from <url> as a
subtree, registering a remote named <path> if one doesn't already exist.
Requires exactly one <path> <url> pair -- unlike every other command, init
is not batchable across all discovered subtrees, since it's the one
operation that needs human judgment.

If the remote has no branch named like the current one (e.g. on a fresh
feature branch), init adds the remote's branch named like the monorepo's
base branch instead, so your first push creates the missing branch on top
of it. The base branch is taken from --base, else from origin/HEAD, else
from init.defaultBranch. If none resolves, or the remote lacks that branch
too (e.g. it's empty), init only registers the remote.
EOF
}

# Fetches <branch> of remote <path> for init. Returns 0 on success and 2 if
# the remote has no such branch; dies on any other fetch failure.
init_fetch() {
  local path="$1" branch="$2"
  # Deferred: `git fetch` and fetch_one's own log_err already write a fatal
  # diagnostic to stderr the moment the branch fetch fails, before we get a
  # chance to check whether that's actually the missing-branch case.
  # Capture it instead of letting it print immediately, and only replay it
  # once remote_missing_branch has ruled that out -- otherwise a successful
  # (exit 0) no-op still leaves a misleading "fetch failed" on stderr.
  local fetch_err fetch_status=0
  {
    fetch_err="$(fetch_one "$path" "$branch" 2>&1 1>&3)" || fetch_status=$?
  } 3>&1
  ((fetch_status == 0)) && return 0
  if remote_missing_branch "$path" "$branch"; then
    # A tracking ref left from an earlier fetch would make status and push
    # compare against a branch the remote no longer has.
    git update-ref -d "$(target_ref_for "$path" "$branch")" 2>/dev/null || true
    return 2
  fi
  printf '%s\n' "$fetch_err" >&2
  die "$path: fetch failed"
}

# Prints the name the monorepo's base branch has on a subtree remote: "main"
# for refs/heads/main as well as for any remote-tracking ref of it, e.g.
# origin/main or upstream/main. A symbolic ref such as origin/HEAD is
# followed first. Fails if no base branch resolves (see resolve_base_ref).
base_branch_name() {
  local ref target name remote tracking=""
  ref="$(resolve_base_ref "$1")" || return 1
  target="$(git symbolic-ref --quiet "$ref" 2>/dev/null)" && ref="$target"
  case "$ref" in
    refs/heads/*)
      name="${ref#refs/heads/}"
      ;;
    refs/remotes/*)
      name="${ref#refs/remotes/}"
      # Remote names may contain '/', so strip the longest one that matches.
      while IFS= read -r remote; do
        if [[ "$name" == "$remote"/* && ${#remote} -gt ${#tracking} ]]; then
          tracking="$remote"
        fi
      done < <(git remote)
      [[ -n "$tracking" ]] && name="${name#"$tracking"/}"
      ;;
    *)
      name="${ref#refs/*/}"
      ;;
  esac
  printf '%s\n' "$name"
}

# Records the remote commit at <target-ref> as the last sync of <path>,
# whose content already equals it, without touching any file: the same two
# commits `git subtree add --squash` would create -- a squash commit with the
# remote's tree and git-subtree-dir/git-subtree-split trailers, merged into
# HEAD -- except that the merge keeps HEAD's tree. git-subtree itself
# refuses both `add` (the folder exists) and `merge` (it was never added).
# The merge also carries git-subtree-mainline/-split trailers, as a
# `split --rejoin` merge does: they tell split that HEAD's folder already
# equals the remote commit, so a push never sends the folder's history
# from before the adoption.
adopt_subtree() {
  local path="$1" target_ref="$2" split squash head merge
  split="$(git rev-parse "$target_ref^{commit}")"
  squash="$(git commit-tree "$target_ref^{tree}" \
    -m "Squashed '$path/' content from commit ${split:0:7}" \
    -m "git-subtree-dir: $path"$'\n'"git-subtree-split: $split")"
  head="$(git rev-parse HEAD)"
  merge="$(git commit-tree "HEAD^{tree}" -p "$head" -p "$squash" \
    -m "Merge commit '$squash' as '$path'" \
    -m "git-subtree-dir: $path"$'\n'"git-subtree-mainline: $head"$'\n'"git-subtree-split: $split")"
  git update-ref -m "git subtrees init: adopt $path" HEAD "$merge" "$head"
}

cmd_init() {
  parse_base_args usage_init "$@"
  local base="$BASE_ARG"
  local path="${PATH_ARGS[0]:-}" url="${PATH_ARGS[1]:-}"
  if [[ -z "$path" || -z "$url" || ${#PATH_ARGS[@]} -gt 2 ]]; then
    usage_init >&2
    exit 1
  fi
  usable_with_git_subtree "$path" || die "$path: git-subtree cannot use a name starting with '-' -- rename it and re-run"

  cd_to_repo_root

  local branch
  branch="$(current_branch)"
  usable_with_git_subtree "$branch" || die "$branch: git-subtree cannot use a branch name starting with '-' -- rename it and re-run"

  discover_subtrees
  local nested
  if nested="$(overlapping_remote "$path")"; then
    die "nested subtrees are not supported: $(overlap_pair "$path" "$nested") overlap"
  fi

  local existing_url
  existing_url="$(git remote get-url -- "$path" 2>/dev/null || true)"

  if [[ -n "$existing_url" && "$existing_url" != "$url" ]]; then
    die "$path: remote already registered, pointing at '$existing_url' (not '$url')"
  fi

  if [[ -z "$existing_url" ]]; then
    log_step "$path: registering remote -> $url"
    git remote add -- "$path" "$url"
  fi

  log_step "$path: fetching"
  local rc=0
  init_fetch "$path" "$branch" || rc=$?
  if ((rc == 2)); then
    local base_branch
    if ! base_branch="$(base_branch_name "$base")"; then
      # An explicit --base that doesn't resolve is a mistake (e.g. a typo),
      # not a reason to skip adding quietly -- the same as for push.
      [[ -n "$base" ]] && die "$path: base branch '$base' not found, or it shares no history with '$branch'"
      log_ok "$path: remote has no '$branch' branch yet -- nothing to add (pass --base <branch> to add another branch)"
      return 0
    fi
    usable_with_git_subtree "$base_branch" || die "$base_branch: git-subtree cannot use a branch name starting with '-' -- pass another --base"
    if [[ "$base_branch" != "$branch" ]]; then
      rc=0
      init_fetch "$path" "$base_branch" || rc=$?
    fi
    if ((rc != 0)); then
      log_ok "$path: remote has no '$branch' branch yet -- nothing to add"
      return 0
    fi
    log_step "$path: remote has no '$branch' branch yet -- using its '$base_branch' branch; your first push creates '$branch'"
    branch="$base_branch"
  fi

  classify_subtree "$path" "$branch"

  if [[ ! -d "$path" ]]; then
    log_step "$path: adding subtree from $url"
    git subtree add --prefix="$path" "$path" "$branch" --squash
    log_ok "$path: added"
    return 0
  fi

  case "$SUBTREE_STATE" in
    up-to-date | push | pull | diverged)
      # Equal content alone reads as up-to-date, even for a folder copied in
      # by hand. Without a sync point, a later push would send a history
      # that shares nothing with the remote's, so record one first.
      if [[ -z "$(find_sync_commit "$path")" ]]; then
        adopt_subtree "$path" "$SUBTREE_TARGET_REF"
        log_ok "$path: content matches '$branch' on the remote -- recorded it as the last sync"
      else
        log_ok "$path: already initialized"
      fi
      ;;
    unrelated-history)
      log_err "$path: directory exists with content unrelated to $url"
      local retry="git subtrees init"
      [[ -n "$base" ]] && retry+=" --base $(shell_quote "$base")"
      log_err "move it aside and re-run: mv $path $path.bak && $retry $path $url"
      exit 1
      ;;
    *)
      die "$path: remote has no branches to add"
      ;;
  esac
}
