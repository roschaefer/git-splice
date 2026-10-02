# Shared discovery, state, classification and logging helpers.
# Sourced first by the entrypoint; every other lib/*.sh file assumes these
# are already in scope.

# Every splice path in the repository, from its committed .splice file.
declare -ga ALL_PATHS=()
# Results of parse_args.
declare -g BASE_ARG=""
declare -g ALL_ARG=""
declare -ga PATH_ARGS=()
declare -ga EXTRA_FLAGS=()

# Name of the state file inside every splice folder.
STATE_FILE=.splice

# Every splice path check and every tree lookup (HEAD:<path>) is only
# meaningful relative to the repository root.
cd_to_repo_root() {
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
  cd "$toplevel" || die "failed to cd to repo root: $toplevel"
}

log_ok() { printf 'ok   %s\n' "$*"; }
log_warn() { printf '??   %s\n' "$*" >&2; }
log_err() { printf '!!   %s\n' "$*" >&2; }
log_step() { printf '===  %s\n' "$*"; }
die() {
  log_err "$*"
  exit 1
}

# Prints the current local branch name; dies on detached HEAD, since every
# splice syncs with the upstream branch named like the current one.
current_branch() {
  local branch
  branch="$(git symbolic-ref --quiet --short HEAD)" ||
    die "not on a branch (detached HEAD) -- git splice requires a named branch"
  printf '%s\n' "$branch"
}

# Dies unless HEAD points at a commit: every command reads the splices'
# state from HEAD, and a pull or clone commits on top of it.
require_head_commit() {
  git rev-parse --quiet --verify "HEAD^{commit}" >/dev/null ||
    die "branch '$(current_branch)' has no commits yet -- create one and re-run: git commit --allow-empty -m 'initial commit'"
}

# Prints $1 without a leading "./" and trailing slashes, as splice paths
# are compared and stored.
normalize_path() {
  local path="$1"
  path="${path#./}"
  while [[ "$path" == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

# Parses the arguments of a command that takes `[--all] [--base <branch>]
# [<flag>...] [path...]`. Sets ALL_ARG, BASE_ARG, PATH_ARGS, and
# EXTRA_FLAGS for every flag named in $2 (space-separated, e.g. "--merge").
# $1 names the command's usage function, which is run (then exit 0) for
# -h/--help. Everything after `--` is a path.
parse_args() {
  local usage_fn="$1" allowed=" $2 "
  shift 2
  ALL_ARG=""
  BASE_ARG=""
  PATH_ARGS=()
  EXTRA_FLAGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        "$usage_fn"
        exit 0
        ;;
      --all)
        ALL_ARG=1
        ;;
      --base)
        [[ $# -ge 2 && -n "$2" ]] || die "--base needs a branch name"
        BASE_ARG="$2"
        shift
        ;;
      --base=*)
        BASE_ARG="${1#--base=}"
        [[ -n "$BASE_ARG" ]] || die "--base needs a branch name"
        ;;
      --)
        shift
        PATH_ARGS+=("$@")
        break
        ;;
      -*)
        [[ "$allowed" == *" $1 "* ]] || {
          "$usage_fn" >&2
          die "unknown option: $1"
        }
        EXTRA_FLAGS+=("$1")
        ;;
      *)
        PATH_ARGS+=("$1")
        ;;
    esac
    shift
  done
}

# Succeeds if flag $1 was given (see parse_args).
has_flag() {
  local flag
  for flag in "${EXTRA_FLAGS[@]}"; do
    [[ "$flag" == "$1" ]] && return 0
  done
  return 1
}

# Populates ALL_PATHS from every tracked */.splice file. This *is* the whole
# discovery mechanism: a folder with a committed .splice is a splice.
discover_splices() {
  ALL_PATHS=()
  local file path
  local -A seen=()
  while IFS= read -r -d '' file; do
    [[ "$file" == "$STATE_FILE" ]] && die "a $STATE_FILE at the repository root isn't supported -- a splice must be a folder"
    path="${file%/"$STATE_FILE"}"
    [[ -n "${seen[$path]:-}" ]] && continue
    seen[$path]=1
    ALL_PATHS+=("$path")
  done < <(git ls-files -z -- ":(glob)**/$STATE_FILE")

  local other
  for path in "${ALL_PATHS[@]}"; do
    if other="$(overlapping_splice "$path")"; then
      die "nested splices are not supported: '$path' and '$other' overlap -- remove one of their $STATE_FILE files"
    fi
  done
}

# Prints the first splice in ALL_PATHS nested inside, or containing, $1.
# Nested splices are refused: the outer one's push would publish the inner
# one, and refs/splices/<outer>/<branch> could name a branch of either.
overlapping_splice() {
  local name="$1" path
  for path in "${ALL_PATHS[@]}"; do
    if [[ "$path" == "$name"/* || "$name" == "$path"/* ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

is_splice_path() {
  local path="$1" p
  for p in "${ALL_PATHS[@]}"; do
    [[ "$p" == "$path" ]] && return 0
  done
  return 1
}

# Resolves which splices a command acts on, into SELECTED_PATHS. $1 is the
# command's kind:
#   explicit  splices in or out (clone, init, merge, pull, push): needs
#             paths or --all
#   overview  looks or prepares (status, diff, log, fetch): every splice
#             unless paths are given
# Uses PATH_ARGS and ALL_ARG from parse_args; $2 is the command's name for
# messages.
declare -ga SELECTED_PATHS=()
select_paths() {
  local kind="$1" command="$2" path
  SELECTED_PATHS=()
  if [[ -n "$ALL_ARG" && ${#PATH_ARGS[@]} -gt 0 ]]; then
    die "give either paths or --all, not both"
  fi
  if [[ ${#PATH_ARGS[@]} -eq 0 ]]; then
    if [[ "$kind" == explicit && -z "$ALL_ARG" ]]; then
      die "which splice? -- name one or more paths, or pass --all (splices: ${ALL_PATHS[*]:-none})"
    fi
    SELECTED_PATHS=("${ALL_PATHS[@]}")
    [[ ${#SELECTED_PATHS[@]} -gt 0 ]] || die "no splices found -- nothing to $command"
    return 0
  fi
  local -A seen=()
  for path in "${PATH_ARGS[@]}"; do
    path="$(normalize_path "$path")"
    is_splice_path "$path" || die "not a splice: $path"
    [[ -n "${seen[$path]:-}" ]] && continue
    seen[$path]=1
    SELECTED_PATHS+=("$path")
  done
}

# Prints value <key> of splice <path>'s state file as committed in <rev>
# (default HEAD), or nothing if it isn't set. The file is Git's config
# format, so Git parses it -- it is never sourced.
splice_config() {
  local path="$1" key="$2" rev="${3:-HEAD}"
  git config --blob "$rev:$path/$STATE_FILE" --get "splice.$key" 2>/dev/null || true
}

# Prints a blob id: splice <path>'s state file as committed in HEAD (or a
# new one), with each "key=value" argument set ("key=" unsets it).
state_blob() {
  local path="$1" tmp kv key value
  shift
  tmp="$(mktemp)"
  git cat-file blob "HEAD:$path/$STATE_FILE" >"$tmp" 2>/dev/null || : >"$tmp"
  for kv in "$@"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    if [[ -n "$value" ]]; then
      git config --file "$tmp" "splice.$key" "$value"
    else
      git config --file "$tmp" --unset "splice.$key" 2>/dev/null || true
    fi
  done
  git hash-object -w "$tmp"
  rm -f "$tmp"
}

# Prints the tree of folder <path> in commit <rev>, or nothing if there is
# no folder there. (`<rev>:<path>^{tree}` would read "^{tree}" as part of
# the path.)
folder_tree() {
  local rev="$1" path="$2" object
  object="$(git rev-parse --verify --quiet "$rev:$path" 2>/dev/null)" || return 0
  [[ "$(git cat-file -t "$object")" == tree ]] && printf '%s\n' "$object"
  return 0
}

splice_ref() {
  printf 'refs/splices/%s/%s\n' "$1" "$2"
}

# Succeeds if any upstream branch of splice $1 has been fetched.
splice_fetched() {
  [[ -n "$(git for-each-ref --count=1 "refs/splices/$1/")" ]]
}

# Prints the monorepo's default branch name: the target of origin/HEAD,
# else init.defaultBranch, else nothing.
monorepo_default_branch() {
  local name
  name="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$name" ]]; then
    printf '%s\n' "${name#origin/}"
    return
  fi
  git config --get init.defaultBranch 2>/dev/null || true
}

# Prints the upstream branch splice $1 syncs with while the monorepo is on
# branch $2: the same name, except that the monorepo's default branch maps
# to the splice's recorded default-branch, if it has one.
upstream_branch_for() {
  local path="$1" branch="$2" default_branch
  default_branch="$(splice_config "$path" default-branch)"
  if [[ -n "$default_branch" && "$branch" == "$(monorepo_default_branch)" ]]; then
    printf '%s\n' "$default_branch"
  else
    printf '%s\n' "$branch"
  fi
}

# Prints the upstream's default branch (its HEAD), or nothing if it has
# none, e.g. because it is empty.
upstream_default_branch() {
  git ls-remote --symref -- "$1" HEAD 2>/dev/null |
    sed -n 's#^ref: refs/heads/\(.*\)\tHEAD$#\1#p'
}

# False for a name starting with '-', which Git would take for an option.
usable_name() {
  [[ "$1" != -* ]]
}

# Prints $1 as one shell word for a ready-to-run command we print: as-is if
# it only has characters no shell treats specially, else single-quoted.
shell_quote() {
  if [[ "$1" =~ ^[A-Za-z0-9_./:@%+=,-]+$ ]]; then
    printf '%s' "$1"
  else
    printf "'%s'" "${1//\'/\'\\\'\'}"
  fi
}

# Pathspecs for splice $1's content: the folder, without its state file.
content_pathspec() {
  printf '%s\n' ":(top,literal)$1" ":(top,exclude,literal)$1/$STATE_FILE"
}

# Prints the full ref of the monorepo's base branch -- the branch feature
# branches are cut from -- or fails if there is none. Git doesn't record
# which branch a branch was cut from, so this is resolved, in order, from:
#   1. the explicit branch given as $1 (from --base), which always wins;
#   2. the monorepo's default branch (see monorepo_default_branch).
# A name may be a local branch ("main"), a remote-tracking one
# ("origin/main") or a full ref. A candidate only counts if it exists and
# shares history with HEAD. There is deliberately no guessing at
# "main"/"master": callers ask the user for --base instead.
#
# When a name matches both a local branch and origin/<name>, the one whose
# merge base with HEAD is more recent wins, so a stale local branch can't
# hide the fresher origin/<name> a branch was actually cut from.
resolve_base_ref() {
  local explicit="${1:-}" candidates=() candidate ref refs mb best_ref="" best_mb=""
  if [[ -n "$explicit" ]]; then
    candidates+=("$explicit")
  else
    candidate="$(monorepo_default_branch)"
    [[ -n "$candidate" ]] && candidates+=("$candidate")
  fi
  for candidate in "${candidates[@]}"; do
    refs=("refs/heads/$candidate" "refs/remotes/$candidate" "refs/remotes/origin/$candidate")
    [[ "$candidate" == refs/* ]] && refs=("$candidate")
    for ref in "${refs[@]}"; do
      git show-ref --verify --quiet "$ref" || continue
      mb="$(git merge-base HEAD "$ref" 2>/dev/null)" || continue
      if [[ -z "$best_ref" ]] || { [[ "$mb" != "$best_mb" ]] && git merge-base --is-ancestor "$best_mb" "$mb"; }; then
        best_ref="$ref"
        best_mb="$mb"
      fi
    done
    [[ -n "$best_ref" ]] && break
  done
  [[ -n "$best_ref" ]] || return 1
  printf '%s\n' "$best_ref"
}

# For a splice whose upstream has no branch like the current one: has its
# content changed on this branch, compared with the monorepo's base branch?
# Judged purely inside the monorepo, from the merge base of HEAD and the
# base branch, so later changes on the base branch don't count against this
# one. The state file doesn't count: a pull alone changes nothing to push.
# Sets:
#   SPLICE_CHANGES_VS_BASE  yes | no | unresolved (no usable base branch)
#                           | self (the current branch is the base branch)
#                           | error (git could not compare)
#   SPLICE_BASE_REF         the resolved base ref (empty if unresolved)
#   SPLICE_BASE_BRANCH      its short name, for messages
#   SPLICE_BASE_MERGE_BASE  the merge base commit (yes/no only)
# $2 is an explicit --base branch, if any.
changes_vs_base() {
  local path="$1" explicit="${2:-}" head_ref rc pathspec=()
  SPLICE_CHANGES_VS_BASE="unresolved"
  SPLICE_BASE_REF=""
  SPLICE_BASE_BRANCH=""
  SPLICE_BASE_MERGE_BASE=""

  SPLICE_BASE_REF="$(resolve_base_ref "$explicit")" || {
    SPLICE_BASE_REF=""
    return 0
  }
  SPLICE_BASE_BRANCH="${SPLICE_BASE_REF#refs/heads/}"
  SPLICE_BASE_BRANCH="${SPLICE_BASE_BRANCH#refs/remotes/}"

  head_ref="$(git symbolic-ref --quiet HEAD 2>/dev/null || true)"
  if [[ "$SPLICE_BASE_REF" == "$head_ref" ]]; then
    SPLICE_CHANGES_VS_BASE="self"
    return 0
  fi

  SPLICE_BASE_MERGE_BASE="$(git merge-base HEAD "$SPLICE_BASE_REF")"
  mapfile -t pathspec < <(content_pathspec "$path")
  # `git diff --quiet` exits 1 for "differs" and >1 for a real failure; only
  # the former may be read as "changed", or an error would create a branch.
  if git diff --quiet "$SPLICE_BASE_MERGE_BASE" HEAD -- "${pathspec[@]}" 2>/dev/null; then
    SPLICE_CHANGES_VS_BASE="no"
  else
    rc=$?
    if ((rc == 1)); then
      SPLICE_CHANGES_VS_BASE="yes"
    else
      SPLICE_CHANGES_VS_BASE="error"
    fi
  fi
}
