# The push rebuild: turns a splice's history in the monorepo into the
# commits its upstream gets. Assumes lib/common.sh is already sourced.
#
# The rebuild is deterministic -- the same history always rebuilds into the
# same commits -- so status can compare it with the upstream branch without
# remembering anything about earlier pushes. See docs/design/README.md.

# Cache: monorepo tree of a splice folder -> that tree without its state
# file. The same folder tree recurs in every commit that doesn't touch it.
declare -gA CONTENT_TREE_CACHE=()

# Sets CONTENT_TREE to the tree of splice <path> in commit <rev>, without
# its state file, or to nothing if the folder doesn't exist there. Sets a
# global rather than printing, so the cache survives: a $(...) call would
# fill it in a subshell.
CONTENT_TREE=""
content_tree() {
  local rev="$1" path="$2" tree entry
  CONTENT_TREE=""
  tree="$(folder_tree "$rev" "$path")"
  [[ -n "$tree" ]] || return 0
  if [[ -z "${CONTENT_TREE_CACHE[$tree]:-}" ]]; then
    if git cat-file -e "$tree:$STATE_FILE" 2>/dev/null; then
      CONTENT_TREE_CACHE[$tree]="$(
        git ls-tree -z "$tree" |
          while IFS= read -r -d '' entry; do
            [[ "${entry#*$'\t'}" == "$STATE_FILE" ]] || printf '%s\0' "$entry"
          done |
          git mktree -z
      )"
    else
      CONTENT_TREE_CACHE[$tree]="$tree"
    fi
  fi
  CONTENT_TREE="${CONTENT_TREE_CACHE[$tree]}"
}

# Prints the newest first-parent commit reachable from <rev> that changed
# <path>'s state file -- the boundary. Every pull, clone and init writes
# such a commit, and rebases and squash merges can't remove all of them.
splice_boundary() {
  local path="$1" rev="${2:-HEAD}"
  git log --first-parent -1 --format=%H "$rev" -- ":(top,literal)$path/$STATE_FILE"
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
# Without a synced commit (after init, before any pull), the whole
# first-parent history is rebuilt from its first commit.
rebuild_splice() {
  local path="$1" rev="${2:-HEAD}"
  local boundary synced prev="" prev_tree="" tree range

  boundary="$(splice_boundary "$path" "$rev")"
  synced=""
  [[ -n "$boundary" ]] && synced="$(splice_config "$path" commit "$boundary")"

  if [[ -n "$synced" ]]; then
    git cat-file -e "$synced^{commit}" 2>/dev/null ||
      die "$path: synced commit ${synced:0:7} isn't available locally -- run 'git splice fetch $path'"
    prev="$synced"
    prev_tree="$(git rev-parse "$synced^{tree}")"
    content_tree "$boundary" "$path"
    tree="$CONTENT_TREE"
    if [[ -n "$tree" && "$tree" != "$prev_tree" ]]; then
      local before parents=()
      before=""
      git rev-parse --verify --quiet "$boundary^1" >/dev/null &&
        before="$(rebuild_splice "$path" "$boundary^1")"
      if [[ -n "$before" ]] && ! git merge-base --is-ancestor "$before" "$synced" 2>/dev/null; then
        parents=("$before" "$synced")
      else
        parents=("$synced")
      fi
      prev="$(copy_commit "$boundary" "$tree" "${parents[@]}")"
      prev_tree="$tree"
    fi
    range="$boundary..$rev"
  else
    range="$rev"
  fi

  rebuild_walk "$path" "$prev" "$range"
}

# Prints the rebuild of splice <path> along <range> (rev-list syntax, e.g.
# "B..HEAD"), on top of upstream commit <start> (nothing: a new root):
# one commit per first-parent commit whose folder differs from the one
# before. A merge in the monorepo becomes one ordinary commit.
rebuild_walk() {
  local path="$1" prev="$2" range="$3" prev_tree="" tree commit
  [[ -n "$prev" ]] && prev_tree="$(git rev-parse "$prev^{tree}")"
  for commit in $(git rev-list --reverse --first-parent "$range" -- ":(top,literal)$path"); do
    content_tree "$commit" "$path"
    tree="$CONTENT_TREE"
    [[ -z "$tree" || "$tree" == "$prev_tree" ]] && continue
    if [[ -n "$prev" ]]; then
      prev="$(copy_commit "$commit" "$tree" "$prev")"
    else
      prev="$(copy_commit "$commit" "$tree")"
    fi
    prev_tree="$tree"
  done
  printf '%s\n' "$prev"
}
