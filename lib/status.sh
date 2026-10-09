# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_status() {
  cat <<'EOF'
usage: git splice status [--upstream <name>] [--base <branch>] [path...]

Shows the sync state of every splice. Purely local -- run 'git splice
fetch' first for up-to-date results. Defaults to every splice when no
paths are given.

Every splice gets a line: the splices that need something come first,
most urgent first -- "!!" and "??" mark problems -- and those that are up
to date or unchanged come last.

Like 'git status' against a tracking branch, it counts commits: "ahead"
is how many 'git splice push' would publish, "behind" how many 'git
splice pull' would bring in. 'git splice diff --stat' shows the files.

For a splice whose upstream has no branch named like the current one, the
state is whether the splice changed on this branch compared with the
monorepo's base branch (--base, else the monorepo's default branch).

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
# upstream has no branch like the current one: what changed on this branch
# compared with the base branch.
classify_missing_branch() {
  local path="$1" base="$2" count
  changes_vs_base "$path" "$base"
  case "$SPLICE_CHANGES_VS_BASE" in
    no)
      STATUS_KIND=unchanged STATUS_LABEL="unchanged, no upstream branch"
      ;;
    yes)
      count="$(new_branch_count "$path")"
      STATUS_KIND=new STATUS_LABEL="new, $count" STATUS_HINT="push creates the branch"
      ;;
    self)
      count="$(new_branch_count "$path")"
      STATUS_KIND=warning STATUS_LABEL="?? new, $count" STATUS_HINT="push creates the branch"
      ;;
    error)
      STATUS_KIND=warning STATUS_LABEL="?? no upstream branch"
      STATUS_HINT="could not compare with base branch '$SPLICE_BASE_BRANCH'"
      ;;
    unresolved)
      STATUS_KIND=warning STATUS_LABEL="?? no upstream branch"
      if [[ -n "$base" ]]; then
        STATUS_HINT="base branch '$base' not found, or it shares no history"
      else
        STATUS_HINT="monorepo base branch unknown -- pass --base <branch>"
      fi
      ;;
  esac
}

# Prints "ahead <n>" for a splice whose upstream lacks the current
# branch: the commits the push that creates it would publish, i.e. those
# of the rebuild on no fetched upstream branch. Prints "changed" if
# there are none to count, e.g. right after cloning on a feature branch:
# the push would create the branch at a commit upstream already has, or
# if they can't be counted, e.g. because the synced commit was pruned.
new_branch_count() {
  local path="$1" rebuilt count
  rebuilt="$(rebuild_splice "$path" HEAD 2>/dev/null)"
  if [[ -z "$rebuilt" ]] || ! count="$(git rev-list --count "$rebuilt" --not --glob="$(splice_refs_prefix "$path")*")" || ((count == 0)); then
    printf 'changed'
    return
  fi
  printf 'ahead %s' "$count"
}

# Classifies one splice and adds its row.
add_status_row() {
  local path="$1" branch="$2" base="${3:-}" counts ahead behind rc=0 column="$1" option
  classify_splice "$path" "$branch"
  STATUS_KIND="" STATUS_LABEL="" STATUS_HINT=""
  [[ "$SPLICE_UPSTREAM_LABEL" == "$branch" ]] || column="$path -> $SPLICE_UPSTREAM_LABEL"
  option="$(upstream_option "$path")"

  case "$SPLICE_STATE" in
    never-fetched)
      STATUS_KIND=warning STATUS_LABEL="?? never fetched" STATUS_HINT="run 'git splice fetch $option$path'"
      ;;
    missing-branch)
      classify_missing_branch "$path" "$base"
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

# Prints the header: the branch every splice syncs with, unless its
# upstream names it differently, and the base branch that "unchanged" and
# "new" compare with.
print_status_header() {
  local branch="$1" base="$2" base_ref base_branch
  if base_ref="$(resolve_base_ref "$base")" && [[ "$base_ref" != "$(git symbolic-ref --quiet HEAD)" ]]; then
    base_branch="${base_ref#refs/heads/}"
    base_branch="${base_branch#refs/remotes/}"
    printf 'On branch %s (base: %s)\n\n' "$branch" "$base_branch"
  else
    printf 'On branch %s\n\n' "$branch"
  fi
}

cmd_status() {
  parse_args usage_status "--upstream" "$@"
  local base="$BASE_ARG" branch path
  cd_to_repo_root
  require_head_commit
  discover_splices
  if [[ ${#ALL_PATHS[@]} -eq 0 && ${#PATH_ARGS[@]} -eq 0 ]]; then
    log_ok "no splices -- 'git splice clone <url> <path>' adds one"
    return 0
  fi
  select_paths overview status
  use_upstreams "$UPSTREAM_ARG" "${SELECTED_PATHS[@]}"
  branch="$(current_branch)"
  STATUS_RANKS=() STATUS_LABELS=() STATUS_PATHS=() STATUS_HINTS=()
  for path in "${SELECTED_PATHS[@]}"; do
    add_status_row "$path" "$branch" "$base"
  done
  print_status_header "$branch" "$base"
  print_status_rows
}
