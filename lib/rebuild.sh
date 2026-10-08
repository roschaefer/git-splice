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

# Succeeds if the state file at <path> in commit <a> and the one at
# <path_b> (default: <path>) in commit <b> are the same splice: they have
# the same splice.id. If either has none, from before ids, they're
# compared by their upstream URLs instead. Fails if either commit has no
# state file there.
same_splice() {
  local path="$1" a="$2" b="$3" path_b="${4:-$1}" id_a id_b urls_a
  id_a="$(splice_config "$path" id "$a")"
  id_b="$(splice_config "$path_b" id "$b")"
  if [[ -n "$id_a" && -n "$id_b" ]]; then
    [[ "$id_a" == "$id_b" ]]
    return
  fi
  urls_a="$(splice_url_identity "$path" "$a")"
  [[ -n "$urls_a" && "$urls_a" == "$(splice_url_identity "$path_b" "$b")" ]]
}

# Prints a hash of the upstream URLs that splice <path>'s state file names
# in commit <rev>, sorted: the identity of a splice from before ids.
# Nothing if there's no state file. As in load_splice_upstream, the old
# format's splice.url counts only if no upstream has a URL, so converting
# it keeps the identity, and a leftover one doesn't change it.
# NUL-delimited, since a URL may contain a newline.
splice_url_identity() {
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
# state file at <path>, or another splice's (same_splice). Nothing if
# <path> isn't a splice in <rev>. Only the history from there on is this
# splice's: before, the folder was no splice, or another one.
splice_mount() {
  local path="$1" rev="${2:-HEAD}" commit
  git cat-file -e "$rev:$path/$STATE_FILE" 2>/dev/null || return 0
  while read -r commit; do
    if ! git rev-parse --verify --quiet "$commit^1" >/dev/null ||
      ! same_splice "$path" "$commit^1" "$commit"; then
      printf '%s\n' "$commit"
      return
    fi
  done < <(git log --first-parent --format=%H "$rev" -- ":(top,literal)$path/$STATE_FILE")
}

# Sets MOVED_FROM to the folder that commit <rev> moved to <path> (`git
# mv`), or to nothing if it didn't, and MOVED_STATE_KEPT to 1 if the move
# left the state file as it was. Only a move of the whole folder counts:
# <path> doesn't exist in <rev>'s first parent, and a folder that shares a
# file name with it there is gone in <rev>. If that folder wasn't a splice
# yet, all its file names must be the same -- their contents may have
# changed -- or a single file moved out of a bigger folder would publish
# the rest of that folder's history. A splice's content was meant for its
# upstream anyway, so the move may also add, delete or rename files. If
# several folders qualify (alike splices moved together), the one with the
# most unchanged files wins; a tie is no move.
moved_from() {
  local rev="$1" path="$2" entry name object deleted rest from
  local count=0 score best_score=-1 tie="" state from_state kept same
  # Keys start with "/", so that no file name is a special subscript.
  local -A files=() candidates=()
  MOVED_FROM=""
  MOVED_STATE_KEPT=""
  git rev-parse --verify --quiet "$rev^1" >/dev/null || return 0
  [[ -z "$(folder_tree "$rev^1" "$path")" ]] || return 0

  # ls-tree -z entries are "<mode> <type> <object>\t<name>".
  while IFS= read -r -d '' entry; do
    name="${entry#*$'\t'}"
    object="${entry%%$'\t'*}"
    files["/$name"]="${object##* }"
    [[ "$name" == "$STATE_FILE" ]] || count=$((count + 1))
  done < <(git ls-tree -r -z "$rev:$path")
  state="${files["/$STATE_FILE"]:-}"

  # A folder is a candidate if a file deleted from it has the name of one
  # in <path>.
  while IFS= read -r -d '' deleted; do
    rest="$deleted"
    while [[ "$rest" == */* ]]; do
      rest="${rest#*/}"
      [[ -n "${files["/$rest"]+set}" ]] && candidates["/${deleted%"/$rest"}"]=1
    done
  done < <(git diff-tree -r -z --no-renames --name-only --diff-filter=D "$rev^1" "$rev")

  for from in "${!candidates[@]}"; do
    from="${from#/}"
    [[ -z "$(folder_tree "$rev" "$from")" ]] || continue
    score=0
    rest=0
    from_state=""
    same=1
    while IFS= read -r -d '' entry; do
      name="${entry#*$'\t'}"
      object="${entry%%$'\t'*}"
      object="${object##* }"
      if [[ "$name" == "$STATE_FILE" ]]; then
        from_state="$object"
      elif [[ -n "${files["/$name"]+set}" ]]; then
        rest=$((rest + 1))
        [[ "${files["/$name"]}" == "$object" ]] && score=$((score + 1))
      else
        same=""
      fi
    done < <(git ls-tree -r -z "$rev^1:$from")
    ((rest == count)) || same=""
    [[ -n "$same" || -n "$from_state" ]] || continue
    if ((score > best_score)); then
      MOVED_FROM="$from"
      best_score="$score"
      tie=""
      kept=""
      [[ -n "$state" && "$state" == "$from_state" ]] && kept=1
    elif ((score == best_score)); then
      tie=1
    fi
  done
  if [[ -n "$tie" ]]; then
    MOVED_FROM=""
  elif [[ -n "$MOVED_FROM" ]]; then
    MOVED_STATE_KEPT="$kept"
  fi
}

# Follows splice <path> back from monorepo commit <upper> to its boundary:
# the newest first-parent commit that changed its state file. Moves of the
# folder (`git mv`, see moved_from) are followed; one that leaves the state
# file as it is isn't a boundary. Sets, as globals:
#   LINEAGE_BOUNDARY     the boundary B, or nothing
#   LINEAGE_SYNCED       the synced commit U recorded at B, or nothing
#   LINEAGE_PATH         the splice's path at B
#   LINEAGE_BEFORE_PATH  its path in B's first parent: another one if B
#                        moved the folder and changed the state file
#   LINEAGE_UPPER        the newest commit at LINEAGE_PATH
#   LINEAGE_PATHS, LINEAGE_RANGES
#                        the newer paths, newest first, each with the
#                        range (rev-list syntax) of commits it applies to
splice_lineage() {
  local path="$1" upper="$2" commit status
  LINEAGE_BOUNDARY=""
  LINEAGE_SYNCED=""
  LINEAGE_BEFORE_PATH=""
  LINEAGE_PATHS=()
  LINEAGE_RANGES=()
  while :; do
    commit="" status=""
    {
      IFS= read -r commit
      IFS= read -r _
      read -r status _
    } < <(git log --first-parent -1 --name-status --format=%H "$upper" -- ":(top,literal)$path/$STATE_FILE")
    [[ -n "$commit" ]] || break
    MOVED_FROM=""
    MOVED_STATE_KEPT=""
    # Only a commit that adds the state file can have moved the folder, so
    # a splice that never moved costs no extra Git process.
    [[ "$status" == A ]] && moved_from "$commit" "$path"
    if [[ -z "$MOVED_STATE_KEPT" ]]; then
      LINEAGE_BOUNDARY="$commit"
      LINEAGE_BEFORE_PATH="${MOVED_FROM:-$path}"
      break
    fi
    LINEAGE_PATHS+=("$path")
    LINEAGE_RANGES+=("$commit^1..$upper")
    path="$MOVED_FROM"
    upper="$commit^1"
  done
  [[ -n "$LINEAGE_BOUNDARY" ]] && LINEAGE_SYNCED="$(splice_config "$path" commit "$LINEAGE_BOUNDARY")"
  LINEAGE_PATH="$path"
  LINEAGE_UPPER="$upper"
}

# Continues splice_lineage back from LINEAGE_PATH and LINEAGE_UPPER to the
# splice's mount (see splice_mount), following moves of the folder that
# kept the splice: the state file it came from is the same splice
# (same_splice), even if the move changed it. Sets LINEAGE_MOUNT, or
# nothing if there's no state file, and extends LINEAGE_PATH,
# LINEAGE_UPPER, LINEAGE_PATHS and LINEAGE_RANGES. A move from before the
# mount isn't followed: the folder was no splice then.
splice_lineage_to_mount() {
  local path="$LINEAGE_PATH" upper="$LINEAGE_UPPER" commit moved
  LINEAGE_MOUNT=""
  while :; do
    moved=""
    while read -r commit; do
      if git rev-parse --verify --quiet "$commit^1" >/dev/null &&
        same_splice "$path" "$commit^1" "$commit"; then
        continue
      fi
      moved_from "$commit" "$path"
      if [[ -n "$MOVED_FROM" ]] && same_splice "$MOVED_FROM" "$commit^1" "$commit" "$path"; then
        moved=1
      else
        LINEAGE_MOUNT="$commit"
      fi
      break
    done < <(git log --first-parent --format=%H "$upper" -- ":(top,literal)$path/$STATE_FILE")
    [[ -n "$moved" ]] || break
    LINEAGE_PATHS+=("$path")
    LINEAGE_RANGES+=("$commit^1..$upper")
    path="$MOVED_FROM"
    upper="$commit^1"
  done
  LINEAGE_PATH="$path"
  LINEAGE_UPPER="$upper"
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
#   1. B is the boundary (splice_lineage, which follows the folder through
#      moves) and U the synced commit recorded there. If B's folder equals
#      U, the rebuild starts at U.
#   2. If it differs -- a pull merged local changes in, or a squash merge
#      mixed local edits into the commit that changed the state file -- B
#      is rebuilt as a commit with B's folder, whose parents are what the
#      rebuild had before B (rebuilt from B's first parent, recursively)
#      and U. Local commits that were never pushed keep their own identity.
#   3. Then one commit per first-parent commit after B whose folder
#      differs from the one before, under the path the folder had then. A
#      merge in the monorepo becomes one ordinary commit.
# Without a synced commit (after init, before any pull), the rebuild
# starts at the mount (splice_lineage_to_mount, which follows moves too),
# as a root commit with the folder as it was then. Nothing from before the
# mount is published, with or without a synced commit: the folder was no
# splice then, or another one, and its history may hold what was removed
# before it became this splice.
rebuild_splice() {
  local path="$1" rev="${2:-HEAD}"
  local boundary synced prev="" prev_tree="" tree range i
  local at before_path upper
  local -a paths ranges

  splice_lineage "$path" "$rev"
  # Recursive calls below overwrite the globals.
  boundary="$LINEAGE_BOUNDARY"
  synced="$LINEAGE_SYNCED"
  at="$LINEAGE_PATH"
  before_path="$LINEAGE_BEFORE_PATH"
  upper="$LINEAGE_UPPER"
  paths=("${LINEAGE_PATHS[@]}")
  ranges=("${LINEAGE_RANGES[@]}")

  # A nested splice's history up to the boundary of the splice above it
  # is in that splice's upstream: a clone or pull of the splice above
  # squashed it into one commit here. So up to there, it's rebuilt from
  # the upstream's history, at the synced commit of the splice above, and
  # that rebuild stands in for the synced commit. Only if the splice
  # didn't move since its boundary: the path in the upstream above would
  # be another one.
  local above above_boundary above_synced from_above
  if [[ ${#paths[@]} -eq 0 ]] && above="$(splice_above_in "$rev" "$path")"; then
    above_boundary="$(splice_boundary "$above" "$rev")"
    above_synced=""
    [[ -n "$above_boundary" ]] && above_synced="$(splice_config "$above" commit "$above_boundary")"
    if [[ -n "$above_synced" && -n "$boundary" ]] &&
      git cat-file -e "$above_synced^{commit}" 2>/dev/null &&
      git merge-base --is-ancestor "$boundary" "$above_boundary"; then
      from_above="$(rebuild_splice "${path#"$above/"}" "$above_synced")"
      if [[ -n "$from_above" ]]; then
        boundary="$above_boundary"
        synced="$from_above"
        before_path="$path"
      fi
    fi
  fi

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
    content_tree "$boundary" "$at"
    tree="$CONTENT_TREE"
    if [[ -n "$tree" && "$tree" != "$prev_tree" ]]; then
      local before parents=()
      before=""
      # Unless B is the mount: what came before isn't this splice's.
      git rev-parse --verify --quiet "$boundary^1" >/dev/null &&
        same_splice "$before_path" "$boundary^1" "$boundary" "$at" &&
        before="$(rebuild_splice "$before_path" "$boundary^1")"
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
    range="$boundary..$upper"
  else
    LINEAGE_PATH="$at"
    LINEAGE_UPPER="$upper"
    LINEAGE_PATHS=("${paths[@]}")
    LINEAGE_RANGES=("${ranges[@]}")
    splice_lineage_to_mount
    [[ -n "$LINEAGE_MOUNT" ]] || return 0
    at="$LINEAGE_PATH"
    upper="$LINEAGE_UPPER"
    paths=("${LINEAGE_PATHS[@]}")
    ranges=("${LINEAGE_RANGES[@]}")
    range="$upper"
    git rev-parse --verify --quiet "$LINEAGE_MOUNT^1" >/dev/null && range="$LINEAGE_MOUNT^1..$upper"
  fi

  prev="$(rebuild_walk "$at" "$prev" "$range")"
  for ((i = ${#paths[@]} - 1; i >= 0; i--)); do
    prev="$(rebuild_walk "${paths[i]}" "$prev" "${ranges[i]}")"
  done
  printf '%s\n' "$prev"
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
