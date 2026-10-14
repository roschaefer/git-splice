# The push rebuild: turns a splice's history in the monorepo into the
# commits its upstream gets, and the rebuild command that prints it. Assumes lib/common.sh is already sourced.
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
# <path>'s state file -- the last sync, L. Every pull, clone and init writes
# such a commit, and rebases and squash merges can't remove all of them.
splice_last_sync() {
  local path="$1" rev="${2:-HEAD}"
  git log --first-parent -1 --no-show-signature --format=%H "$rev" -- ":(top,literal)$path/$STATE_FILE"
}

# Succeeds if the state files at <path> in commits <a> and <b> are the
# same splice: they have the same splice.id. Fails if either has none.
same_splice() {
  local path="$1" a="$2" b="$3" id_a
  id_a="$(splice_config "$path" id "$a")"
  [[ -n "$id_a" && "$id_a" == "$(splice_config "$path" id "$b")" ]]
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
#   1. L is the last sync (splice_last_sync) and U the synced commit
#      recorded there. If L's folder equals U, the rebuild starts at U,
#      and L is the start.
#   2. If it differs -- a pull merged local changes in, or a squash merge
#      mixed local edits into the commit that changed the state file -- L
#      is rebuilt as a commit with L's folder, whose parents are what the
#      rebuild had before L (rebuilt from L's first parent, recursively)
#      and U. Local commits that were never pushed keep their own identity.
#      Where that rebuild is one of the parents, its start is the start.
#   3. Then one commit per first-parent commit after L whose folder
#      differs from the one before. A merge in the monorepo becomes one
#      ordinary commit.
# Without a synced commit (after init, before any pull), the rebuild
# starts at the mount (splice_mount), as a root commit with the folder as
# it was then. Nothing from before the mount is published, with or
# without a synced commit: the folder was no splice then, or another one,
# and its history may hold what was removed before it became this splice.
rebuild_with_start() {
  local path="$1" rev="${2:-HEAD}"
  local last_sync synced prev="" prev_tree="" tree range start rebuild_start

  last_sync="$(splice_last_sync "$path" "$rev")"
  synced=""
  [[ -n "$last_sync" ]] && synced="$(splice_config "$path" commit "$last_sync")"

  # A nested splice's history up to the last sync of a splice above it is
  # in that splice's upstream: a clone or pull of the splice above
  # squashed it into one commit here. So up to there, it's rebuilt from
  # the upstream's history, at the synced commit of the splice above, and
  # that rebuild stands in for the synced commit. Of the splices above,
  # the one with the newest last sync covers the most history; on a tie,
  # the outermost, whose upstream has the ones below it too, at least as
  # new as their own synced commits. Only where the upstream above has
  # the same splice at the path: it may have replaced it with another.
  local dir="$path" above above_last_sync above_synced from_above=""
  local best="" best_last_sync="" best_synced=""
  if [[ -n "$last_sync" ]]; then
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
    content_tree "$last_sync" "$path"
    tree="$CONTENT_TREE"
    # With the history from above, L's folder may equal it while the
    # monorepo's history before L has commits it lacks, e.g. one pushed
    # straight to this splice's upstream: they're joined all the same.
    if [[ -n "$tree" && ("$tree" != "$prev_tree" || -n "$from_above") ]]; then
      local before="" before_start="" parents=()
      # Unless L is the mount: what came before isn't this splice's.
      if git rev-parse --verify --quiet "$last_sync^1" >/dev/null &&
        same_splice "$path" "$last_sync^1" "$last_sync"; then
        before="$(rebuild_with_start "$path" "$last_sync^1")" || return
        before_start="${before#* }"
        before="${before% *}"
        [[ "$before" != - ]] || before=""
      fi
      if [[ -z "$before" ]] || git merge-base --is-ancestor "$before" "$synced"; then
        # Nothing unpushed before L: L's changes go on top of U. Where
        # L's folder isn't U, e.g. a squash merge put a local edit into
        # it, L itself is copied, so the rebuild starts where the one
        # before L did.
        parents=("$synced")
        [[ "$tree" == "$prev_tree" || -z "$before_start" || "$before_start" == - ]] ||
          rebuild_start="$before_start"
      elif git merge-base --is-ancestor "$synced" "$before"; then
        # What came before already contains U, e.g. L only changed the
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
    range="$last_sync..$rev"
  else
    start="$(splice_mount "$path" "$rev")"
    if [[ -z "$start" ]]; then
      printf -- '- -\n'
      return 0
    fi
    rebuild_start="$start"
    range="$rev"
    git rev-parse --verify --quiet "$start^1" >/dev/null && range="$start^1..$rev"
  fi

  prev="$(rebuild_walk "$path" "$prev" "$range")"
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

usage_rebuild() {
  cat <<'EOF'
usage: git splice rebuild <path>

Prints the commit 'git splice push <path>' would send: the splice's
history rebuilt without its .splice file, on top of the upstream commit
it last synced with. If nothing changed since, that's the synced commit
itself. The rebuild is deterministic, so a later push sees what was
pushed of it as already upstream.

Writes nothing: no ref, no monorepo commit. Purely local, but the synced
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
  [[ -z "$ALL_ARG" ]] || die "rebuild takes no --all"
  [[ -z "$BASE_ARG" ]] || die "rebuild takes no --base"
  [[ ${#PATH_ARGS[@]} -eq 1 ]] || {
    usage_rebuild >&2
    exit 1
  }
  local path rebuilt
  path="$(normalize_path "${PATH_ARGS[0]}")"
  cd_to_repo_root
  require_head_commit
  discover_splices
  is_splice_path "$path" || die "not a splice: $path"
  rebuilt="$(rebuild_splice "$path" HEAD)" || exit 1
  [[ -n "$rebuilt" ]] || die "$path: has no content yet -- nothing to rebuild"
  printf '%s\n' "$rebuilt"
}
