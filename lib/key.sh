# Assumes lib/common.sh is already sourced.

usage_key() {
  cat <<'EOF'
usage: git splice key <path> [<new-key>]

Prints the key splice <path>'s upstream has in this repository: its
fetched branches are refs/splices/<key>/<branch>, e.g. for
'git log splices/<key>/main'. With <new-key>, renames the key and moves
its refs along.

A key belongs to an upstream URL, so splices with the same URL share it.
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
  url="${URL_OF_KEY[$old]}"
  upstream_key_taken "$new" && die "key '$new' is taken -- 'git config --local --get-regexp ^splice\\.' lists the keys"
  git for-each-ref --format='%(refname) %(objectname)' "refs/splices/$old/" |
    while read -r ref object; do
      printf 'create refs/splices/%s/%s %s\n' "$new" "${ref#"refs/splices/$old/"}" "$object"
      printf 'delete %s %s\n' "$ref" "$object"
    done | git update-ref --stdin || die "couldn't move the refs of key '$old'"
  git config --local --rename-section "splice.$old" "splice.$new" ||
    die "moved the refs to refs/splices/$new/, but couldn't rename splice.$old in the repository's config -- rename it by hand (git config --local --rename-section splice.$old splice.$new)"
  unlock_upstream_keys
  URL_OF_KEY[$new]="$url"
  unset 'URL_OF_KEY[$old]'
  KEY_OF_URL[$url]="$new"
}

cmd_key() {
  case "${1:-}" in
    -h | --help)
      usage_key
      return
      ;;
  esac
  [[ $# -eq 1 || $# -eq 2 ]] || {
    usage_key >&2
    exit 1
  }
  local path="${1%/}" new="${2:-}"
  cd_to_repo_root
  require_head_commit
  discover_splices
  is_splice_path "$path" || die "not a splice: $path"
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
