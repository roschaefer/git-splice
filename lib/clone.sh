# Assumes lib/common.sh, lib/rebuild.sh, lib/state.sh and lib/fetch.sh are
# already sourced.

usage_clone() {
  cat <<'EOF'
usage: git splice clone [--merge] <url> [<path>]

Splices an existing upstream repository into <path> (default: the
repository's name), as one ordinary commit with a new <path>/.splice.

The upstream branch is the one named like the current branch, else the
upstream's default branch; your first push then creates the missing
branch. If the upstream's default branch is named differently from the
monorepo's, .splice records it as default-branch. Inside another splice,
it's compared with that splice's default branch instead, and on the
monorepo's default branch, that's the upstream branch: the monorepo's
branch name isn't tried.

If <path> already exists with exactly the upstream's content, clone only
adds .splice. If its content differs, clone refuses, unless --merge is
given: then every file that differs becomes a conflict to resolve, and
nothing is lost. Resolve it and run 'git commit'.
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

cmd_clone() {
  parse_args usage_clone "--merge" "$@"
  local merge=""
  has_flag --merge && merge=1
  [[ -z "$ALL_ARG" && -z "$BASE_ARG" ]] || die "clone takes no --all or --base"
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
  if git cat-file -e "HEAD:$path" 2>/dev/null && [[ -z "$(folder_tree HEAD "$path")" ]]; then
    die "$path is a file, not a folder"
  fi

  create_upstream_key "$url"
  SPLICE_URLS[$path]="$url"
  SPLICE_UPSTREAM_NAMES[$path]="$DEFAULT_UPSTREAM"
  SPLICE_KEYS[$path]="$UPSTREAM_KEY"
  log_step "$path: fetching $url"
  fetch_upstream "$url" "$(splice_refs_prefix "$path")" || die "$path: fetch failed"
  splice_fetched "$path" || die "$url has no branches yet -- to publish $path there, use 'git splice init $(shell_quote "$path") $(shell_quote "$url")'"

  # Map the monorepo's default branch to the upstream's, if it differs from
  # the default branch of what the splice lives in: the splice above it,
  # or the monorepo (container_default_branch).
  local upstream_default monorepo_default container_default default_branch=""
  upstream_default="$(upstream_default_branch "$url")"
  monorepo_default="$(monorepo_default_branch)"
  container_default="$(container_default_branch "$path")"
  if [[ -n "$upstream_default" && -z "$monorepo_default" && "$upstream_default" != "$branch" ]]; then
    # Without the monorepo's default branch, the splice couldn't map it to
    # upstream's: it would look for '$branch' upstream from the start, even
    # inside a splice whose default branch is known.
    die "$path: upstream's default branch is '$upstream_default', and the monorepo's can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"
  elif [[ -n "$upstream_default" && -n "$container_default" && "$upstream_default" != "$container_default" ]]; then
    default_branch="$upstream_default"
  fi

  local upstream_branch="$branch"
  [[ -n "$monorepo_default" && "$branch" == "$monorepo_default" ]] && upstream_branch="${default_branch:-$container_default}"
  if ! git show-ref --verify --quiet "$(splice_ref "$path" "$upstream_branch")"; then
    # On the monorepo's default branch inside a splice, '$upstream_branch'
    # is the splice above's default branch. The monorepo's branch name says
    # nothing about this upstream then, so it isn't tried instead.
    [[ -n "$upstream_default" ]] || die "$path: upstream has no '$upstream_branch' branch and names no default branch"
    log_step "$path: upstream has no '$upstream_branch' branch -- using '$upstream_default'; your first push creates '$upstream_branch'"
    upstream_branch="$upstream_default"
  fi

  local target local_folder
  target="$(git rev-parse "$(splice_ref "$path" "$upstream_branch")^{commit}")"
  upstream_has_state_file "$target" &&
    die "$path: upstream has a $STATE_FILE at its root, which would replace $path/$STATE_FILE -- splice a folder of it instead"
  local_folder="$(folder_tree HEAD "$path")"
  if [[ -n "$local_folder" && "$local_folder" != "$(git rev-parse "$target^{tree}")" && -z "$merge" ]]; then
    die "$path exists and differs from '$upstream_branch' upstream -- '--merge' keeps both, and every file that differs becomes a conflict to resolve"
  fi

  local blob
  blob="$(state_blob "$path" "commit=$target" "default-branch=$default_branch" "upstream.$DEFAULT_UPSTREAM.url=$url")"
  # The merge base is an empty folder: the two sides share nothing.
  if ! splice_in "$path" "" "" "$target^{tree}" "$blob" \
    "splice: clone $path from $upstream_branch at ${target:0:7}"; then
    log_err "$path: clone failed"
    exit 1
  fi
  log_ok "$path: cloned ${target:0:7} from $upstream_branch"
}
