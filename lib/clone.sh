# Assumes lib/common.sh, lib/rebuild.sh, lib/state.sh and lib/fetch.sh are
# already sourced.

usage_clone() {
  cat <<'EOF'
usage: git splice clone [--merge] <url> [<path>]
   or: git splice clone --from-submodule <path>

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
once empty). The commit must be on a branch upstream, and a checkout of
the submodule must be at that commit without changes; clone refuses
otherwise. It asks git status for those changes, so it can't see the ones
hidden by 'git update-index --assume-unchanged' or '--skip-worktree': an
edited file keeps its edit, but a deleted one comes back. Clear these
flags first. Files Git ignores in the checkout stay, and its repository
stays in .git/modules/. Settings in .gitmodules other than path and url
are dropped: a splice syncs with the upstream branch named like the
current branch, not with submodule.<name>.branch.
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
NEW_DEFAULT_BRANCH=""
UPSTREAM_DEFAULT=""
MONOREPO_DEFAULT=""
CONTAINER_DEFAULT=""
fetch_new_upstream() {
  local path="$1" url="$2"
  # Before the fetch: refuses if the splice above leaves it open.
  container_default_branch "$path" >/dev/null
  create_upstream_key "$url"
  SPLICE_UPSTREAM_LISTS[$path]="$DEFAULT_UPSTREAM"
  UPSTREAM_URLS["$path:$DEFAULT_UPSTREAM"]="$url"
  SPLICE_DEFAULT_UPSTREAMS[$path]="$DEFAULT_UPSTREAM"
  use_upstream "$path" "$DEFAULT_UPSTREAM"
  log_step "$path: fetching $url"
  fetch_upstream "$url" "$(splice_refs_prefix "$path")" || die "$path: fetch failed"
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
  parse_args usage_clone "--merge --from-submodule" "$@"
  [[ -z "$ALL_ARG" && -z "$BASE_ARG" ]] || die "clone takes no --all or --base"
  if has_flag --from-submodule; then
    has_flag --merge && die "--from-submodule takes no --merge: the folder gets the submodule's files"
    if [[ ${#PATH_ARGS[@]} -ne 1 ]]; then
      usage_clone >&2
      exit 1
    fi
    clone_from_submodule "${PATH_ARGS[0]}"
    return
  fi
  local merge=""
  has_flag --merge && merge=1
  local url="${PATH_ARGS[0]:-}" path="${PATH_ARGS[1]:-}"
  if [[ -z "$url" || ${#PATH_ARGS[@]} -gt 2 ]]; then
    usage_clone >&2
    exit 1
  fi
  [[ -n "$path" ]] || path="$(default_clone_path "$url")"
  path="$(normalize_path "$path")"
  [[ -n "$path" && "$path" != . && "$path" != /* ]] || die "'$path' isn't a folder inside the repository"
  usable_splice_path "$path" ||
    die "'$path' isn't supported as a splice path yet -- choose another folder name (e.g. no spaces)"

  cd_to_repo_root
  require_head_commit
  discover_splices
  local branch
  branch="$(current_branch)"
  is_splice_path "$path" && die "$path is a splice already"
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"
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
  blob="$(state_blob "$path" "id=$(new_splice_id "$path" "$url" "$target")" "commit=$target" "upstream.$DEFAULT_UPSTREAM.url=$url" "upstream.$DEFAULT_UPSTREAM.default-branch=$default_branch")"
  # The merge base is an empty folder: the two sides share nothing.
  if ! splice_in "$path" "" "" "$target^{tree}" "$blob" \
    "splice: clone $path from $upstream_branch at ${target:0:7}"; then
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

# Prints the name of the submodule at <path> in HEAD's .gitmodules, or
# nothing if none has that path.
submodule_name() {
  local path="$1" entry key
  while IFS= read -r -d '' entry; do
    key="${entry%%$'\n'*}"
    if [[ "$(normalize_path "${entry#*$'\n'}")" == "$path" ]]; then
      key="${key#submodule.}"
      printf '%s\n' "${key%.path}"
      return
    fi
  done < <(git config -z --blob HEAD:.gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null)
}

# Prints submodule URL <url> as `git submodule` reads it: a relative one,
# starting with ./ or ../, is relative to the URL of the monorepo's default
# remote -- the current branch's remote, else origin -- or, without one,
# to the monorepo itself. A remote URL that is a relative path is relative
# to the monorepo's top folder.
resolve_submodule_url() {
  local url="$1" branch remote base
  [[ "$url" == ./* || "$url" == ../* ]] || {
    printf '%s\n' "$url"
    return
  }
  branch="$(git symbolic-ref --quiet --short HEAD || true)"
  remote="$(git config "branch.$branch.remote" 2>/dev/null || echo origin)"
  base="$(git config "remote.$remote.url" 2>/dev/null || git rev-parse --show-toplevel)"
  base="${base%/}"
  [[ "$base" == /* || "$base" == *:* ]] || base="$(git rev-parse --show-toplevel)/$base"
  while :; do
    case "$url" in
      ./*) url="${url#./}" ;;
      ../*)
        url="${url#../}"
        if [[ "$base" == */* ]]; then
          base="${base%/*}"
          # host:/mono.git, scp-like with an absolute path: ../ leaves host:/
          [[ "$base" != *: ]] || base="$base/"
        elif [[ "$base" == *:* ]]; then
          # host:repo.git, scp-like: ../ leaves host:
          base="${base%%:*}:"
        else
          die "can't resolve submodule URL '$1' against '$base'"
        fi
        ;;
      *) break ;;
    esac
  done
  if [[ "$base" == *: || "$base" == */ ]]; then
    printf '%s%s\n' "$base" "$url"
  else
    printf '%s/%s\n' "$base" "$url"
  fi
}

# Dies unless converting the submodule at <path>, committed at <commit>,
# can't lose anything. The conversion writes to the index, .gitmodules,
# the folder and its .splice, and each must be unchanged from HEAD or
# missing. Content is compared, not just what git status says: index
# flags like assume-unchanged hide edits from it.
refuse_lossy_submodule_conversion() {
  local path="$1" commit="$2"
  git diff --cached --quiet ||
    die "$path: there are staged changes -- commit or unstage them first, the conversion commits only its own"
  # HEAD has a .gitmodules: it names the submodule.
  if [[ ! -e .gitmodules && ! -L .gitmodules ]] ||
    [[ "$(git hash-object -- .gitmodules)" != "$(git rev-parse HEAD:.gitmodules)" ]]; then
    die "$path: .gitmodules has uncommitted changes -- commit or discard them first"
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

clone_from_submodule() {
  local path
  path="$(normalize_path "$1")"
  [[ -n "$path" && "$path" != . && "$path" != /* ]] || die "'$path' isn't a folder inside the repository"
  usable_splice_path "$path" ||
    die "'$path' isn't supported as a splice path yet -- rename the submodule's folder (e.g. no spaces)"

  cd_to_repo_root
  require_head_commit
  current_branch >/dev/null
  discover_splices
  is_splice_path "$path" && die "$path is a splice already"
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"
  [[ "$(path_mode HEAD "$path")" == 160000 ]] || die "$path: no submodule committed here"
  local commit name url
  commit="$(git rev-parse "HEAD:$path")"
  name="$(submodule_name "$path")"
  [[ -n "$name" ]] || die "$path: .gitmodules in HEAD has no submodule with this path"
  url="$(git config --blob HEAD:.gitmodules "submodule.$name.url" 2>/dev/null)" ||
    die "$path: .gitmodules in HEAD has no url for submodule '$name'"
  url="$(resolve_submodule_url "$url")"

  refuse_lossy_submodule_conversion "$path" "$commit"
  local gitdir=""
  [[ ! -e "$path/.git" ]] || gitdir="$(git -C "$path" rev-parse --absolute-git-dir)"

  fetch_new_upstream "$path" "$url"
  if ! git cat-file -e "$commit^{commit}" 2>/dev/null ||
    [[ -z "$(git for-each-ref --count=1 --contains "$commit" --format="%(refname)" "$(splice_refs_prefix "$path")")" ]]; then
    die "$path: no upstream branch has the submodule's commit ${commit:0:7} -- push it there first"
  fi
  upstream_has_state_file "$commit" &&
    die "$path: upstream has a $STATE_FILE at its root, which would replace $path/$STATE_FILE -- splice a folder of it instead"
  local inner
  inner="$(upstream_submodule "$commit")"
  [[ -z "$inner" ]] ||
    die "$path: the submodule has a submodule of its own, $inner -- turn it into a splice in its upstream first"

  # Keys are submodule.<name>.<setting>, and <name> may contain dots.
  local key setting
  while IFS= read -r key; do
    [[ "$key" == "submodule.$name."* ]] || continue
    setting="${key#"submodule.$name."}"
    [[ "$setting" != *.* && "$setting" != path && "$setting" != url ]] || continue
    log_warn "$path: dropping $key from .gitmodules -- a splice has no such setting"
  done < <(git config --blob HEAD:.gitmodules --name-only --get-regexp '^submodule\.')

  local blob gitmodules
  blob="$(state_blob "$path" "id=$(new_splice_id "$path" "$url" "$commit")" "commit=$commit" "upstream.$DEFAULT_UPSTREAM.url=$url" "upstream.$DEFAULT_UPSTREAM.default-branch=$NEW_DEFAULT_BRANCH")"
  gitmodules="$(mktemp)"
  git cat-file blob HEAD:.gitmodules >"$gitmodules"
  git config --file "$gitmodules" --remove-section "submodule.$name"

  if [[ -n "$gitdir" ]]; then
    # An embedded repository moves to .git/modules/ first: removing the
    # checkout's .git then loses nothing.
    [[ -d "$path/.git" ]] && git submodule --quiet absorbgitdirs -- "$path"
    gitdir="$(git -C "$path" rev-parse --absolute-git-dir)"
    rm -f -- "$path/.git"
  fi
  git config --remove-section "submodule.$name" 2>/dev/null || true
  git rm -q --cached -- ":(top,literal)$path"
  git read-tree --prefix="$path/" "$commit"
  # Writes only the files that are missing, as in a submodule that was
  # never checked out. A file the checks above missed, e.g. one hidden by
  # assume-unchanged, keeps its edit and shows as changed afterwards.
  git ls-files -z --deleted -- ":(top,literal)$path" | git checkout-index -z --stdin
  git update-index -q --refresh >/dev/null || true
  git cat-file blob "$blob" >"$path/$STATE_FILE"
  git add -f -- "$path/$STATE_FILE"
  if [[ -z "$(git config --file "$gitmodules" --list)" ]]; then
    git rm -q -- .gitmodules
  else
    cat "$gitmodules" >.gitmodules
    git add -- .gitmodules
  fi
  rm -f -- "$gitmodules"
  git commit --quiet -m "splice: clone $path from submodule at ${commit:0:7}"
  log_ok "$path: cloned ${commit:0:7} from the submodule"
  [[ -z "$gitdir" ]] || log_step "$path: the submodule's repository stays in $gitdir -- remove it once you don't need it"
}
