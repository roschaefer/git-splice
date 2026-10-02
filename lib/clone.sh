# Assumes lib/common.sh, lib/rebuild.sh and lib/state.sh are already sourced.

usage_clone() {
  cat <<'EOF'
usage: git splice clone [--merge] <url> [<path>]

Splices an existing upstream repository into <path> (default: the
repository's name), as one ordinary commit with a new <path>/.splice.

The upstream branch is the one named like the current branch, else the
upstream's default branch; your first push then creates the missing
branch. If the upstream's default branch is named differently from the
monorepo's, .splice records it as default-branch.

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
    die "'$path' can't be part of a Git ref name, so it can't be a splice -- choose another folder name (e.g. no spaces)"

  cd_to_repo_root
  require_head_commit
  discover_splices
  local branch other
  branch="$(current_branch)"
  is_splice_path "$path" && die "$path is a splice already"
  if other="$(overlapping_splice "$path")"; then
    die "nested splices are not supported: '$path' and '$other' overlap"
  fi
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"

  log_step "$path: fetching $url"
  git fetch --quiet --no-tags --no-write-fetch-head --prune -- "$url" "+refs/heads/*:refs/splices/$path/*" ||
    die "$path: fetch failed"
  splice_fetched "$path" || die "$url has no branches yet -- to publish $path there, use 'git splice init $(shell_quote "$path") $(shell_quote "$url")'"

  # Map the monorepo's default branch to the upstream's, if they differ.
  local upstream_default monorepo_default default_branch=""
  upstream_default="$(upstream_default_branch "$url")"
  monorepo_default="$(monorepo_default_branch)"
  if [[ -n "$upstream_default" && -n "$monorepo_default" && "$upstream_default" != "$monorepo_default" ]]; then
    default_branch="$upstream_default"
  fi

  local upstream_branch="$branch"
  [[ -n "$default_branch" && "$branch" == "$monorepo_default" ]] && upstream_branch="$default_branch"
  if ! git show-ref --verify --quiet "$(splice_ref "$path" "$upstream_branch")"; then
    [[ -n "$upstream_default" ]] || die "$path: upstream has no '$upstream_branch' branch and no default branch"
    log_step "$path: upstream has no '$upstream_branch' branch -- using '$upstream_default'; your first push creates '$upstream_branch'"
    upstream_branch="$upstream_default"
  fi

  local target local_folder
  target="$(git rev-parse "$(splice_ref "$path" "$upstream_branch")^{commit}")"
  upstream_state_file_free "$target" ||
    die "$path: upstream has a $STATE_FILE at its root, which would collide with the splice's own"
  local_folder="$(folder_tree HEAD "$path")"
  if [[ -n "$local_folder" && "$local_folder" != "$(git rev-parse "$target^{tree}")" && -z "$merge" ]]; then
    die "$path exists and differs from '$upstream_branch' upstream -- '--merge' keeps both, and every file that differs becomes a conflict to resolve"
  fi

  local blob
  blob="$(state_blob "$path" "url=$url" "commit=$target" "default-branch=$default_branch")"
  # The merge base is an empty folder: the two sides share nothing.
  if ! splice_in "$path" "" "" "$target^{tree}" "$blob" \
    "splice: clone $path from $upstream_branch at ${target:0:7}"; then
    log_err "$path: clone failed"
    exit 1
  fi
  log_ok "$path: cloned ${target:0:7} from $upstream_branch"
}
