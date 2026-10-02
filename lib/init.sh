# Assumes lib/common.sh is already sourced.

usage_init() {
  cat <<'EOF'
usage: git splice init <path> <url>

Makes the existing folder <path> a splice, to be published to <url>: an
empty repository you created for it. Commits <path>/.splice and nothing
else. Your first 'git splice push <path>' then sends the folder's history.

If <url> has commits already, use 'git splice clone --merge <url> <path>'.
EOF
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

  cd_to_repo_root
  require_head_commit
  discover_splices
  local other heads
  is_splice_path "$path" && die "$path is a splice already"
  if other="$(overlapping_splice "$path")"; then
    die "nested splices are not supported: '$path' and '$other' overlap"
  fi
  [[ -n "$(folder_tree HEAD "$path")" ]] ||
    die "$path: no committed folder here -- to splice in an existing repository, use 'git splice clone'"
  [[ ! -e "$path/$STATE_FILE" ]] || die "$path/$STATE_FILE exists, but isn't committed -- remove it or commit it"

  heads="$(git ls-remote --heads -- "$url")" || die "$path: can't reach $url"
  [[ -z "$heads" ]] ||
    die "$url has commits already -- to combine them with $path, use 'git splice clone --merge $(shell_quote "$url") $(shell_quote "$path")'"

  git cat-file blob "$(state_blob "$path" "url=$url")" >"$path/$STATE_FILE"
  git add -- "$path/$STATE_FILE"
  git commit --quiet -m "splice: init $path" -- "$path/$STATE_FILE"
  log_ok "$path: initialized -- 'git splice push $(shell_quote "$path")' publishes it"
}
