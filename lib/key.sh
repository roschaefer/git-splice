# Assumes lib/common.sh is already sourced.

usage_key() {
  cat <<'EOF'
NAME
    git-splice-key - Print or rename an upstream's key

SYNOPSIS
    git splice key [--upstream <name>] <path> [<new-key>]

DESCRIPTION
    Prints the key splice <path>'s upstream has in this repository: its
    fetched branches are refs/splices/<key>/heads/<branch>, e.g. for
    'git log splices/<key>/heads/main'. With <new-key>, renames the key and
    moves its refs along.

    --upstream names the upstream, as <path>/.splice does in
    [upstream "<name>"]. Without it, the splice's default upstream.

    A key belongs to an upstream URL, so splices with the same URL share it.
    Renaming it also renames it in the tracked upstream branches,
    branch.<branch>.splice = <key>:<name>.
    The first fetch of an upstream records its key in the repository's config,
    as splice.<key>.url, from the end of its URL: lib for
    https://github.com/x/lib.git, or x-lib, then github.com-x-lib, if that's
    taken. A key is lower-case letters, digits, ".", "_" and "-", at most 64
    long.
EOF
}

# Renames upstream key <old> to <new>: its refs, in one transaction, then
# its entry in the repository's config. Under the lock create_upstream_key
# takes, so neither picks a key the other is taking.
rename_upstream_key() {
  local old="$1" new="$2" url
  valid_upstream_key "$new" ||
    die "'$new' isn't a valid key -- use lower-case letters, digits, '.', '_' and '-', at most 64, starting and ending with a letter or digit"
  lock_upstream_keys
  reload_upstream_keys
  # Another command may have renamed it since this one read the config.
  [[ -n "${URL_OF_KEY[$old]:-}" ]] || die "key '$old' is gone -- run 'git splice key' again"
  url="${URL_OF_KEY[$old]}"
  upstream_key_taken "$new" && die "key '$new' is taken -- 'git config --local --get-regexp ^splice\\.' lists the keys"
  git for-each-ref --format='%(refname) %(objectname)' "refs/splices/$old/" |
    while read -r ref object; do
      printf 'create refs/splices/%s/%s %s\n' "$new" "${ref#"refs/splices/$old/"}" "$object"
      printf 'delete %s %s\n' "$ref" "$object"
    done | git update-ref --stdin || die "couldn't move the refs of key '$old'"
  git config --local --rename-section "splice.$old" "splice.$new" ||
    die "moved the refs to refs/splices/$new/, but couldn't rename splice.$old in the repository's config -- rename it by hand (git config --local --rename-section splice.$old splice.$new)"
  rename_tracked_branches "$old" "$new"
  unlock_upstream_keys
  URL_OF_KEY[$new]="$url"
  unset 'URL_OF_KEY[$old]'
  KEY_OF_URL[$url]="$new"
}

# Renames upstream key <old> to <new> in every upstream branch tracked
# on a monorepo branch (see TRACKED_BRANCHES).
rename_tracked_branches() {
  local old="$1" new="$2" name value
  while read -r name value; do
    [[ "$value" == "$old:"* ]] || continue
    git config --local --fixed-value --replace-all "$name" "$new:${value#"$old:"}" "$value" ||
      die "couldn't rename key '$old' in $name -- rename it by hand (git config --local --fixed-value --replace-all $name $(shell_quote "$new:${value#"$old:"}") $(shell_quote "$value"))"
  done < <(git config --local --get-regexp '^branch\..*\.splice$' 2>/dev/null || true)
  TRACKED_FOR=""
}

cmd_key() {
  parse_args usage_key "--upstream" "$@"
  require_args usage_key key 1 2
  local path new="${PATH_ARGS[1]:-}"
  path="$(normalize_path "${PATH_ARGS[0]}")"
  open_repository
  require_splice "$path"
  use_upstreams "$UPSTREAM_ARG" "$path"
  local key="${SPLICE_KEYS[$path]}"
  [[ -n "$key" ]] || die "$path: its upstream has no key yet -- 'git splice fetch $(shell_quote "$path")' records one"
  if [[ -z "$new" ]]; then
    printf '%s\n' "$key"
  elif [[ "$new" == "$key" ]]; then
    log_ok "$path: key is '$key' already"
  else
    rename_upstream_key "$key" "$new"
    log_ok "$path: renamed key '$key' to '$new'"
  fi
}
