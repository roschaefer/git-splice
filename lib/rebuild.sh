# The push rebuild: turns a splice's history in the monorepo into the
# commits its upstream gets, and the rebuild command that prints it. Assumes lib/common.sh is already sourced.
#
# The rebuild is deterministic -- the same history always rebuilds into the
# same commits -- so status can compare it with the upstream branch without
# remembering anything about earlier pushes. See docs/design/README.md.

# Options for every git command that reads or writes a rebuilt commit:
# the rebuild must come out the same for everyone, and i18n.commitEncoding
# would re-encode each message and add an encoding header.
REBUILD_ENCODING=(-c i18n.commitEncoding=UTF-8 -c i18n.logOutputEncoding=UTF-8)

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
# <path>'s state file -- the last sync, L. Every pull, clone and init writes
# such a commit, and rebases and squash merges can't remove all of them.
splice_last_sync() {
  local path="$1" rev="${2:-HEAD}"
  git log --first-parent -1 --no-show-signature --format=%H "$rev" -- ":(top,literal)$path/$STATE_FILE"
}

# Dies if <commit> is a shallow clone's cut-off commit. git log takes it
# as adding every file, so it looks like splice <path>'s last sync or
# mount whether it is one or not, and the rebuild would fold the commits
# since the real one into one.
refuse_shallow_start() {
  local path="$1" commit="$2" shallow
  shallow="$(git rev-parse --git-path shallow)"
  [[ -f "$shallow" ]] && grep -qxF "$commit" "$shallow" || return 0
  die "$path: this shallow clone may cut off where its rebuild starts, at ${commit:0:7} -- run 'git fetch --unshallow'"
}

# Succeeds if the state file at <path> in commit <a> and the one at
# <path_b> (default: <path>) in commit <b> are the same splice: they have
# the same splice.id. Fails if either has none.
same_splice() {
  local path="$1" a="$2" b="$3" path_b="${4:-$1}" id_a
  id_a="$(splice_config "$path" id "$a")"
  [[ -n "$id_a" && "$id_a" == "$(splice_config "$path_b" id "$b")" ]]
}

# Prints the first-parent commit reachable from <rev> where the splice at
# <path> in <rev> was mounted: the newest one whose first parent had no
# state file at <path>, or another splice's (same_splice). Nothing if
# <path> isn't a splice in <rev>. Only the history from there on is this
# splice's: before, the folder was no splice, or another one.
splice_mount() {
  local path="$1" rev="${2:-HEAD}" commit id
  git cat-file -e "$rev:$path/$STATE_FILE" 2>/dev/null || return 0
  # Every commit the walk passes has the same id as <rev>: it stops at the
  # first one whose parent has another. So <rev>'s is read once, and only
  # each parent's per commit.
  id="$(splice_config "$path" id "$rev")"
  while read -r commit; do
    if [[ -z "$id" ]] || ! git rev-parse --verify --quiet "$commit^1" >/dev/null ||
      [[ "$(splice_config "$path" id "$commit^1")" != "$id" ]]; then
      printf '%s\n' "$commit"
      return
    fi
  done < <(git log --first-parent --no-show-signature --format=%H "$rev" -- ":(top,literal)$path/$STATE_FILE")
}

# Sets MOVED_FROM to the folder that commit <rev> moved splice <path>
# from (`git mv`), or to nothing if it didn't, and MOVED_STATE_KEPT to 1
# if the move left the state file as it was. The splice's id says where it
# came from: the folder whose state file had that id in <rev>'s first
# parent, and no longer has it in <rev>. So a move may also change, add or
# delete files, two splices may swap paths, and a new folder may take the
# old path. If several folders had the id, mirrors moved together, the one
# with the most files unchanged at <path> wins; a tie is no move.
moved_from() {
  local rev="$1" path="$2" id file from score best_score=-1 tie=""
  local -a candidates=()
  MOVED_FROM=""
  MOVED_STATE_KEPT=""
  git rev-parse --verify --quiet "$rev^1" >/dev/null || return 0
  id="$(splice_config "$path" id "$rev")"
  [[ -n "$id" ]] || return 0
  [[ "$(splice_config "$path" id "$rev^1")" != "$id" ]] || return 0
  # The state file it came from was deleted or changed by <rev>.
  while IFS= read -r -d '' file; do
    from="${file%/"$STATE_FILE"}"
    [[ "$from" != "$path" ]] || continue
    [[ "$(splice_config "$from" id "$rev^1")" == "$id" ]] || continue
    [[ "$(splice_config "$from" id "$rev")" != "$id" ]] || continue
    candidates+=("$from")
  done < <(git diff-tree -r -z --no-renames --name-only --diff-filter=DM "$rev^1" "$rev" -- ":(top,glob)**/$STATE_FILE")
  if [[ ${#candidates[@]} -eq 1 ]]; then
    MOVED_FROM="${candidates[0]}"
  else
    for from in "${candidates[@]}"; do
      # Files with the same name and content: lines both listings have.
      score="$(comm -12 <(git ls-tree -r "$rev^1:$from" | sort) <(git ls-tree -r "$rev:$path" | sort) | wc -l)"
      if ((score > best_score)); then
        MOVED_FROM="$from" best_score="$score" tie=""
      elif ((score == best_score)); then
        tie=1
      fi
    done
    [[ -z "$tie" ]] || MOVED_FROM=""
  fi
  [[ -n "$MOVED_FROM" && "$(git rev-parse "$rev^1:$MOVED_FROM/$STATE_FILE")" == "$(git rev-parse "$rev:$path/$STATE_FILE")" ]] &&
    MOVED_STATE_KEPT=1
  return 0
}

# Follows splice <path> back from monorepo commit <upper> to its last
# sync L (splice_last_sync). Moves of the folder (`git mv`, see
# moved_from) are followed; one that leaves the state file as it is isn't
# a last sync. Prints, each field ending with a NUL:
#   L, or nothing
#   the synced commit U(L) recorded at L, or nothing
#   the splice's path at L
#   its path in L's first parent: another one if L moved the folder and
#     changed the state file
#   the newest commit at the path at L
# then, newest first, each newer path and the range (rev-list syntax) of
# commits it applies to. Read it with read_lineage.
splice_lineage() {
  local path="$1" upper="$2" commit last_sync="" synced="" before_path=""
  local -a moves=()
  while :; do
    commit="$(splice_last_sync "$path" "$upper")"
    [[ -n "$commit" ]] || break
    moved_from "$commit" "$path"
    if [[ -z "$MOVED_STATE_KEPT" ]]; then
      last_sync="$commit"
      before_path="${MOVED_FROM:-$path}"
      break
    fi
    moves+=("$path" "$commit^1..$upper")
    path="$MOVED_FROM"
    upper="$commit^1"
  done
  [[ -z "$last_sync" ]] || synced="$(splice_config "$path" commit "$last_sync")"
  printf '%s\0' "$last_sync" "$synced" "$path" "$before_path" "$upper" "${moves[@]}"
}

# Continues splice_lineage's walk for splice <path> back from monorepo
# commit <upper> to the splice's mount (see splice_mount), following moves
# of the folder that kept the splice's id, even if the move changed its
# state file. A move from before the mount isn't followed: the folder was
# no splice then. Prints, each field ending with a NUL, the mount (nothing
# if there's no state file), the path there, and the newest commit at that
# path, then the moves as splice_lineage does.
splice_lineage_to_mount() {
  local path="$1" upper="$2" commit id mount=""
  local -a moves=()
  if git cat-file -e "$upper:$path/$STATE_FILE" 2>/dev/null; then
    while :; do
      # As in splice_mount, every commit the walk passes at one path has
      # <upper>'s id, so it's read once per path.
      id="$(splice_config "$path" id "$upper")"
      MOVED_FROM=""
      while read -r commit; do
        if [[ -n "$id" ]] && git rev-parse --verify --quiet "$commit^1" >/dev/null &&
          [[ "$(splice_config "$path" id "$commit^1")" == "$id" ]]; then
          continue
        fi
        moved_from "$commit" "$path"
        [[ -n "$MOVED_FROM" ]] || mount="$commit"
        break
      done < <(git log --first-parent --no-show-signature --format=%H "$upper" -- ":(top,literal)$path/$STATE_FILE")
      [[ -n "$MOVED_FROM" ]] || break
      moves+=("$path" "$commit^1..$upper")
      path="$MOVED_FROM"
      upper="$commit^1"
    done
  fi
  printf '%s\0' "$mount" "$path" "$upper" "${moves[@]}"
}

# Reads the output of splice_lineage or splice_lineage_to_mount from
# stdin: its first <n> fields into the variables named <var>... (a field
# whose name is - is skipped), and the moves after them appended to the
# arrays named <paths> and <ranges>.
read_lineage() {
  local n="$1" i field move_path move_range
  local -n lineage_paths="$2" lineage_ranges="$3"
  shift 3
  for ((i = 0; i < n; i++)); do
    IFS= read -r -d '' field || return
    [[ "$1" == - ]] || printf -v "$1" '%s' "$field"
    shift
  done
  while IFS= read -r -d '' move_path && IFS= read -r -d '' move_range; do
    lineage_paths+=("$move_path")
    lineage_ranges+=("$move_range")
  done
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
  } < <(git "${REBUILD_ENCODING[@]}" log -1 --no-show-signature --pretty=format:'%an%n%ae%n%aD%n%cn%n%ce%n%cD%n' "$source")
  # --pretty=format: has no trailing newline, unlike --format= (tformat),
  # so the message comes out byte for byte as split copies it.
  git "${REBUILD_ENCODING[@]}" log -1 --no-show-signature --pretty=format:%B "$source" |
    GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" GIT_AUTHOR_DATE="$ad" \
      GIT_COMMITTER_NAME="$cn" GIT_COMMITTER_EMAIL="$ce" GIT_COMMITTER_DATE="$cd" \
      git "${REBUILD_ENCODING[@]}" commit-tree --no-gpg-sign "$tree" "${parents[@]}"
}

# Commits given for a splice's rebuild with push --rebuilt-commit, by path.
declare -gA REBUILD_GIVEN=()

# Prints the rebuild push sends for splice <path> at HEAD: the commit given
# with push --rebuilt-commit, if any, else rebuild_splice's.
splice_rebuild() {
  local path="$1"
  if [[ -n "${REBUILD_GIVEN[$path]:-}" ]]; then
    printf '%s\n' "${REBUILD_GIVEN[$path]}"
  else
    rebuild_splice "$path" HEAD
  fi
}

# Prints the upstream commit that represents splice <path> as of monorepo
# commit <rev> (default HEAD), or nothing if the splice has no content yet.
rebuild_splice() {
  local result
  result="$(rebuild_with_start "$@")" || return
  result="${result% *}"
  [[ "$result" == - ]] || printf '%s
' "$result"
}

# Prints the commit the rebuild of splice <path> as of <rev> (default
# HEAD) starts from, the splice's boundary B: the commits on the
# first-parent history after it are the ones the rebuild copies.
splice_start() {
  local result
  result="$(rebuild_with_start "$@")" || return
  result="${result#* }"
  [[ "$result" == - ]] || printf '%s
' "$result"
}

# Prints "<rebuild> <start>": rebuild_splice's commit and splice_start's,
# each "-" if there's none.
#
#   1. L is the last sync (splice_lineage, which follows the folder through
#      moves) and U(L) the synced commit recorded there. If L's folder equals U(L), the rebuild starts at U(L),
#      and L is the start.
#   2. If it differs -- a pull merged local changes in, or a squash merge
#      mixed local edits into the commit that changed the state file -- L
#      is rebuilt as a commit with L's folder, whose parents are what the
#      rebuild had before L (rebuilt from L's first parent, recursively)
#      and U(L). Local commits that were never pushed keep their own identity.
#      Where that rebuild is one of the parents, its start is the start.
#   3. Then one commit per first-parent commit after L whose folder
#      differs from the one before, under the path the folder had then. A
#      merge in the monorepo becomes one ordinary commit.
# Without a synced commit (after init, before any pull), the rebuild
# starts at the mount (splice_lineage_to_mount, which follows moves too),
# as a root commit with the folder as
# it was then. Nothing from before the mount is published, with or
# without a synced commit: the folder was no splice then, or another one,
# and its history may hold what was removed before it became this splice.
rebuild_with_start() {
  local path="$1" rev="${2:-HEAD}"
  local last_sync synced prev="" prev_tree="" tree range rebuild_start i
  local at before_path upper
  local -a paths=() ranges=()
  read_lineage 5 paths ranges last_sync synced at before_path upper < <(splice_lineage "$path" "$rev")
  [[ -z "$last_sync" ]] || refuse_shallow_start "$at" "$last_sync"

  # A nested splice's history up to the last sync of a splice above it is
  # in that splice's upstream: a clone or pull of the splice above
  # squashed it into one commit here. So up to there, it's rebuilt from
  # the upstream's history, at the synced commit of the splice above, and
  # that rebuild stands in for the synced commit. Of the splices above,
  # the one with the newest last sync covers the most history; on a tie,
  # the outermost, whose upstream has the ones below it too, at least as
  # new as their own synced commits. Only where the upstream above has
  # the same splice at the path: it may have replaced it with another.
  # And only if the splice didn't move since its last sync: the path in
  # the upstream above would be another one.
  local dir="$path" above above_last_sync above_synced from_above=""
  local best="" best_last_sync="" best_synced=""
  if [[ -n "$last_sync" && ${#paths[@]} -eq 0 ]]; then
    while above="$(splice_above_in "$rev" "$dir")"; do
      dir="$above"
      above_last_sync="$(splice_last_sync "$above" "$rev")"
      [[ -n "$above_last_sync" ]] || continue
      above_synced="$(splice_config "$above" commit "$above_last_sync")"
      [[ -n "$above_synced" ]] && git cat-file -e "$above_synced^{commit}" 2>/dev/null || continue
      git merge-base --is-ancestor "$last_sync" "$above_last_sync" || continue
      [[ -z "$best" ]] || git merge-base --is-ancestor "$best_last_sync" "$above_last_sync" || continue
      [[ "$(splice_config "${path#"$above/"}" id "$above_synced")" == "$(splice_config "$path" id "$rev")" ]] || continue
      best="$above" best_last_sync="$above_last_sync" best_synced="$above_synced"
    done
  fi
  if [[ -n "$best" ]]; then
    from_above="$(rebuild_splice "${path#"$best/"}" "$best_synced")"
    if [[ -n "$from_above" ]]; then
      # A newer last sync above: the splice had its path in its first
      # parent, since it didn't move after its own last sync.
      [[ "$best_last_sync" == "$last_sync" ]] || before_path="$path"
      last_sync="$best_last_sync"
      synced="$from_above"
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
    rebuild_start="$last_sync"
    prev="$synced"
    prev_tree="$(git rev-parse "$synced^{tree}")"
    content_tree "$last_sync" "$at"
    tree="$CONTENT_TREE"
    # With the history from above, L's folder may equal it while the
    # monorepo's history before L has commits it lacks, e.g. one pushed
    # straight to this splice's upstream: they're joined all the same.
    # So is a move that changed the state file: the history before it is
    # at the old path, even where L's folder equals U(L).
    if [[ -n "$tree" && ("$tree" != "$prev_tree" || -n "$from_above" || "$before_path" != "$at") ]]; then
      local before="" before_start="" parents=()
      # Unless L is the mount: what came before isn't this splice's.
      if git rev-parse --verify --quiet "$last_sync^1" >/dev/null &&
        same_splice "$before_path" "$last_sync^1" "$last_sync" "$at"; then
        before="$(rebuild_with_start "$before_path" "$last_sync^1")" || return
        before_start="${before#* }"
        before="${before% *}"
        [[ "$before" != - ]] || before=""
      fi
      if [[ -z "$before" ]] || git merge-base --is-ancestor "$before" "$synced"; then
        # Nothing unpushed before L: L's changes go on top of U(L). Where
        # L's folder isn't U(L), e.g. a squash merge put a local edit into
        # it, L itself is copied, so the rebuild starts where the one
        # before L did.
        parents=("$synced")
        [[ "$tree" == "$prev_tree" || -z "$before_start" || "$before_start" == - ]] ||
          rebuild_start="$before_start"
      elif git merge-base --is-ancestor "$synced" "$before"; then
        # What came before already contains U(L), e.g. L only changed the
        # state file: continue from there.
        parents=("$before")
        rebuild_start="$before_start"
      else
        # A pull merged a divergence: join both sides, as git pull would.
        parents=("$before" "$synced")
        rebuild_start="$before_start"
      fi
      if [[ ${#parents[@]} -eq 1 && "$tree" == "$(git rev-parse "${parents[0]}^{tree}")" ]]; then
        prev="${parents[0]}"
      else
        prev="$(copy_commit "$last_sync" "$tree" "${parents[@]}")"
      fi
      prev_tree="$tree"
    fi
    range="$last_sync..$upper"
  else
    read_lineage 3 paths ranges rebuild_start at upper < <(splice_lineage_to_mount "$at" "$upper")
    if [[ -z "$rebuild_start" ]]; then
      printf -- '- -\n'
      return 0
    fi
    refuse_shallow_start "$at" "$rebuild_start"
    range="$upper"
    git rev-parse --verify --quiet "$rebuild_start^1" >/dev/null && range="$rebuild_start^1..$upper"
  fi

  prev="$(rebuild_walk "$at" "$prev" "$range")"
  for ((i = ${#paths[@]} - 1; i >= 0; i--)); do
    prev="$(rebuild_walk "${paths[i]}" "$prev" "${ranges[i]}")"
  done
  printf '%s %s\n' "${prev:--}" "$rebuild_start"
}

# Prints the rebuild of splice <path> along <range> (rev-list syntax, e.g.
# "L..HEAD"), on top of upstream commit <start> (nothing: a new root):
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
  done < <(git "${REBUILD_ENCODING[@]}" log --reverse --first-parent --no-show-signature \
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
        git "${REBUILD_ENCODING[@]}" commit-tree --no-gpg-sign "$CONTENT_TREE" "${parents[@]}")"
    prev_tree="$CONTENT_TREE"
  done
  printf '%s\n' "$prev"
}

usage_rebuild() {
  cat <<'EOF'
usage: git splice rebuild <path>

Prints the commit 'git splice push <path>' would send: the splice's
history rebuilt without its .splice file, on top of the upstream commit
it last synced with. If nothing changed since, that's the synced commit
itself. The rebuild is deterministic, so a later push sees what was
pushed of it as already upstream.

Writes no ref and no monorepo commit. Purely local, but the synced
commit must have been fetched.

Push it to an upstream branch other than the one named like the current
one, e.g. a release branch:

  git push <url> "$(git splice rebuild <path>)":refs/heads/<branch>

or check it out in a separate worktree, since it has the upstream's
layout, not the monorepo's:

  git worktree add ../rebuild "$(git splice rebuild <path>)"
EOF
}

cmd_rebuild() {
  parse_args usage_rebuild "" "$@"
  require_args usage_rebuild rebuild 1 1
  local path rebuilt
  path="$(normalize_path "${PATH_ARGS[0]}")"
  open_repository
  require_splice "$path"
  rebuilt="$(rebuild_splice "$path" HEAD)" || exit 1
  [[ -n "$rebuilt" ]] || die "$path: has no content yet -- nothing to rebuild"
  printf '%s\n' "$rebuilt"
}
