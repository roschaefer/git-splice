# Low-level git-plumbing helpers shared by test/scenarios/**/setup.bash.
# Named scenarios compose these into the specific history shapes bats
# tests exercise -- see each scenario folder's README.md.

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

make_bare_repo() {
  git init -q --bare --initial-branch="${2:-main}" "$1"
}

# Clones $1, appends line $2 to file $4 (default: file.txt, created if
# needed), commits with message $2, and pushes to branch $3 (default:
# main). A missing branch is created from the remote's HEAD, or as the
# first commit of an empty repository.
seed_bare_repo() {
  local repo="$1" msg="$2" branch="${3:-main}" file="${4:-file.txt}" tmp
  tmp="$(mktemp -d)"
  git clone -q "$repo" "$tmp" 2>/dev/null
  (
    cd "$tmp"
    git config user.name "Test"
    git config user.email "test@example.com"
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
      git fetch -q origin "$branch"
      git checkout -q -B "$branch" "origin/$branch"
    else
      git checkout -q -B "$branch"
    fi
    mkdir -p "$(dirname "$file")"
    echo "$msg" >>"$file"
    git add "$file"
    git commit -q -m "$msg"
    git push -q origin "HEAD:$branch"
  )
  rm -rf "$tmp"
}

# Commits file $2 with content $3, where printf %b escapes such as \r\n
# apply, to branch main of bare repository $1, as is: past any line
# ending conversion.
commit_raw_file() {
  local repo="$1" file="$2" content="$3" tmp
  tmp="$(mktemp -d)"
  git clone -q "$repo" "$tmp" 2>/dev/null
  (
    cd "$tmp"
    printf '%b' "$content" >"$file"
    git -c core.autocrlf=false add -- "$file"
    git -c user.name=Test -c user.email=test@example.com commit -q -m "add $file"
    git push -q origin HEAD:main
  )
  rm -rf "$tmp"
}

# Commits a submodule of bare repository $2 at path $3 to branch main of
# bare repository $1.
add_upstream_submodule() {
  local repo="$1" inner="$2" path="$3" tmp
  tmp="$(mktemp -d)"
  git clone -q "$repo" "$tmp" 2>/dev/null
  (
    cd "$tmp"
    git -c protocol.file.allow=always submodule add -q "$inner" "$path"
    git -c user.name=Test -c user.email=test@example.com commit -q -m "add $path as a submodule"
    git push -q origin HEAD:main
  )
  rm -rf "$tmp"
}

# Initializes a monorepo working tree at $1 with local git identity (CI
# runners have no global one), main as its default branch, and one
# initial commit. Does not cd -- callers use their own cwd or a subshell.
init_monorepo() {
  git init -q -b main "$1"
  (
    cd "$1"
    git config user.name "Test"
    git config user.email "test@example.com"
    git config init.defaultBranch main
    git commit -q --allow-empty -m "initial commit"
  )
}

# Prints the prefix of the refs git splice fetches upstream <url>'s
# branches into in the repository at the current directory, e.g.
# refs/splices/upstream/heads/, recording a key for the upstream first if
# it has none, in the repository's config, where the commands read it.
upstream_refs() {
  local url="$1" name key="" n=2 line
  while IFS= read -r line; do
    [[ "${line#* }" != "$url" ]] || key="${line%% *}"
  done < <(git config --local --get-regexp '^splice\..*\.url$' || true)
  if [[ -n "$key" ]]; then
    key="${key#splice.}"
    key="${key%.url}"
  else
    name="${url%/}"
    name="${name%.git}"
    name="${name##*/}"
    key="$name"
    while [[ -n "$(git config --local "splice.$key.url" || true)" ]]; do
      key="$name-$n"
      n=$((n + 1))
    done
    git config --local "splice.$key.url" "$url"
  fi
  printf 'refs/splices/%s/heads/\n' "$key"
}

# Fetches every branch of upstream $2 into monorepo $1's refs, like `git
# splice fetch` does for a splice with that URL. ($3, the splice's path,
# doesn't matter: refs are keyed by URL.)
fetch_splice() {
  local monorepo="$1" url="$2" prefix
  prefix="$(cd "$monorepo" && upstream_refs "$url")"
  git -C "$monorepo" -c core.logAllRefUpdates=always fetch -q --no-tags --prune -- "$url" "+refs/heads/*:$prefix*"
}

# Splices branch $4 (default: main) of upstream $2 into $3 inside monorepo
# $1 via raw git plumbing -- deliberately NOT via `git splice clone`, so other
# commands' tests don't depend on clone's own correctness. The commit's
# message is $5, default "add <path>".
add_splice() {
  local monorepo="$1" url="$2" path="$3" branch="${4:-main}" msg="${5:-add $3}" commit id
  fetch_splice "$monorepo" "$url" "$path"
  (
    cd "$monorepo"
    commit="$(git rev-parse "$(upstream_refs "$url")$branch")"
    id="$(printf '%s\0%s\0%s\0%s\0' "$path" "$(git rev-parse --verify --quiet HEAD || true)" "$url" "$commit" | git hash-object --stdin)"
    id="${id:0:16}"
    git read-tree --prefix="$path/" -u "$commit"
    printf '[splice]\n\tcommit = %s\n\tid = %s\n[upstream "origin"]\n\turl = %s\n' "$commit" "$id" "$url" >"$path/.splice"
    git add "$path"
    git commit -q -m "$msg"
  )
}

# Appends line $3 to <path>/file.txt in monorepo $1 (path $2) and commits
# it with message $3.
commit_local() {
  local monorepo="$1" path="$2" msg="$3" file="${4:-file.txt}"
  (
    cd "$monorepo"
    mkdir -p "$(dirname "$path/$file")"
    echo "$msg" >>"$path/$file"
    git add "$path/$file"
    git commit -q -m "$msg"
  )
}

# Runs the real git-splice entrypoint, for scenarios whose history needs
# a command's own result (e.g. an earlier push).
splice() {
  "$FIXTURES_DIR/../../git-splice" "$@"
}

# Ignores the developer's own git config (e.g. a global init.defaultBranch),
# so tests about how the default branch is resolved behave the same everywhere.
# Bats runs each test in its own subshell, so this never leaks.
hermetic_git_config() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
}

# Prints value <key> of the [splice] section of <path>'s committed state
# file in <rev> (default: HEAD), or nothing.
splice_config() {
  git config --blob "${3:-HEAD}:$1/.splice" --get "splice.$2" 2>/dev/null || true
}

# Prints value <key> of upstream <name> in <path>'s committed state file,
# or nothing.
upstream_config() {
  git config --blob "HEAD:$1/.splice" --get "upstream.$2.$3" 2>/dev/null || true
}

# Prints the mode of <path> in <rev>: 040000 for a folder, 160000 for a
# submodule, or nothing if it isn't there.
path_mode() {
  git ls-tree --format='%(objectmode)' "$1" -- "$2"
}

# Sets CONTENT_TREE to folder <path>'s tree in <rev>, without its state
# file: what a rebuilt commit holds.
content_tree() {
  local index="$BATS_TEST_TMPDIR/content-tree-index"
  rm -f "$index"
  GIT_INDEX_FILE="$index" git read-tree "$1:$2"
  GIT_INDEX_FILE="$index" git rm -q --cached --ignore-unmatch .splice
  CONTENT_TREE="$(GIT_INDEX_FILE="$index" git write-tree)"
}

# Prints splice <path>'s state, read off its line in `git splice status`:
# up-to-date, push, pull, diverged, unrelated-history, never-fetched,
# missing-branch, missing-synced or missing-pin.
splice_state() {
  local label
  label="$(splice status "$1" | sed -n '3,$p' | grep -v '^$' | head -n 1 | sed 's/^  //; s/  .*//')"
  case "$label" in
    "up to date") echo up-to-date ;;
    "unchanged, no upstream branch" | "new, ahead "* | "?? no upstream branch") echo missing-branch ;;
    "?? never fetched") echo never-fetched ;;
    "?? synced commit "*) echo missing-synced ;;
    "!! "*" isn't here") echo missing-pin ;;
    "!! unrelated history") echo unrelated-history ;;
    "diverged" | "ahead "*", behind "*) echo diverged ;;
    "ahead"*) echo push ;;
    "behind"*) echo pull ;;
    *) echo "unknown status label: $label" >&2 ;;
  esac
}

# Prints the splices git splice finds in HEAD, as the message of a command
# that needs to be told which one names them, or its refusal to read them.
discovered_splices() {
  local output
  if output="$(splice push 2>&1)"; then
    return 1
  fi
  case "$output" in
    *"(splices: "*)
      output="${output##*"(splices: "}"
      printf '%s\n' "${output%)*}"
      ;;
    *)
      printf '%s\n' "$output" >&2
      return 1
      ;;
  esac
}

# Puts a `git` first on PATH for the rest of the test, which runs shell
# code $1 before each command, with the command's arguments in "$@". The
# code may exit to replace the command. The real git is in $real_git.
stub_git() {
  local bin="$BATS_TEST_TMPDIR/stub-bin" real_git
  real_git="$(command -v git)"
  mkdir -p "$bin"
  {
    printf '#!/usr/bin/env bash\nreal_git=%q\n' "$real_git"
    printf '%s\n' "$1"
    printf 'exec "$real_git" "$@"\n'
  } >"$bin/git"
  chmod +x "$bin/git"
  PATH="$bin:$PATH"
}
