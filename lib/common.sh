# Shared discovery, state, classification and logging helpers.
# Sourced first by the entrypoint; every other lib/*.sh file assumes these
# are already in scope.

# Every splice path in the repository, from its committed .splice file.
declare -ga ALL_PATHS=()
# Each splice's upstream URL, and the key its fetched refs live under (see
# upstream_key; empty until the upstream is first fetched), by path. Set by
# discover_splices, and by clone for the splice it creates.
declare -gA SPLICE_URLS=()
declare -gA SPLICE_KEYS=()
# Each splice's upstream's name in its .splice, [upstream "<name>"], by path.
declare -gA SPLICE_UPSTREAM_NAMES=()

# Name of the one upstream clone and init write into a new .splice.
DEFAULT_UPSTREAM=origin
# Results of parse_args.
declare -g BASE_ARG=""
declare -g UPSTREAM_ARG=""
declare -g ALL_ARG=""
declare -ga PATH_ARGS=()
declare -ga EXTRA_FLAGS=()

# Name of the state file inside every splice folder.
STATE_FILE=.splice

# Prints the first state file in upstream commit <commit>, at its root or
# deeper, e.g. because the upstream uses git splice itself. Fails if there
# is none. Bringing one in would replace the splice's own, or nest a splice
# inside it, and every command refuses nested splices.
upstream_state_file() {
  local file
  IFS= read -r -d '' file < <(state_files "$1") || return 1
  printf '%s\n' "$file"
}

# Prints every state file in commit <commit>, at any depth, NUL-separated.
# Git filters them (a diff from the empty tree lists every file), so
# neither a file name with a newline nor a non-GNU grep gets in the way.
state_files() {
  git diff-tree -r --name-only -z "$(git hash-object -t tree /dev/null)" "$1" -- ":(top,glob)**/$STATE_FILE"
}

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
  unlock_upstream_keys
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
  UPSTREAM_ARG=""
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
      --upstream | --upstream=*)
        [[ "$allowed" == *" --upstream "* ]] || {
          "$usage_fn" >&2
          die "unknown option: ${1%%=*}"
        }
        if [[ "$1" == --upstream ]]; then
          [[ $# -ge 2 && -n "$2" ]] || die "--upstream needs an upstream's name"
          UPSTREAM_ARG="$2"
          shift
        else
          UPSTREAM_ARG="${1#--upstream=}"
          [[ -n "$UPSTREAM_ARG" ]] || die "--upstream needs an upstream's name"
        fi
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

# Populates ALL_PATHS from every */.splice file committed in HEAD. This
# *is* the whole discovery mechanism: a folder with a committed .splice is a
# splice. Committed, not staged: every command reads a splice's state from
# HEAD, so a staged .splice isn't one yet, and a staged deletion doesn't end
# one.
discover_splices() {
  ALL_PATHS=()
  local file path
  while IFS= read -r -d '' file; do
    [[ "$file" == "$STATE_FILE" ]] && die "a $STATE_FILE at the repository root isn't supported -- a splice must be a folder"
    path="${file%/"$STATE_FILE"}"
    usable_splice_path "$path" ||
      die "'$path' isn't supported as a splice path yet -- rename the folder (e.g. no spaces)"
    ALL_PATHS+=("$path")
  done < <(state_files HEAD 2>/dev/null)

  for path in "${ALL_PATHS[@]}"; do
    load_splice_upstream "$path"
  done

  local other
  for path in "${ALL_PATHS[@]}"; do
    if other="$(overlapping_splice "$path")"; then
      die "nested splices are not supported: '$path' and '$other' overlap -- remove one of their $STATE_FILE files"
    fi
  done
}

# Succeeds if <path> would be valid in a ref name: no spaces, "..", or a
# component ending in ".lock". Splice paths were part of their refs' names
# before refs were keyed by URL, and are still limited to these until
# every command is tested with the others.
usable_splice_path() {
  git check-ref-format "refs/splices/$1/branch"
}

# Prints the first splice in ALL_PATHS nested inside, or containing, $1.
# Nested splices are refused: the outer one's push would publish the inner
# one.
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
# new one), with each "key=value" argument set ("key=" unsets it). A key
# without a section is in [splice], e.g. "commit"; others are given in
# full, e.g. "upstream.origin.url".
state_blob() {
  local path="$1" tmp kv key value
  shift
  tmp="$(mktemp)"
  git cat-file blob "HEAD:$path/$STATE_FILE" >"$tmp" 2>/dev/null || : >"$tmp"
  for kv in "$@"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    [[ "$key" == *.* ]] || key="splice.$key"
    if [[ -n "$value" ]]; then
      git config --file "$tmp" "$key" "$value"
    else
      git config --file "$tmp" --unset "$key" 2>/dev/null || true
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

# Reads splice <path>'s upstream from its committed state file into
# SPLICE_URLS and SPLICE_KEYS, or dies explaining what's wrong with it:
#
#   [upstream "origin"]
#   	url = https://github.com/x/lib.git
#
# Exactly one [upstream] section is supported for now.
load_splice_upstream() {
  local path="$1" records=() record urls=() names=() name old_url="" error q_file
  # One git config per splice: discovery runs this for every splice, in
  # every command. NUL-delimited, since a value, e.g. a local path, may
  # contain a newline; git's status follows as the last record, since it
  # may list some entries before failing. An if, so set -e can't end the
  # subshell before the status is printed.
  mapfile -d '' records < <(
    if git config --blob "HEAD:$path/$STATE_FILE" --list -z 2>/dev/null; then
      printf 0
    else
      printf '%d' "$?"
    fi
  )
  if [[ "${records[-1]}" != 0 ]]; then
    error="$(git config --blob "HEAD:$path/$STATE_FILE" --list 2>&1 >/dev/null || true)"
    error="${error%%$'\n'*}"
    die "$path/$STATE_FILE can't be read (${error#error: }) -- fix it and commit it"
  fi
  unset 'records[-1]'
  for record in "${records[@]}"; do
    # Each record is <key>, a newline, and the value.
    case "${record%%$'\n'*}" in
      # An empty URL names no upstream.
      upstream.*.url)
        [[ -n "${record#*$'\n'}" ]] || continue
        urls+=("${record#*$'\n'}")
        name="${record%%$'\n'*}"
        name="${name#upstream.}"
        names+=("${name%.url}")
        ;;
      splice.url) old_url="${record#*$'\n'}" ;;
    esac
  done
  if [[ ${#urls[@]} -eq 0 ]]; then
    q_file="$(shell_quote "$path/$STATE_FILE")"
    if [[ -n "$old_url" ]]; then
      log_err "$path/$STATE_FILE has its URL in the old format, splice.url -- convert it with:"
      cat >&2 <<EOF

  git config --file $q_file upstream.$DEFAULT_UPSTREAM.url $(shell_quote "$old_url")
  git config --file $q_file --unset splice.url
  git commit -m $(shell_quote "splice: name $path's upstream") -- $q_file

EOF
      exit 1
    fi
    die "$path/$STATE_FILE names no upstream -- add one: git config --file $q_file upstream.$DEFAULT_UPSTREAM.url <url>"
  fi
  [[ ${#urls[@]} -eq 1 ]] ||
    die "$path/$STATE_FILE names ${#urls[@]} upstreams -- only one is supported so far"
  upstream_key "${urls[0]}"
  SPLICE_URLS[$path]="${urls[0]}"
  SPLICE_UPSTREAM_NAMES[$path]="${names[0]}"
  SPLICE_KEYS[$path]="$UPSTREAM_KEY"
}

# Each upstream URL's key, and each key's URL, as recorded in the
# repository's config by create_upstream_key. Loaded by
# load_upstream_keys.
declare -gA KEY_OF_URL=()
declare -gA URL_OF_KEY=()
declare -g UPSTREAM_KEYS_LOADED=""

# Reads the keys of the upstreams fetched so far from the repository's
# config, where create_upstream_key records them as splice.<key>.url:
#
#   [splice "lib"]
#   	url = https://github.com/x/lib.git
#
# --local: the repository's own config, which all its worktrees share, as
# they share refs/splices/. Dies if an edit by hand broke what
# create_upstream_key keeps: valid keys, each with one URL, and each URL
# with one key.
load_upstream_keys() {
  [[ -z "$UPSTREAM_KEYS_LOADED" ]] || return 0
  local records=() record key url
  mapfile -d '' records < <(git config --local -z --get-regexp '^splice\..*\.url$' || true)
  for record in "${records[@]}"; do
    key="${record%%$'\n'*}"
    key="${key#splice.}"
    key="${key%.url}"
    url="${record#*$'\n'}"
    valid_upstream_key "$key" ||
      die "splice.$key.url in the repository's config: '$key' isn't a valid key -- rename it: git config --local --rename-section $(shell_quote "splice.$key") splice.<new-key>"
    [[ -n "$url" ]] ||
      die "splice.$key.url in the repository's config is empty -- remove it: git config --local --remove-section splice.$key"
    [[ -z "${URL_OF_KEY[$key]+set}" ]] ||
      die "splice.$key.url is set more than once in the repository's config -- keep one: git config --local --edit"
    [[ -z "${KEY_OF_URL[$url]+set}" ]] ||
      die "keys '${KEY_OF_URL[$url]}' and '$key' both name $url in the repository's config -- remove one: git config --local --remove-section splice.$key"
    URL_OF_KEY[$key]="$url"
    KEY_OF_URL[$url]="$key"
  done
  UPSTREAM_KEYS_LOADED=1
}

# Forgets the keys load_upstream_keys read, so the next lookup reads the
# config again.
reload_upstream_keys() {
  UPSTREAM_KEYS_LOADED=""
  KEY_OF_URL=()
  URL_OF_KEY=()
  load_upstream_keys
}

# Sets UPSTREAM_KEY to the key the fetched refs of upstream <url> live
# under, refs/splices/<key>/<branch>, or to nothing if the upstream has
# never been fetched. Keyed by URL rather than by the splice's path, refs
# follow a splice through git mv, and splices at one path with different
# upstreams, e.g. on two branches, don't share them. The URL is taken
# exactly as written, so splices share refs only if their URLs are equal
# -- spellings that look alike can name different repositories, e.g.
# /srv/lib and /srv/lib.git.
upstream_key() {
  load_upstream_keys
  UPSTREAM_KEY="${KEY_OF_URL[$1]:-}"
  [[ -z "$UPSTREAM_KEY" ]] || return 0
  # Not cached: another command may have recorded it since.
  reload_upstream_keys
  UPSTREAM_KEY="${KEY_OF_URL[$1]:-}"
}

# Succeeds if <key> can name an upstream: lower-case letters, digits, ".",
# "_" and "-", starting and ending with a letter or digit, and at most 64
# long. Lower case only, so no two keys' refs share files on a
# case-insensitive file system; no "/", so no key's refs nest in another's.
valid_upstream_key() {
  local key="$1"
  [[ "$key" =~ ^[a-z0-9]([a-z0-9._-]{0,62}[a-z0-9])?$ ]] &&
    git check-ref-format "refs/splices/$key/main"
}

# Succeeds if <key> names an upstream already, or refs are left under it,
# e.g. from a key that was removed from the config by hand.
upstream_key_taken() {
  load_upstream_keys
  [[ -n "${URL_OF_KEY[$1]+set}" ]] || [[ -n "$(git for-each-ref --count=1 "refs/splices/$1/")" ]]
}

# Sets KEY_CANDIDATE to <name> as a valid key, or to nothing if nothing
# usable is left: lower case, with anything valid_upstream_key doesn't
# allow replaced by "-", and its end kept if it's too long.
upstream_key_candidate() {
  local LC_ALL=C name="${1,,}"
  name="${name//[^a-z0-9._-]/-}"
  while [[ "$name" == *--* ]]; do name="${name//--/-}"; done
  while [[ "$name" == *..* ]]; do name="${name//../.}"; done
  ((${#name} <= 60)) || name="${name: -60}"
  while [[ "$name" == [._-]* ]]; do name="${name:1}"; done
  while [[ "$name" == *[._-] ]]; do name="${name%?}"; done
  [[ "$name" != *.lock ]] || name="${name%.lock}-lock"
  valid_upstream_key "$name" || name=""
  KEY_CANDIDATE="$name"
}

# Sets KEY_CANDIDATES to the keys upstream <url> could get, most readable
# first: its last path component without .git, then with more of the path
# in front, up to the host, until one is free:
#
#   https://github.com/x/lib.git    lib, x-lib, github.com-x-lib
#   git@gitlab.com:y/My_Lib.git     my_lib, y-my_lib, gitlab.com-y-my_lib
#   /srv/git/lib/                   lib, git-lib, srv-git-lib
#
# Falls back to "upstream" if no part of the URL is usable.
upstream_key_candidates() {
  local url="$1" rest parts=() part name="" i
  rest="${url#*://}"
  while [[ "$rest" == */ ]]; do rest="${rest%/}"; done
  rest="${rest%.git}"
  IFS='/:' read -r -a parts <<<"$rest"
  KEY_CANDIDATES=()
  for ((i = ${#parts[@]} - 1; i >= 0; i--)); do
    part="${parts[i]##*@}"
    [[ -n "$part" ]] || continue
    name="$part${name:+-$name}"
    upstream_key_candidate "$name"
    [[ -z "$KEY_CANDIDATE" ]] || [[ " ${KEY_CANDIDATES[*]} " == *" $KEY_CANDIDATE "* ]] ||
      KEY_CANDIDATES+=("$KEY_CANDIDATE")
  done
  [[ ${#KEY_CANDIDATES[@]} -gt 0 ]] || KEY_CANDIDATES=(upstream)
}

# Where create_upstream_key and rename_upstream_key take turns: a folder
# in the repository's common Git directory, which mkdir creates or fails
# on in one step. Set while held; die releases it. Waits up to
# UPSTREAM_KEYS_LOCK_TRIES tenths of a second for another command's.
UPSTREAM_KEYS_LOCK=""
UPSTREAM_KEYS_LOCK_TRIES=50

lock_upstream_keys() {
  local lock i
  lock="$(git rev-parse --path-format=absolute --git-common-dir)/splice-keys.lock"
  for ((i = 0; i < UPSTREAM_KEYS_LOCK_TRIES; i++)); do
    if mkdir -- "$lock" 2>/dev/null; then
      UPSTREAM_KEYS_LOCK="$lock"
      return 0
    fi
    sleep 0.1
  done
  die "another git splice is recording an upstream key -- if none is running, remove $lock"
}

unlock_upstream_keys() {
  [[ -z "$UPSTREAM_KEYS_LOCK" ]] || rmdir -- "$UPSTREAM_KEYS_LOCK" 2>/dev/null || true
  UPSTREAM_KEYS_LOCK=""
}

# Sets UPSTREAM_KEY to upstream <url>'s key, and records one in the
# repository's config first if it has none: the first of
# upstream_key_candidates that's free, or the last with "-2", "-3" and so
# on. Under the lock, so two commands recording keys at the same time,
# e.g. first fetches in two worktrees, can't pick the same one.
create_upstream_key() {
  local url="$1" key="" candidate n
  upstream_key "$url"
  [[ -z "$UPSTREAM_KEY" ]] || return 0
  lock_upstream_keys
  reload_upstream_keys
  if [[ -n "${KEY_OF_URL[$url]:-}" ]]; then
    UPSTREAM_KEY="${KEY_OF_URL[$url]}"
    unlock_upstream_keys
    return 0
  fi
  upstream_key_candidates "$url"
  for candidate in "${KEY_CANDIDATES[@]}"; do
    if ! upstream_key_taken "$candidate"; then
      key="$candidate"
      break
    fi
  done
  if [[ -z "$key" ]]; then
    n=2
    while upstream_key_taken "$candidate-$n"; do n=$((n + 1)); done
    key="$candidate-$n"
  fi
  git config --local "splice.$key.url" "$url" ||
    die "couldn't record the key of $url in the repository's config"
  unlock_upstream_keys
  URL_OF_KEY[$key]="$url"
  KEY_OF_URL[$url]="$key"
  UPSTREAM_KEY="$key"
}

# Gives splice <path>'s upstream a key, if it has none yet, and every
# splice with the same URL along with it. For the commands that write
# refs: clone, fetch, pull and push.
ensure_splice_key() {
  local path="$1" p
  require_splice_upstream "$path"
  [[ -z "${SPLICE_KEYS[$path]}" ]] || return 0
  create_upstream_key "${SPLICE_URLS[$path]}"
  for p in "${!SPLICE_URLS[@]}"; do
    [[ "${SPLICE_URLS[$p]}" != "${SPLICE_URLS[$path]}" ]] || SPLICE_KEYS[$p]="$UPSTREAM_KEY"
  done
}

# Prints the ref prefix splice <path>'s fetched upstream branches share. An
# upstream without a key has no refs: its prefix, "refs/splices/./", isn't
# a valid ref name, so it matches none.
splice_refs_prefix() {
  printf 'refs/splices/%s/\n' "${SPLICE_KEYS[$1]:-.}"
}

# Prints the ref of upstream branch <branch> of splice <path>, as fetched.
splice_ref() {
  printf '%s%s\n' "$(splice_refs_prefix "$1")" "$2"
}

# Dies unless upstream <name> (from --upstream) is one of splice <path>'s,
# or <name> is empty. Leaving it out picks the splice's only upstream; once
# a .splice can name several, it will have to name one of them.
require_upstream_name() {
  local path="$1" name="$2"
  require_splice_upstream "$path"
  [[ -z "$name" || "$name" == "${SPLICE_UPSTREAM_NAMES[$path]}" ]] ||
    die "$path has no upstream '$name' -- its upstream is '${SPLICE_UPSTREAM_NAMES[$path]}'"
}

# Loads splice <path>'s upstream, unless discover_splices or clone has, and
# looks up its key again if it had none yet.
require_splice_upstream() {
  if [[ -z "${SPLICE_URLS[$1]:-}" ]]; then
    load_splice_upstream "$1"
  elif [[ -z "${SPLICE_KEYS[$1]}" ]]; then
    upstream_key "${SPLICE_URLS[$1]}"
    SPLICE_KEYS[$1]="$UPSTREAM_KEY"
  fi
}

# Succeeds if any upstream branch of splice $1 has been fetched.
splice_fetched() {
  [[ -n "${SPLICE_KEYS[$1]}" ]] &&
    [[ -n "$(git for-each-ref --count=1 "$(splice_refs_prefix "$1")")" ]]
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

# Succeeds if splice $1's folder has uncommitted changes: staged, unstaged
# or untracked files (ignored ones don't count). Every command reads a
# splice from HEAD, so push leaves them out. Returns 1 for none, and 2 if
# git status failed, which must not pass for "none".
has_uncommitted_changes() {
  local changes
  changes="$(git status --porcelain --untracked-files=normal -- ":(top,literal)$1" 2>/dev/null)" || return 2
  [[ -n "$changes" ]]
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
