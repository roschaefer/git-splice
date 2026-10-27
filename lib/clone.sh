# Assumes lib/common.sh, lib/rebuild.sh, lib/state.sh and lib/fetch.sh are
# already sourced.

usage_clone() {
  cat <<'EOF'
NAME
    git-splice-clone - Splice an existing repository into the monorepo

SYNOPSIS
    git splice clone [--merge] [-m <message>] <url> [<path>]
    git splice clone --from-submodule [--recursive | -m <message>] <path>

DESCRIPTION
    Splices an existing upstream repository into <path> (default: the
    repository's name), as one ordinary commit with a new <path>/.splice.

    The upstream branch is the one named like the current branch, else the
    upstream's default branch; your first push then creates the missing
    branch. If the upstream's default branch is named differently from the
    monorepo's, .splice records it as the upstream's default-branch. Inside another splice,
    it's compared with that splice's default branch instead, and on the
    monorepo's default branch, that's the upstream branch: the monorepo's
    branch name isn't tried.

    If <path> already exists with exactly the upstream's content, clone only
    adds .splice. If its content differs, clone refuses, unless --merge is
    given: then every file that differs becomes a conflict to resolve, and
    nothing is lost. Resolve it and run 'git commit'.

    With --from-submodule, <path> is a submodule committed in HEAD, and clone
    turns it into a splice of the same upstream, at the same commit: the
    upstream is the submodule's URL in .gitmodules, and the folder gets the
    files of the commit the submodule points to. One commit replaces the
    submodule with the folder, and removes it from .gitmodules (the file too,
    once empty). Upstream must serve the commit, on a branch, a tag or by
    id, and a checkout of the submodule must be at that commit without
    changes; clone refuses otherwise. It asks git status for those changes,
    so it can't see the ones hidden by 'git update-index --assume-unchanged'
    or '--skip-worktree': an edited file keeps its edit, but a deleted one
    comes back. Clear these flags first. Files Git ignores in the checkout
    stay, and its repository stays in .git/modules/.

    The splice keeps what the submodule followed. submodule.<name>.branch,
    the branch 'git submodule update --remote' follows, becomes the
    upstream's default-branch ("." needs none: a splice follows the branch
    named like the current one by default; inside a splice that pins a tag
    or a commit, it stays at its commit). Without it, the submodule stayed
    at its commit, and the upstream's default-pin pins that commit: on the
    monorepo's default branch, pull brings in nothing and push refuses until
    default-pin is removed. Other settings in .gitmodules are dropped.

    A submodule whose commit has submodules of its own is refused, unless
    --recursive is given: then clone converts those too, one commit each,
    top-down. Their URLs and settings come from the .gitmodules in the
    folder above, and a relative URL is relative to that folder's upstream.
    The upstream above still has the submodule, so the folder differs from
    it by that commit: the next push of the folder above sends it, which
    turns the submodule into a splice there too. Push it before that
    upstream moves its submodule to another commit: pulling such a change
    is refused. If a nested submodule is refused, the ones above stay
    converted; fix what the message says, then run clone on that path.

    -m gives the commit this message instead of the default one, which
    names the upstream branch and commit. Nothing reads the message back:
    .splice records them.
EOF
}

# Prints the folder name `git clone` would pick for <url>.
default_clone_path() {
  local name="${1%/}"
  name="${name%.git}"
  name="${name##*/}"
  name="${name##*:}"
  printf '%s\n' "$name"
}

# Fetches <url>, a new upstream of a splice to be created at <path>, and
# registers it as that splice's default upstream. Sets NEW_DEFAULT_BRANCH
# to the default-branch .splice has to record: the upstream's default
# branch where it's named differently from the default branch of what
# the splice lives in, else nothing. Also sets UPSTREAM_DEFAULT,
# MONOREPO_DEFAULT and CONTAINER_DEFAULT, the default branches it compared.
# With <only-fetch> set, it only fetches and registers: a submodule's
# conversion records what the submodule followed instead.
NEW_DEFAULT_BRANCH=""
UPSTREAM_DEFAULT=""
MONOREPO_DEFAULT=""
CONTAINER_DEFAULT=""
fetch_new_upstream() {
  local path="$1" url="$2" only_fetch="${3:-}"
  # Before the fetch: refuses if the splice above leaves it open.
  [[ -n "$only_fetch" ]] || container_default_branch "$path" >/dev/null
  create_upstream_key "$url"
  SPLICE_UPSTREAM_LISTS[$path]="$DEFAULT_UPSTREAM"
  UPSTREAM_URLS["$path:$DEFAULT_UPSTREAM"]="$url"
  SPLICE_DEFAULT_UPSTREAMS[$path]="$DEFAULT_UPSTREAM"
  use_upstream "$path" "$DEFAULT_UPSTREAM"
  log_step "$path: fetching $url"
  fetch_upstream "$url" "$(splice_refs_prefix "$path")" || die "$path: fetch failed"
  # A submodule's commit may be on no branch, only on a tag.
  [[ -z "$only_fetch" ]] || return 0
  splice_fetched "$path" || die "$url has no branches yet -- to publish $path there, use 'git splice init $(shell_quote "$path") $(shell_quote "$url")'"

  # Map the monorepo's default branch to the upstream's, if it differs from
  # the default branch of what the splice lives in: the splice above it,
  # or the monorepo (container_default_branch).
  NEW_DEFAULT_BRANCH=""
  UPSTREAM_DEFAULT="$(upstream_default_branch "$url")"
  MONOREPO_DEFAULT="$(monorepo_default_branch)"
  CONTAINER_DEFAULT="$(container_default_branch "$path")"
  if [[ -n "$UPSTREAM_DEFAULT" && -z "$MONOREPO_DEFAULT" && "$UPSTREAM_DEFAULT" != "$(current_branch)" ]]; then
    # Without the monorepo's default branch, the splice couldn't map it to
    # upstream's: it would look for the current branch upstream from the
    # start, even inside a splice whose default branch is known.
    die "$path: upstream's default branch is '$UPSTREAM_DEFAULT', and the monorepo's can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"
  elif [[ -n "$UPSTREAM_DEFAULT" && -n "$CONTAINER_DEFAULT" && "$UPSTREAM_DEFAULT" != "$CONTAINER_DEFAULT" ]]; then
    NEW_DEFAULT_BRANCH="$UPSTREAM_DEFAULT"
  fi
}

cmd_clone() {
  parse_args usage_clone "--merge --from-submodule --recursive -m" "$@"
  if has_flag --from-submodule; then
    require_args usage_clone clone 1 1
    has_flag --merge && die "--from-submodule takes no --merge: the folder gets the submodule's files"
    local recursive=""
    has_flag --recursive && recursive=1
    [[ -z "$recursive" || -z "$MESSAGE_ARG" ]] ||
      die "-m names one commit, and --recursive makes one per submodule"
    clone_from_submodule "${PATH_ARGS[0]}" "$recursive"
    return
  fi
  has_flag --recursive && die "--recursive needs --from-submodule: it converts the submodule's own submodules too"
  local merge=""
  has_flag --merge && merge=1
  require_args usage_clone clone 1 2
  local url="${PATH_ARGS[0]}" path="${PATH_ARGS[1]:-}"
  if [[ -z "$url" ]]; then
    usage_clone >&2
    exit 1
  fi
  [[ -n "$path" ]] || path="$(default_clone_path "$url")"
  path="$(normalize_path "$path")"
  [[ -n "$path" && "$path" != . && "$path" != /* ]] || die "'$path' isn't a folder inside the repository"
  require_usable_splice_path "$path" "choose another folder name"

  open_repository
  local branch
  branch="$(current_branch)"
  is_splice_path "$path" && die "$path is a splice already"
  require_no_splice_in_progress
  [[ "$(path_mode HEAD "$path")" == 160000 ]] &&
    die "$path is a submodule -- 'git splice clone --from-submodule $(shell_quote "$path")' turns it into a splice"
  if git cat-file -e "HEAD:$path" 2>/dev/null && [[ -z "$(folder_tree HEAD "$path")" ]]; then
    die "$path is a file, not a folder"
  fi

  fetch_new_upstream "$path" "$url"
  local default_branch="$NEW_DEFAULT_BRANCH" upstream_branch="$branch"
  [[ -n "$MONOREPO_DEFAULT" && "$branch" == "$MONOREPO_DEFAULT" ]] && upstream_branch="${default_branch:-$CONTAINER_DEFAULT}"
  if ! git show-ref --verify --quiet "$(splice_ref "$path" "$upstream_branch")"; then
    # On the monorepo's default branch inside a splice, '$upstream_branch'
    # is the splice above's default branch. The monorepo's branch name says
    # nothing about this upstream then, so it isn't tried instead.
    [[ -n "$UPSTREAM_DEFAULT" ]] || die "$path: upstream has no '$upstream_branch' branch and names no default branch"
    log_step "$path: upstream has no '$upstream_branch' branch -- using '$UPSTREAM_DEFAULT'; your first push creates '$upstream_branch'"
    upstream_branch="$UPSTREAM_DEFAULT"
  fi

  local target local_folder
  target="$(git rev-parse "$(splice_ref "$path" "$upstream_branch")^{commit}")"
  upstream_has_state_file "$target" &&
    die "$path: upstream has a $STATE_FILE at its root, which would replace $path/$STATE_FILE -- splice a folder of it instead"
  local inner
  inner="$(upstream_submodule "$target")"
  [[ -z "$inner" ]] ||
    die "$path: upstream has a submodule, $inner, which nobody could check out in the monorepo -- turn it into a splice in the upstream first"
  local_folder="$(folder_tree HEAD "$path")"
  if [[ -n "$local_folder" && "$local_folder" != "$(git rev-parse "$target^{tree}")" && -z "$merge" ]]; then
    die "$path exists and differs from '$upstream_branch' upstream -- '--merge' keeps both, and every file that differs becomes a conflict to resolve"
  fi

  local blob
  blob="$(state_blob "$path" "id=$(new_splice_id "$path" "$url" "$target")" "commit=$target" "upstream.$DEFAULT_UPSTREAM.url=$url" "upstream.$DEFAULT_UPSTREAM.default-branch=$default_branch")" || exit 1
  # The merge base is an empty folder: the two sides share nothing.
  if ! splice_in "$path" "" "" "$target^{tree}" "$blob" \
    "$(commit_message "splice: clone $path from $upstream_branch at ${target:0:7}")"; then
    log_err "$path: clone failed"
    exit 1
  fi
  log_ok "$path: cloned ${target:0:7} from $upstream_branch"
}

# Prints the mode of <path> in commit <rev>, e.g. 160000 for a submodule,
# or nothing if it isn't there.
path_mode() {
  local entry
  entry="$(git ls-tree -z "$1" -- "$2" | tr -d '\0')"
  [[ "${entry#*$'\t'}" == "$2" ]] || return 0
  printf '%s\n' "${entry%% *}"
}

# Prints the name of the submodule at <path>, relative to the folder of
# .gitmodules file <gitmodules> in HEAD, or nothing if none has that path.
submodule_name() {
  local gitmodules="$1" path="$2" entry key
  while IFS= read -r -d '' entry; do
    key="${entry%%$'\n'*}"
    if [[ "$(normalize_path "${entry#*$'\n'}")" == "$path" ]]; then
      key="${key#submodule.}"
      printf '%s\n' "${key%.path}"
      return
    fi
  done < <(git config -z --blob "HEAD:$gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null)
}

# Prints submodule URL <url> as `git submodule` reads it: a relative one,
# starting with ./ or ../, is relative to URL <base>, if given: the
# upstream of the splice the submodule is in. Else it's relative to the
# URL of the monorepo's default remote -- the current branch's remote,
# else origin -- or, without one, to the monorepo itself. Git resolves
# it: `git submodule init` in a throwaway repository whose origin has
# that URL records it resolved.
resolve_submodule_url() {
  local url="$1" base="${2:-}" branch remote tmp resolved
  [[ "$url" == ./* || "$url" == ../* ]] || {
    printf '%s\n' "$url"
    return
  }
  if [[ -z "$base" ]]; then
    branch="$(git symbolic-ref --quiet --short HEAD || true)"
    remote="$(git config "branch.$branch.remote" 2>/dev/null || echo origin)"
    base="$(git config "remote.$remote.url" 2>/dev/null || git rev-parse --show-toplevel)"
  fi
  # A relative path is relative to the monorepo, not to the throwaway
  # repository.
  [[ "$base" == /* || "$base" == *:* ]] || base="$(git rev-parse --show-toplevel)/$base"
  tmp="$(mktemp -d)"
  resolved="$(
    cd "$tmp" &&
      git init -q &&
      git config remote.origin.url "$base" &&
      git config --file .gitmodules submodule.s.path s &&
      git config --file .gitmodules submodule.s.url "$url" &&
      git update-index --add --cacheinfo "160000,$(git hash-object -t tree /dev/null),s" &&
      git submodule --quiet init -- s &&
      git config submodule.s.url
  )" || resolved=""
  rm -rf -- "$tmp"
  [[ -n "$resolved" ]] || die "can't resolve submodule URL '$url' against '$base'"
  printf '%s\n' "$resolved"
}

# Dies unless converting the submodule at <path>, committed at <commit>,
# can't lose anything. The conversion writes to the index, .gitmodules
# file <gitmodules>, the folder and its .splice, and each must be
# unchanged from HEAD or missing. Content is compared, not just what git
# status says: index flags like assume-unchanged hide edits from it.
refuse_lossy_submodule_conversion() {
  local path="$1" commit="$2" gitmodules="$3"
  git diff --cached --quiet ||
    die "$path: there are staged changes -- commit or unstage them first, the conversion commits only its own"
  # HEAD has a .gitmodules: it names the submodule.
  if [[ ! -e "$gitmodules" && ! -L "$gitmodules" ]] ||
    [[ "$(git hash-object -- "$gitmodules")" != "$(git rev-parse "HEAD:$gitmodules")" ]]; then
    die "$path: $gitmodules has uncommitted changes -- commit or discard them first"
  fi
  local parent="$path"
  while [[ "$parent" == */* ]]; do
    parent="${parent%/*}"
    [[ ! -L "$parent" ]] ||
      die "$path: $parent is a symbolic link -- the submodule's folder must be inside the repository"
  done
  if [[ -L "$path" ]]; then
    die "$path: a symbolic link takes the submodule's place -- remove it first"
  elif [[ -e "$path/.git" ]]; then
    [[ "$(git -C "$path" rev-parse HEAD 2>/dev/null)" == "$commit" ]] ||
      die "$path: the submodule's checkout isn't at ${commit:0:7}, the commit in HEAD -- commit the submodule's new commit, or check out ${commit:0:7} in it"
    [[ -z "$(git -C "$path" status --porcelain --untracked-files=all)" ]] ||
      die "$path: the submodule's checkout has changes -- commit and push them, or discard them, first"
    # An ignored one: status doesn't show it.
    [[ ! -e "$path/$STATE_FILE" && ! -L "$path/$STATE_FILE" ]] ||
      die "$path/$STATE_FILE exists in the submodule's checkout -- move it away first"
  elif [[ -e "$path" && ! -d "$path" ]]; then
    die "$path: a file takes the place of the uninitialized submodule -- move it away first"
  elif [[ -d "$path" && -n "$(ls -A -- "$path")" ]]; then
    die "$path: the folder of the uninitialized submodule isn't empty -- move its files away first"
  fi
}

# Sets SUBMODULE_BRANCH and SUBMODULE_PIN to the default-branch and
# default-pin the splice at <path> of submodule <name>, committed at
# <commit> and listed in <gitmodules>, records to mean what the submodule
# meant; empty ones aren't recorded. Its branch setting, for
# 'git submodule update --remote', names the branch it follows: that one,
# unless the splice would follow it anyway (container_default_branch);
# "." follows the branch named like the current one, which a splice does
# without a default-branch. Without a branch, the submodule stayed at
# its commit, and so does the splice. Inside a splice that pins a tag or
# a commit, there's no such branch: "." stays at its commit too, which
# SUBMODULE_PINNED_AS then says. Dies if a pin or a default-branch can't
# apply because the monorepo's default branch can't be determined.
submodule_defaults() {
  local path="$1" gitmodules="$2" name="$3" commit="$4" branch above pinned_above=""
  branch="$(git config --blob "HEAD:$gitmodules" "submodule.$name.branch" 2>/dev/null || true)"
  SUBMODULE_BRANCH="" SUBMODULE_PIN="" SUBMODULE_PINNED_AS="the submodule was"
  if above="$(splice_above_in HEAD "$path")"; then
    resolve_default_target "$above"
    [[ "$TARGET_KIND" == branch ]] || pinned_above=1
  fi
  case "$branch" in
    "") SUBMODULE_PIN="$commit" ;;
    .)
      if [[ -n "$pinned_above" ]]; then
        SUBMODULE_PIN="$commit"
        SUBMODULE_PINNED_AS="$above is"
      fi
      ;;
    *)
      if [[ -n "$pinned_above" || "$branch" != "$(container_default_branch "$path")" ]]; then
        SUBMODULE_BRANCH="$branch"
      fi
      ;;
  esac
  if [[ -z "$(monorepo_default_branch)" ]]; then
    if [[ -n "$SUBMODULE_PIN" ]]; then
      die "$path: the submodule stays at ${commit:0:7}, and a pin applies on the monorepo's default branch, which can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"
    elif [[ -n "$SUBMODULE_BRANCH" ]]; then
      die "$path: the submodule follows '$SUBMODULE_BRANCH', and a default-branch applies on the monorepo's default branch, which can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"
    fi
  fi
}

# Prints the name of a tag of upstream <url> that names <commit>, or
# nothing. Reads the whole listing: git ls-remote would get a SIGPIPE if
# awk stopped at the first match.
tag_naming() {
  git ls-remote --tags -- "$1" 2>/dev/null |
    awk -v c="$2" '!found && $1 == c { sub("^refs/tags/", "", $2); sub("\\^\\{\\}$", "", $2); print $2; found = 1 }'
}

# Turns the submodule at <path> into a splice, as clone --from-submodule
# does; with <recursive> non-empty, its own submodules too, each in a
# commit of its own after the one above. A submodule inside a splice --
# a folder above with a .splice -- is listed in that folder's
# .gitmodules, as in its upstream.
clone_from_submodule() {
  local path recursive="${2:-}"
  path="$(normalize_path "$1")"
  [[ -n "$path" && "$path" != . && "$path" != /* ]] || die "'$path' isn't a folder inside the repository"
  require_usable_splice_path "$path" "rename the submodule's folder"

  open_repository
  current_branch >/dev/null
  is_splice_path "$path" && die "$path is a splice already"
  require_no_splice_in_progress
  [[ "$(path_mode HEAD "$path")" == 160000 ]] || die "$path: no submodule committed here"
  local above="" gitmodules=.gitmodules base=""
  if above="$(splice_above_in HEAD "$path")"; then
    gitmodules="$above/.gitmodules"
    require_default_upstream "$above"
    base="${SPLICE_URLS[$above]}"
  fi
  local commit name url
  commit="$(git rev-parse "HEAD:$path")"
  name="$(submodule_name "$gitmodules" "${path#"${above:+$above/}"}")"
  [[ -n "$name" ]] || die "$path: $gitmodules in HEAD has no submodule with this path"
  url="$(git config --blob "HEAD:$gitmodules" "submodule.$name.url" 2>/dev/null)" ||
    die "$path: $gitmodules in HEAD has no url for submodule '$name'"
  url="$(resolve_submodule_url "$url" "$base")"

  refuse_lossy_submodule_conversion "$path" "$commit" "$gitmodules"
  local gitdir=""
  [[ ! -e "$path/.git" ]] || gitdir="$(git -C "$path" rev-parse --absolute-git-dir)"
  # The conversion above moved the repositories of nested checkouts to
  # .git/modules/; one cloned into the folder since would be lost.
  [[ -z "$above" || ! -d "$path/.git" ]] ||
    die "$path/.git is a repository of its own, not one in .git/modules/ -- move it away first"

  fetch_new_upstream "$path" "$url" only-fetch
  # A commit no branch has, e.g. one only a tag has, is still there for
  # everyone if upstream serves it by id, as fetch then fetches it.
  if [[ -z "$(git for-each-ref --count=1 --contains "$commit" --format="%(refname)" "$(splice_refs_prefix "$path")" 2>/dev/null)" ]]; then
    git fetch --quiet --no-recurse-submodules --no-tags --no-write-fetch-head -- "$url" "$commit" 2>/dev/null ||
      die "$path: upstream doesn't serve the submodule's commit ${commit:0:7} -- push it to a branch or a tag there first"
  fi
  submodule_defaults "$path" "$gitmodules" "$name" "$commit"
  upstream_has_state_file "$commit" &&
    die "$path: upstream has a $STATE_FILE at its root, which would replace $path/$STATE_FILE -- splice a folder of it instead"
  local inner
  inner="$(upstream_submodule "$commit")"
  [[ -z "$inner" || -n "$recursive" ]] ||
    die "$path: the submodule has a submodule of its own, $inner -- turn it into a splice in its upstream first, or add --recursive to convert it here too"

  # Keys are submodule.<name>.<setting>, and <name> may contain dots.
  local key setting
  while IFS= read -r key; do
    [[ "$key" == "submodule.$name."* ]] || continue
    setting="${key#"submodule.$name."}"
    [[ "$setting" != *.* && "$setting" != path && "$setting" != url && "$setting" != branch ]] || continue
    log_warn "$path: dropping $key from .gitmodules -- a splice has no such setting"
  done < <(git config --blob "HEAD:$gitmodules" --name-only --get-regexp '^submodule\.')

  local blob edited
  blob="$(state_blob "$path" "id=$(new_splice_id "$path" "$url" "$commit")" "commit=$commit" "upstream.$DEFAULT_UPSTREAM.url=$url" "upstream.$DEFAULT_UPSTREAM.default-branch=$SUBMODULE_BRANCH" "upstream.$DEFAULT_UPSTREAM.default-pin=$SUBMODULE_PIN")" || exit 1
  edited="$(mktemp)"
  git cat-file blob "HEAD:$gitmodules" >"$edited"
  git config --file "$edited" --remove-section "submodule.$name"

  if [[ -n "$gitdir" && -z "$above" ]]; then
    # An embedded repository moves to .git/modules/ first, and so do
    # those of its own submodules: removing a checkout's .git then loses
    # nothing.
    git submodule --quiet absorbgitdirs -- "$path"
    gitdir="$(git -C "$path" rev-parse --absolute-git-dir)"
  fi
  [[ -z "$gitdir" ]] || rm -f -- "$path/.git"
  # The monorepo's config names only its own submodules.
  [[ -n "$above" ]] || git config --remove-section "submodule.$name" 2>/dev/null || true
  git rm -q --cached -- ":(top,literal)$path"
  git read-tree --prefix="$path/" "$commit"
  # Writes only the files that are missing, as in a submodule that was
  # never checked out. A file the checks above missed, e.g. one hidden by
  # assume-unchanged, keeps its edit and shows as changed afterwards.
  git ls-files -z --deleted -- ":(top,literal)$path" | git checkout-index -z --stdin
  git update-index -q --refresh >/dev/null || true
  # A commit without files left no folder to write .splice into.
  mkdir -p -- "$path"
  git cat-file blob "$blob" >"$path/$STATE_FILE"
  git add -f -- "$path/$STATE_FILE"
  if [[ -z "$(git config --file "$edited" --list)" ]]; then
    git rm -q -- "$gitmodules"
  else
    cat "$edited" >"$gitmodules"
    git add -- "$gitmodules"
  fi
  rm -f -- "$edited"
  git commit --quiet -m "$(commit_message "splice: clone $path from submodule at ${commit:0:7}")" ||
    die "$path: 'git commit' failed -- the conversion stays staged"
  log_ok "$path: cloned ${commit:0:7} from the submodule"
  if [[ -n "$SUBMODULE_PIN" ]]; then
    local tag
    tag="$(tag_naming "$url" "$commit")" || tag=""
    log_step "$path: pinned at ${commit:0:7}${tag:+, the tag '$tag'}, as $SUBMODULE_PINNED_AS -- pull brings in nothing and push refuses on $(monorepo_default_branch) until it follows a branch: git config --file $(shell_quote "$path/$STATE_FILE") --unset upstream.$DEFAULT_UPSTREAM.default-pin"
  fi
  [[ -z "$gitdir" ]] || log_step "$path: the submodule's repository stays in $gitdir -- remove it once you don't need it"
  [[ -z "$above" ]] ||
    log_step "$above: upstream still has ${path#"$above/"} as a submodule -- 'git splice push $(shell_quote "$above")' turns it into a splice there too"

  [[ -n "$recursive" ]] || return 0
  local entry sub
  # Paths come from the commit, before any conversion below changes HEAD.
  while IFS= read -r -d '' entry; do
    [[ "${entry%% *}" == 160000 ]] || continue
    sub="${entry#*$'\t'}"
    # A subshell each: every conversion discovers the splices anew.
    (clone_from_submodule "$sub" "$recursive") && continue
    # Converted, but one below it wasn't: that one said so.
    [[ "$(path_mode HEAD "$sub")" == 160000 ]] || exit 1
    die "$sub: not converted -- $path and what was converted before stay; fix the above, then run 'git splice clone --from-submodule --recursive $(shell_quote "$sub")'"
  done < <(git ls-tree -r -z HEAD -- ":(top,literal)$path")
}
