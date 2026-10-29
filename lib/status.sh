# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_status() {
  cat <<'EOF'
NAME
    git-splice-status - Show each splice's sync state

SYNOPSIS
    git splice status [--upstream <name>] [path...]

DESCRIPTION
    Shows the sync state of every splice. Purely local -- run 'git splice
    fetch' first for up-to-date results. Defaults to every splice when no
    paths are given.

    Every splice gets a line: the splices that need something come first,
    most urgent first -- "!!" and "??" mark problems -- and those that are up
    to date or unchanged come last.

    Like 'git status' against its upstream branch, it counts commits: "ahead"
    is how many 'git splice push' would publish, "behind" how many 'git
    splice pull' would bring in. 'git splice diff --stat' shows the files.

    For a splice whose upstream has no branch named like the current one,
    the comparison is with upstream's default branch, as for a PR: "new"
    counts the commits the push that creates the branch would publish, and
    how many the default branch has that this one lacks. "unchanged" means
    a PR from the branch would show no changes: the default branch has
    every commit, or the others change no files, e.g. a change and its
    revert.

    A splice that tracks an upstream branch on the current branch, by
    'git splice fetch --track' (or push, pull, merge), says so: "tracked on
    <branch>, local". It's in this repository's config only, so another
    clone of the monorepo shows the usual branch there.

    Like every command, status reads splices from the last commit. It warns
    about uncommitted changes in a splice's folder, which push leaves out.

    --upstream names one of the upstreams a splice's .splice names; without
    it, the splice's default upstream. A splice without the named upstream
    stops the command before it starts. A splice with several upstreams shows its
    upstream branch as <name>/<branch>.
EOF
}

# A status row per splice, collected so they can be sorted and aligned:
# STATUS_RANKS orders them, most urgent first (see status_rank), and the
# others hold the columns.
STATUS_RANKS=()
STATUS_LABELS=()
STATUS_PATHS=()
STATUS_HINTS=()

# Ranks, most urgent first. Splices ranked QUIET_RANK or higher need
# nothing from the user; they come last, after a blank line. Rank 6 is a
# quiet splice with uncommitted changes (see add_status_row).
QUIET_RANK=7
status_rank() {
  case "$1" in
    problem) echo 0 ;;
    warning) echo 1 ;;
    diverged) echo 2 ;;
    pull) echo 3 ;;
    push) echo 4 ;;
    new) echo 5 ;;
    up-to-date) echo 7 ;;
    unchanged) echo 8 ;;
  esac
}

# Sets STATUS_LABEL, STATUS_KIND and STATUS_HINT for a splice whose
# upstream has no branch like the current one: whether the push that
# creates it would publish anything (see compare_with_default_branch).
classify_missing_branch() {
  local path="$1"
  if ! compare_with_default_branch "$path" 2>/dev/null; then
    STATUS_KIND=warning STATUS_LABEL="?? no upstream branch"
    if [[ -z "$SPLICE_DEFAULT_BRANCH" ]]; then
      STATUS_HINT="upstream's default branch unknown"
    else
      STATUS_HINT="could not compare with upstream's '$SPLICE_DEFAULT_BRANCH'"
    fi
  elif [[ -n "$SPLICE_NO_CHANGES" ]]; then
    STATUS_KIND=unchanged STATUS_LABEL="unchanged, no upstream branch"
  else
    STATUS_KIND=new STATUS_LABEL="new, ahead $SPLICE_NEW_COMMITS" STATUS_HINT="push creates the branch"
    ((SPLICE_BEHIND_COMMITS == 0)) || STATUS_LABEL+=", behind $SPLICE_BEHIND_COMMITS"
  fi
}

# Classifies one splice and adds its row.
add_status_row() {
  local path="$1" branch="$2" counts ahead behind rc=0 column="$1" option
  classify_splice "$path" "$branch" || return 1
  STATUS_KIND="" STATUS_LABEL="" STATUS_HINT=""
  [[ "$SPLICE_UPSTREAM_LABEL" == "$branch" ]] || column="$path -> $SPLICE_UPSTREAM_LABEL"
  option="$(upstream_option "$path")"

  case "$SPLICE_STATE" in
    never-fetched)
      STATUS_KIND=warning STATUS_LABEL="?? never fetched" STATUS_HINT="run 'git splice fetch $option$path'"
      ;;
    missing-branch)
      classify_missing_branch "$path"
      ;;
    missing-synced)
      STATUS_KIND=warning STATUS_LABEL="?? synced commit ${SPLICE_SYNCED:0:7} isn't here" STATUS_HINT="run 'git splice fetch $option$path', or check that upstream has it"
      ;;
    missing-pin)
      STATUS_KIND=problem STATUS_LABEL="!! $(target_description) isn't here" STATUS_HINT="run 'git splice fetch $option$path', or check that upstream has it"
      ;;
    up-to-date)
      STATUS_KIND=up-to-date STATUS_LABEL="up to date"
      ;;
    push | pull | diverged)
      STATUS_KIND="$SPLICE_STATE"
      # Ahead: commits of the rebuild R the upstream branch T lacks, which
      # push publishes. Behind: commits of T that R lacks, which pull
      # brings in. If they can't be counted, the state alone still holds.
      if counts="$(git rev-list --left-right --count "$SPLICE_REBUILT...$SPLICE_TARGET_REF" 2>/dev/null)"; then
        read -r ahead behind <<<"$counts"
        case "$SPLICE_STATE" in
          push) STATUS_LABEL="ahead $ahead" ;;
          pull) STATUS_LABEL="behind $behind" ;;
          diverged) STATUS_LABEL="ahead $ahead, behind $behind" ;;
        esac
      else
        case "$SPLICE_STATE" in
          push) STATUS_LABEL="ahead" ;;
          pull) STATUS_LABEL="behind" ;;
          diverged) STATUS_LABEL="diverged" ;;
        esac
      fi
      ;;
    unrelated-history)
      STATUS_KIND=problem STATUS_LABEL="!! unrelated history" STATUS_HINT="see 'git splice merge $option$path' for options"
      ;;
  esac

  if [[ -n "$(tracked_branch "$path" "$branch")" ]]; then
    STATUS_HINT="${STATUS_HINT:+$STATUS_HINT; }tracked on $branch, local"
  fi

  local rank uncommitted=""
  rank="$(status_rank "$STATUS_KIND")"
  has_uncommitted_changes "$path" || rc=$?
  case "$rc" in
    0) uncommitted="uncommitted changes" ;;
    2) uncommitted="could not check for uncommitted changes (git status failed)" ;;
  esac
  if [[ -n "$uncommitted" ]]; then
    STATUS_HINT="${STATUS_HINT:+$STATUS_HINT; }$uncommitted"
    # Uncommitted changes need the user even where the splice doesn't.
    ((rank < QUIET_RANK)) || rank=$((QUIET_RANK - 1))
  fi
  STATUS_RANKS+=("$rank")
  STATUS_LABELS+=("$STATUS_LABEL")
  STATUS_PATHS+=("$column")
  STATUS_HINTS+=("$STATUS_HINT")
}

# Prints the collected rows, most urgent first, in aligned columns: the
# state, the path, and what to do. The quiet rows come last, after a blank
# line, and dimmed where Git would color `git status`.
print_status_rows() {
  local label_width=0 path_width=0 i rank shown_rank=-1 line dim="" reset="" tty=false
  # Not inside the command substitution below: its stdout is a pipe.
  [[ ! -t 1 ]] || tty=true
  if [[ "$(git config --get-colorbool color.status "$tty")" == true ]]; then
    dim=$'\e[2m' reset=$'\e[m'
  fi
  for i in "${!STATUS_RANKS[@]}"; do
    ((${#STATUS_LABELS[i]} <= label_width)) || label_width=${#STATUS_LABELS[i]}
    [[ -z "${STATUS_HINTS[i]}" ]] || ((${#STATUS_PATHS[i]} <= path_width)) || path_width=${#STATUS_PATHS[i]}
  done
  for rank in 0 1 2 3 4 5 6 7 8; do
    for i in "${!STATUS_RANKS[@]}"; do
      ((STATUS_RANKS[i] == rank)) || continue
      if ((shown_rank >= 0 && shown_rank < QUIET_RANK && rank >= QUIET_RANK)); then
        echo
      fi
      shown_rank=$rank
      if [[ -n "${STATUS_HINTS[i]}" ]]; then
        printf -v line '  %-*s  %-*s  %s' "$label_width" "${STATUS_LABELS[i]}" "$path_width" "${STATUS_PATHS[i]}" "${STATUS_HINTS[i]}"
      else
        printf -v line '  %-*s  %s' "$label_width" "${STATUS_LABELS[i]}" "${STATUS_PATHS[i]}"
      fi
      if ((rank >= QUIET_RANK)); then
        printf '%s%s%s\n' "$dim" "$line" "$reset"
      else
        printf '%s\n' "$line"
      fi
    done
  done
}

cmd_status() {
  parse_args usage_status "--upstream" "$@"
  local branch path
  open_repository
  if [[ ${#ALL_PATHS[@]} -eq 0 && ${#PATH_ARGS[@]} -eq 0 ]]; then
    log_ok "no splices -- 'git splice clone <url> <path>' adds one"
    return 0
  fi
  select_splices overview status
  branch="$MONOREPO_BRANCH"
  STATUS_RANKS=() STATUS_LABELS=() STATUS_PATHS=() STATUS_HINTS=()
  load_uncommitted_changes "${SELECTED_PATHS[@]}"
  for path in "${SELECTED_PATHS[@]}"; do
    add_status_row "$path" "$branch"
  done
  printf 'On branch %s\n\n' "$branch"
  print_status_rows
}
