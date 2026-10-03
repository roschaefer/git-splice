# Paging for diff and log, the way Git pages its own commands. Assumes
# lib/common.sh is already sourced.

# Prints the pager for this command. pager.splice takes precedence over an
# ordinary GIT_PAGER value, just as pager.log does for `git log`; the special
# GIT_PAGER=cat exported by `git --no-pager` still disables paging globally.
splice_pager() {
  local pager pager_config pager_bool
  if [[ "${GIT_PAGER:-}" == cat ]]; then
    pager=cat
  elif pager_config="$(git config --get pager.splice 2>/dev/null)"; then
    if pager_bool="$(git config --type=bool --get pager.splice 2>/dev/null)"; then
      [[ "$pager_bool" == true ]] && pager="$(git var GIT_PAGER)" || pager=cat
    else
      pager="$pager_config"
    fi
  else
    pager="$(git var GIT_PAGER)"
  fi
  [[ -n "$pager" ]] || pager=cat
  printf '%s\n' "$pager"
}

# Pipes one producer through a pager command and preserves meaningful exit
# statuses. A producer SIGPIPE is normal when a successful pager quits early;
# a pager startup/runtime failure must still reach the caller.
pipe_to_pager() {
  local producer="$1" pager="$2"
  shift 2
  : "${LESS:=FRX}" "${LV:=-c}"
  export LESS LV

  local statuses producer_status pager_status
  if {
    # Pager values are shell commands by Git's documented configuration
    # contract, so evaluate them the same way Git's own shell commands do.
    # shellcheck disable=SC2294
    GIT_PAGER_IN_USE=true "$producer" "$@" | eval "$pager"
    statuses=("${PIPESTATUS[@]}")
    producer_status="${statuses[0]}"
    pager_status="${statuses[1]}"
    ((producer_status == 0 || producer_status == 141)) && ((pager_status == 0))
  }; then
    return 0
  fi
  # A failed pager wins: once it's gone, the producer's write fails too, with
  # 141 if SIGPIPE kills it or 1 if SIGPIPE is ignored and it sees EPIPE.
  # Either way that's a consequence, not the cause.
  ((pager_status != 0)) && return "$pager_status"
  return "$producer_status"
}

# Runs a producer through Git's pager when stdout is a terminal. Redirected
# and piped output remains unpaged, as it does for Git's built-in commands.
page_git_output() {
  local producer="$1"
  shift

  if [[ ! -t 1 ]]; then
    "$producer" "$@"
    return
  fi

  local pager
  pager="$(splice_pager)"
  pipe_to_pager "$producer" "$pager" "$@"
}
