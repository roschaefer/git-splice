# Assumes lib/common.sh is already sourced.

usage_init() {
  cat <<'EOF'
usage: git splice init <path> <url>

Makes the existing folder <path> a splice, to be published to <url>: an
empty repository you created for it. Commits <path>/.splice and nothing
else. Your first 'git splice push <path>' then starts the upstream with
that commit, the folder as it is now, followed by any commits after it.
The folder's earlier history stays in the monorepo.

If <url> has commits already, use 'git splice clone --merge <url> <path>'.
EOF
}

# Prints the branch the HEAD of empty repository <url> names, e.g.
# "master". ls-remote shows nothing for an empty repository, but a clone
# learns its unborn HEAD -- and there is nothing to download.
empty_upstream_default_branch() {
  local tmp name=""
  tmp="$(mktemp -d)"
  if git clone --quiet --bare --no-tags -- "$1" "$tmp/probe" 2>/dev/null; then
    name="$(git -C "$tmp/probe" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  fi
  rm -rf "$tmp"
  printf '%s\n' "$name"
}

cmd_init() {
  parse_args usage_init "" "$@"
  [[ -z "$ALL_ARG" && -z "$BASE_ARG" ]] || die "init takes no --all or --base"
  local path="${PATH_ARGS[0]:-}" url="${PATH_ARGS[1]:-}"
  if [[ -z "$path" || -z "$url" || ${#PATH_ARGS[@]} -gt 2 ]]; then
    usage_init >&2
    exit 1
  fi
  path="$(normalize_path "$path")"
  usable_splice_path "$path" ||
    die "'$path' isn't supported as a splice path yet -- rename the folder (e.g. no spaces)"

  cd_to_repo_root
  current_branch >/dev/null
  require_head_commit
  splice_in_progress && die "a cherry-pick or merge is in progress -- conclude it first"
  discover_splices
  local heads
  is_splice_path "$path" && die "$path is a splice already"
  [[ -n "$(folder_tree HEAD "$path")" ]] ||
    die "$path: no committed folder here -- to splice in an existing repository, use 'git splice clone'"
  [[ ! -e "$path/$STATE_FILE" && ! -L "$path/$STATE_FILE" ]] || die "$path/$STATE_FILE exists, but isn't committed -- remove it or commit it"

  heads="$(git ls-remote --heads -- "$url")" || die "$path: can't reach $url"
  [[ -z "$heads" ]] ||
    die "$url has commits already -- to combine them with $path, use 'git splice clone --merge $(shell_quote "$url") $(shell_quote "$path")'"

  # Map the monorepo's default branch to the upstream's, as clone does.
  # An empty repository has no branch yet, but its HEAD still names one.
  local upstream_default container_default default_branch=""
  upstream_default="$(empty_upstream_default_branch "$url")"
  container_default="$(container_default_branch "$path")"
  if [[ -n "$upstream_default" && -n "$container_default" && "$upstream_default" != "$container_default" ]]; then
    default_branch="$upstream_default"
  elif [[ -n "$upstream_default" && -z "$container_default" && "$upstream_default" != "$(current_branch)" ]]; then
    die "$path: upstream's default branch is '$upstream_default', and the monorepo's can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"
  fi

  # The upstream is empty, so refs fetched from it before name branches
  # it no longer has.
  upstream_key "$url"
  if [[ -n "$UPSTREAM_KEY" ]]; then
    git for-each-ref --format='delete %(refname)' "refs/splices/$UPSTREAM_KEY/" | git update-ref --stdin
  fi
  git cat-file blob "$(state_blob "$path" "default-branch=$default_branch" "upstream.$DEFAULT_UPSTREAM.url=$url")" >"$path/$STATE_FILE"
  # -f: an ignore rule matching .splice mustn't stop it, it's committed
  # by definition.
  git add -f -- "$path/$STATE_FILE"
  git commit --quiet -m "splice: init $path" -- "$path/$STATE_FILE"
  log_ok "$path: initialized -- 'git splice push $(shell_quote "$path")' publishes it"
}
