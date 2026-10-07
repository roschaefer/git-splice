# The push rebuild: turns a splice's history in the monorepo into the
# commits its upstream gets. Assumes lib/common.sh is already sourced.
#
# The rebuild is deterministic -- the same history always rebuilds into the
# same commits -- so status can compare it with the upstream branch without
# remembering anything about earlier pushes. See docs/design/README.md.

# Cache: monorepo tree of a splice folder -> that tree without its state
# file. The same folder tree recurs in every commit that doesn't touch it.
declare -gA CONTENT_TREE_CACHE=()

# Sets CONTENT_TREE to folder tree <tree> without its state file. Sets a
# global rather than printing, so the cache survives: a $(...) call would
# fill it in a subshell.
CONTENT_TREE=""
strip_state_tree() {
  local tree="$1" entry entries=() stripped=() found=""
  if [[ -z "${CONTENT_TREE_CACHE[$tree]:-}" ]]; then
    # NUL-separated throughout: a file name may contain anything but NUL.
    mapfile -d '' entries < <(git ls-tree -z "$tree")
    for entry in "${entries[@]}"; do
      if [[ "${entry#*$'\t'}" == "$STATE_FILE" ]]; then
        found=1
      else
        stripped+=("$entry")
      fi
    done
    if [[ -n "$found" && ${#stripped[@]} -eq 0 ]]; then
      # Only the state file: the folder is empty upstream. printf would
      # still print one NUL, which mktree refuses.
      CONTENT_TREE_CACHE[$tree]="$(git mktree </dev/null)"
    elif [[ -n "$found" ]]; then
      CONTENT_TREE_CACHE[$tree]="$(printf '%s\0' "${stripped[@]}" | git mktree -z)"
    else
      CONTENT_TREE_CACHE[$tree]="$tree"
    fi
  fi
  CONTENT_TREE="${CONTENT_TREE_CACHE[$tree]}"
}

# Sets CONTENT_TREE to the tree of splice <path> in commit <rev>, without
# its state file, or to nothing if the folder doesn't exist there.
content_tree() {
  local tree
  CONTENT_TREE=""
  tree="$(folder_tree "$1" "$2")"
  [[ -n "$tree" ]] || return 0
  strip_state_tree "$tree"
}

# Prints the newest first-parent commit reachable from <rev> that changed
# <path>'s state file -- the boundary. Every pull, clone and init writes
# such a commit, and rebases and squash merges can't remove all of them.
splice_boundary() {
  local path="$1" rev="${2:-HEAD}"
  git log --first-parent -1 --format=%H "$rev" -- ":(top,literal)$path/$STATE_FILE"
}

# Prints the identity of splice <path> in commit <rev>: a hash of the
# upstream URLs its state file names, sorted. Nothing if there's no state
# file. As in load_splice_upstream, the old format's splice.url counts
# only if no upstream has a URL, so converting it keeps the identity, and
# a leftover one doesn't change it. NUL-delimited, since a URL may
# contain a newline.
splice_identity() {
  local path="$1" rev="$2" record urls=() old_urls=()
  while IFS= read -r -d '' record; do
    # Each record is <key>, a newline, and the value.
    [[ "$record" == *$'\n'?* ]] || continue
    case "${record%%$'\n'*}" in
      upstream.*.url) urls+=("${record#*$'\n'}") ;;
      splice.url) old_urls+=("${record#*$'\n'}") ;;
    esac
  done < <(git config --blob "$rev:$path/$STATE_FILE" -z --get-regexp '^(upstream\..*|splice)\.url$' 2>/dev/null)
  [[ ${#urls[@]} -gt 0 ]] || urls=("${old_urls[@]}")
  [[ ${#urls[@]} -gt 0 ]] || return 0
  printf '%s\0' "${urls[@]}" | sort -z | git hash-object --stdin
}

# Prints the first-parent commit reachable from <rev> where the splice at
# <path> in <rev> was mounted: the newest one whose first parent had no
# state file at <path>, or one naming other upstreams. Nothing if <path>
# isn't a splice in <rev>. Only the history from there on is this
# splice's: before, the folder was no splice, or another one.
splice_mount() {
  local path="$1" rev="${2:-HEAD}" identity commit
  identity="$(splice_identity "$path" "$rev")"
  [[ -n "$identity" ]] || return 0
  while read -r commit; do
    if ! git rev-parse --verify --quiet "$commit^1" >/dev/null ||
      [[ "$(splice_identity "$path" "$commit^1")" != "$identity" ]]; then
      printf '%s\n' "$commit"
      return
    fi
  done < <(git log --first-parent --format=%H "$rev" -- ":(top,literal)$path/$STATE_FILE")
}

# Prints a new commit with tree <tree> and parents <parent>... that copies
# author and committer -- names, emails and dates -- and the message of
# monorepo commit <source>, the way `git subtree split` does. Never signed:
# a signature would make the result differ from run to run.
copy_commit() {
  local source="$1" tree="$2" parent parents=()
  shift 2
  for parent in "$@"; do
    parents+=(-p "$parent")
  done
  local an ae ad cn ce cd
  {
    IFS= read -r an
    IFS= read -r ae
    IFS= read -r ad
    IFS= read -r cn
    IFS= read -r ce
    IFS= read -r cd
  } < <(git log -1 --no-show-signature --pretty=format:'%an%n%ae%n%aD%n%cn%n%ce%n%cD%n' "$source")
  # --pretty=format: has no trailing newline, unlike --format= (tformat),
  # so the message comes out byte for byte as split copies it.
  git log -1 --no-show-signature --pretty=format:%B "$source" |
    GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" GIT_AUTHOR_DATE="$ad" \
      GIT_COMMITTER_NAME="$cn" GIT_COMMITTER_EMAIL="$ce" GIT_COMMITTER_DATE="$cd" \
      git commit-tree --no-gpg-sign "$tree" "${parents[@]}"
}

# Prints the upstream commit that represents splice <path> as of monorepo
# commit <rev> (default HEAD), or nothing if the splice has no content yet.
#
#   1. B is the boundary (splice_boundary) and U the synced commit recorded
#      there. If B's folder equals U, the rebuild starts at U.
#   2. If it differs -- a pull merged local changes in, or a squash merge
#      mixed local edits into the commit that changed the state file -- B
#      is rebuilt as a commit with B's folder, whose parents are what the
#      rebuild had before B (rebuilt from B's first parent, recursively)
#      and U. Local commits that were never pushed keep their own identity.
#   3. Then one commit per first-parent commit after B whose folder
#      differs from the one before. A merge in the monorepo becomes one
#      ordinary commit.
# Without a synced commit (after init, before any pull), the rebuild
# starts at the mount (splice_mount), as a root commit with the folder as
# it was then. Nothing from before the mount is published, with or
# without a synced commit: the folder was no splice then, or another one,
# and its history may hold what was removed before it became this splice.
rebuild_splice() {
  local path="$1" rev="${2:-HEAD}"
  local boundary synced prev="" prev_tree="" tree range start

  boundary="$(splice_boundary "$path" "$rev")"
  synced=""
  [[ -n "$boundary" ]] && synced="$(splice_config "$path" commit "$boundary")"

  if [[ -n "$synced" ]] && ! git cat-file -e "$synced^{commit}" 2>/dev/null; then
    # push --force sets REBUILD_WITHOUT_SYNCED: the upstream no longer has
    # the synced commit, and the monorepo's side replaces its history
    # anyway, so it's rebuilt as if the splice had no synced commit.
    [[ -n "${REBUILD_WITHOUT_SYNCED:-}" ]] ||
      die "$path: synced commit ${synced:0:7} isn't available locally -- run 'git splice fetch $path'"
    synced=""
  fi

  if [[ -n "$synced" ]]; then
    prev="$synced"
    prev_tree="$(git rev-parse "$synced^{tree}")"
    content_tree "$boundary" "$path"
    tree="$CONTENT_TREE"
    if [[ -n "$tree" && "$tree" != "$prev_tree" ]]; then
      local before parents=()
      before=""
      # Unless B is the mount: what came before isn't this splice's.
      git rev-parse --verify --quiet "$boundary^1" >/dev/null &&
        [[ "$(splice_identity "$path" "$boundary^1")" == "$(splice_identity "$path" "$boundary")" ]] &&
        before="$(rebuild_splice "$path" "$boundary^1")"
      if [[ -z "$before" ]] || git merge-base --is-ancestor "$before" "$synced"; then
        # Nothing unpushed before B: B's changes go on top of U.
        parents=("$synced")
      elif git merge-base --is-ancestor "$synced" "$before"; then
        # What came before already contains U, e.g. B only changed the
        # state file: continue from there.
        parents=("$before")
      else
        # A pull merged a divergence: join both sides, as git pull would.
        parents=("$before" "$synced")
      fi
      if [[ ${#parents[@]} -eq 1 && "$tree" == "$(git rev-parse "${parents[0]}^{tree}")" ]]; then
        prev="${parents[0]}"
      else
        prev="$(copy_commit "$boundary" "$tree" "${parents[@]}")"
      fi
      prev_tree="$tree"
    fi
    range="$boundary..$rev"
  else
    start="$(splice_mount "$path" "$rev")"
    [[ -n "$start" ]] || return 0
    range="$rev"
    git rev-parse --verify --quiet "$start^1" >/dev/null && range="$start^1..$rev"
  fi

  rebuild_walk "$path" "$prev" "$range"
}

# Prints the rebuild of splice <path> along <range> (rev-list syntax, e.g.
# "B..HEAD"), on top of upstream commit <start> (nothing: a new root):
# one commit per first-parent commit whose folder differs from the one
# before. A merge in the monorepo becomes one ordinary commit.
#
# Each commit is copied like copy_commit does, but the metadata of all of
# them comes from one `git log`, and their folder trees from one `git
# cat-file --batch-check`: the rebuild spawns about one process per commit
# instead of eight.
rebuild_walk() {
  local path="$1" prev="$2" range="$3" prev_tree="" i
  [[ -n "$prev" ]] && prev_tree="$(git rev-parse "$prev^{tree}")"

  local -a hashes=() authors=() emails=() dates=() cnames=() cemails=() cdates=() messages=()
  local hash an ae ad cn ce cd message
  # Every field ends with a NUL; tformat adds a newline after each commit,
  # which then starts the next hash.
  while IFS= read -r -d '' hash && IFS= read -r -d '' an && IFS= read -r -d '' ae &&
    IFS= read -r -d '' ad && IFS= read -r -d '' cn && IFS= read -r -d '' ce &&
    IFS= read -r -d '' cd && IFS= read -r -d '' message; do
    hashes+=("${hash#$'\n'}")
    authors+=("$an")
    emails+=("$ae")
    dates+=("$ad")
    cnames+=("$cn")
    cemails+=("$ce")
    cdates+=("$cd")
    messages+=("$message")
  done < <(git log --reverse --first-parent --no-show-signature \
    --pretty=tformat:'%H%x00%an%x00%ae%x00%aD%x00%cn%x00%ce%x00%cD%x00%B%x00' \
    "$range" -- ":(top,literal)$path")

  if [[ ${#hashes[@]} -eq 0 ]]; then
    printf '%s\n' "$prev"
    return
  fi

  local -a folders=()
  local object type
  while read -r object type _; do
    [[ "$type" == tree ]] || object=""
    folders+=("$object")
  done < <(printf "%s:$path\n" "${hashes[@]}" | git cat-file --batch-check='%(objectname) %(objecttype)')

  local parents=()
  for i in "${!hashes[@]}"; do
    [[ -n "${folders[$i]}" ]] || continue
    strip_state_tree "${folders[$i]}"
    [[ "$CONTENT_TREE" == "$prev_tree" ]] && continue
    parents=()
    [[ -n "$prev" ]] && parents=(-p "$prev")
    # printf '%s', not <<<, which would add a newline to the message.
    prev="$(printf '%s' "${messages[$i]}" |
      GIT_AUTHOR_NAME="${authors[$i]}" GIT_AUTHOR_EMAIL="${emails[$i]}" GIT_AUTHOR_DATE="${dates[$i]}" \
        GIT_COMMITTER_NAME="${cnames[$i]}" GIT_COMMITTER_EMAIL="${cemails[$i]}" GIT_COMMITTER_DATE="${cdates[$i]}" \
        git commit-tree --no-gpg-sign "$CONTENT_TREE" "${parents[@]}")"
    prev_tree="$CONTENT_TREE"
  done
  printf '%s\n' "$prev"
}
