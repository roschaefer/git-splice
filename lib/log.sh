# Assumes lib/common.sh, lib/rebuild.sh, lib/state.sh and lib/pager.sh are
# already sourced.

usage_log() {
  cat <<'EOF'
usage: git splice log [--upstream <name>] [--graph] [path...]

Shows the commits between each splice and the upstream branch it syncs
with, in both directions:

  <  a commit 'git splice push' would publish
  >  a commit 'git splice pull' would bring in
  =  the same change on both sides, e.g. cherry-picked upstream

--graph draws both sides as a graph, like 'git log --graph', with the
marks as its nodes, and the commit both sides build on as 'o'. The
rebuild of the splice's commits is labeled (R), the upstream branch (T).

If the upstream has no branch named like the current one, the other side
is upstream's default branch, as for a PR from the branch push would
create. If it lacks that one too, every commit is one push would
publish.

Each line shows the author, who is published along with the commit. Purely
local -- run 'git splice fetch' first. Defaults to every splice when no
paths are given.

--upstream names one of the upstreams a splice's .splice names; without
it, the splice's default upstream. A splice without the named upstream
stops the command before it starts.
EOF
}

LOG_FORMAT='%m %h %s  (%an <%ae>)'
# For --graph: the graph's nodes are the marks, and the full hash between
# \x01 and \x02 tells label_tips which commit a line is.
GRAPH_FORMAT='%x01%H%x02%h %s  (%an <%ae>)'

# Runs git log with [args...], and in --graph mode labels the abbreviated
# hashes of the rebuild <r> and the upstream branch <t> (R) and (T).
splice_git_log() {
  local r="$1" t="$2"
  shift 2
  if [[ -z "$LOG_GRAPH" ]]; then
    git log --format="$LOG_FORMAT" "$@"
    return
  fi
  git log --graph --boundary --format="$GRAPH_FORMAT" "$@" | label_tips "$r" "$t"
  local statuses=("${PIPESTATUS[@]}")
  ((statuses[0] == 0)) || return "${statuses[0]}"
  return "${statuses[1]}"
}

label_tips() {
  awk -v r="$1" -v t="$2" '{
    s = index($0, "\001")
    e = index($0, "\002")
    if (s && e > s) {
      full = substr($0, s + 1, e - s - 1)
      rest = substr($0, e + 1)
      sp = index(rest, " ")
      label = (full == r) ? " (R)" : (full == t) ? " (T)" : ""
      $0 = substr($0, 1, s - 1) substr(rest, 1, sp - 1) label substr(rest, sp)
    }
    print
  }'
}

log_one() {
  local path="$1" branch="$2"

  classify_splice "$path" "$branch" || return 1
  case "$SPLICE_STATE" in
    never-fetched)
      log_warn "$path: not fetched -- run 'git splice fetch $(upstream_option "$path")$path' first"
      return 1
      ;;
    missing-branch)
      if ! compare_with_default_branch "$path"; then
        log_err "$path: upstream has no '$SPLICE_UPSTREAM_LABEL' branch, and its default branch${SPLICE_DEFAULT_BRANCH:+ '$SPLICE_DEFAULT_BRANCH'} can't be compared with"
        return 1
      fi
      [[ -n "$SPLICE_REBUILT" ]] || return 0
      if [[ -z "$SPLICE_DEFAULT_REF" ]]; then
        if [[ "$SPLICE_DEFAULT_BRANCH" == "$SPLICE_UPSTREAM_BRANCH" ]]; then
          log_step "$path (upstream has no '$SPLICE_UPSTREAM_LABEL' branch)"
        else
          log_step "$path (upstream has neither a '$SPLICE_UPSTREAM_LABEL' nor a '$SPLICE_DEFAULT_BRANCH' branch)"
        fi
        LOG_FORMAT="${LOG_FORMAT/\%m/<}" splice_git_log "$SPLICE_REBUILT" "" "$SPLICE_REBUILT"
        return
      fi
      # As a PR from the branch push creates would: against the default branch.
      log_step "$path (upstream has no '$SPLICE_UPSTREAM_LABEL' branch -- compared with '$SPLICE_DEFAULT_BRANCH')"
      splice_git_log "$SPLICE_REBUILT" "$(git rev-parse "$SPLICE_DEFAULT_REF^{commit}")" \
        --left-right --cherry-mark "$SPLICE_REBUILT...$SPLICE_DEFAULT_REF"
      return
      ;;
    missing-synced)
      log_warn "$path: $(missing_synced_message "$path")"
      return 1
      ;;
    missing-pin)
      log_err "$path: $(target_description) isn't here -- run 'git splice fetch $(upstream_option "$path")$path', or check that upstream has it"
      return 1
      ;;
    up-to-date)
      [[ -n "$SPLICE_REBUILT" ]] || return 0
      ;;
    unrelated-history)
      [[ -n "$SPLICE_REBUILT" ]] || {
        log_warn "$path: upstream and the splice share no history"
        return 1
      }
      ;;
  esac

  log_step "$path ($SPLICE_UPSTREAM_LABEL)"
  splice_git_log "$SPLICE_REBUILT" "$(git rev-parse "$SPLICE_TARGET_REF^{commit}")" \
    --left-right --cherry-mark "$SPLICE_REBUILT...$SPLICE_TARGET_REF"
}

cmd_log() {
  parse_args usage_log "--graph --upstream" "$@"
  LOG_GRAPH=""
  has_flag --graph && LOG_GRAPH=1
  open_repository
  select_splices overview log
  page_git_output run_each_splice log_one "$MONOREPO_BRANCH" "${SELECTED_PATHS[@]}"
}
