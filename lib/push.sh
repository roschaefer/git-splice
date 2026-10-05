# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_push() {
  cat <<'EOF'
usage: git splice push [--base <branch>] [--force] (<path>... | --all)

Publishes each splice's local changes: rebuilds the commits that changed
it since the last sync, without its .splice file, and pushes them to its
upstream URL. Nothing is written to the monorepo.

If the upstream has no branch named like the current one, push creates it
-- but only for a splice that changed on this branch compared with the
monorepo's base branch (the branch this one was cut from), so working on a
feature branch doesn't spawn empty branches upstream. The base branch is
--base, else the monorepo's default branch (origin/HEAD, else
init.defaultBranch); if none resolves, push refuses and asks for --base.

--force overwrites the upstream branch with the monorepo's side: when the
two share no history, or to discard commits only upstream has.

Only committed changes are pushed; push warns about uncommitted ones in a
splice's folder.
EOF
}

# Pushes one splice. $3 is an explicit --base branch, if any; $4 is
# "force" for --force.
push_one() {
  local path="$1" branch="$2" base="${3:-}" force="${4:-}" rc=0

  has_uncommitted_changes "$path" || rc=$?
  case "$rc" in
    0) log_warn "$path: uncommitted changes aren't pushed -- commit them first" ;;
    2) log_warn "$path: could not check for uncommitted changes (git status failed) -- only committed ones are pushed" ;;
  esac
  classify_splice "$path" "$branch"
  local upstream_branch="$SPLICE_UPSTREAM_BRANCH"
  case "$SPLICE_STATE" in
    never-fetched)
      log_warn "$path: not fetched -- run 'git splice fetch $path' first"
      return 1
      ;;
    up-to-date)
      log_ok "$path: nothing to push"
      return 0
      ;;
    pull)
      if [[ -z "$force" ]]; then
        log_ok "$path: nothing to push (upstream is ahead -- 'git splice pull $path' brings it in)"
        return 0
      fi
      ;;
    diverged)
      if [[ -z "$force" ]]; then
        log_err "$path: upstream has commits this branch lacks -- run 'git splice pull $path' first"
        return 1
      fi
      ;;
    unrelated-history)
      if [[ -z "$force" ]]; then
        print_unrelated_history_guidance "$path"
        return 1
      fi
      [[ -n "$SPLICE_REBUILT" ]] || SPLICE_REBUILT="$(REBUILD_WITHOUT_SYNCED=1 rebuild_splice "$path" HEAD)"
      ;;
    missing-branch)
      changes_vs_base "$path" "$base"
      case "$SPLICE_CHANGES_VS_BASE" in
        no)
          log_ok "$path: nothing to push (upstream has no '$upstream_branch' branch; unchanged since '$SPLICE_BASE_BRANCH')"
          return 0
          ;;
        unresolved)
          if [[ -n "$base" ]]; then
            log_err "$path: base branch '$base' not found, or it shares no history with '$branch'"
          else
            log_err "$path: upstream has no '$upstream_branch' branch and the monorepo's base branch can't be determined -- re-run with --base <branch>"
          fi
          return 1
          ;;
        error)
          log_err "$path: could not compare with base branch '$SPLICE_BASE_BRANCH' -- not creating '$upstream_branch'"
          return 1
          ;;
        yes)
          log_warn "$path: upstream has no '$upstream_branch' branch yet -- this push creates it (changed since '$SPLICE_BASE_BRANCH')"
          ;;
        self)
          log_warn "$path: upstream has no '$upstream_branch' branch yet -- this push creates it"
          ;;
      esac
      SPLICE_REBUILT="$(rebuild_splice "$path" HEAD)"
      ;;
    push) ;;
  esac

  if [[ -z "$SPLICE_REBUILT" ]]; then
    log_ok "$path: nothing to push (no content)"
    return 0
  fi

  local url force_flag=()
  url="$(splice_config "$path" url)"
  [[ -n "$force" ]] && force_flag=(--force)
  if ! git push "${force_flag[@]}" --quiet -- "$url" "$SPLICE_REBUILT:refs/heads/$upstream_branch"; then
    log_err "$path: push failed"
    return 1
  fi
  # Pushing to a URL updates no ref here, so record what upstream has now.
  if ! git update-ref "$(splice_ref "$path" "$upstream_branch")" "$SPLICE_REBUILT"; then
    log_err "$path: pushed, but couldn't record it in $(splice_ref "$path" "$upstream_branch") -- run 'git splice fetch $path'"
    return 1
  fi
  log_ok "$path: pushed ${SPLICE_REBUILT:0:7} to $upstream_branch"
}

cmd_push() {
  parse_args usage_push "--force" "$@"
  local base="$BASE_ARG" force=""
  has_flag --force && force=force
  cd_to_repo_root
  require_head_commit
  discover_splices
  select_paths explicit push
  local branch path failures=()
  branch="$(current_branch)"

  # Pushes to the same host share one SSH connection.
  local ssh_control_dir
  ssh_control_dir="$(mktemp -d)"
  # Expanded now: the local is gone by the time the shell exits.
  # shellcheck disable=SC2064
  trap "rm -rf -- $(printf '%q' "$ssh_control_dir")" EXIT
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=$ssh_control_dir/%r@%h:%p"

  for path in "${SELECTED_PATHS[@]}"; do
    push_one "$path" "$branch" "$base" "$force" || failures+=("$path")
  done
  rm -rf "$ssh_control_dir"

  if [[ ${#failures[@]} -gt 0 ]]; then
    log_err "Failed: ${failures[*]}"
    exit 1
  fi
}
