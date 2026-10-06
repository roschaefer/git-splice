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
# refs/splices/upstream/, recording the upstream's key first if it has none,
# as the commands do.
upstream_refs() {
  (
    # shellcheck source=../../lib/common.sh
    source "$FIXTURES_DIR/../../lib/common.sh"
    create_upstream_key "$1"
    printf 'refs/splices/%s/\n' "$UPSTREAM_KEY"
  )
}

# Fetches every branch of upstream $2 into monorepo $1's refs, like `git
# splice fetch` does for a splice with that URL. ($3, the splice's path,
# doesn't matter: refs are keyed by URL.)
fetch_splice() {
  local monorepo="$1" url="$2" prefix
  prefix="$(cd "$monorepo" && upstream_refs "$url")"
  git -C "$monorepo" fetch -q --no-tags --prune -- "$url" "+refs/heads/*:$prefix*"
}

# Splices branch $4 (default: main) of upstream $2 into $3 inside monorepo
# $1 via raw git plumbing -- deliberately NOT via cmd_clone, so other
# commands' tests don't depend on clone's own correctness.
add_splice() {
  local monorepo="$1" url="$2" path="$3" branch="${4:-main}" commit
  fetch_splice "$monorepo" "$url" "$path"
  (
    cd "$monorepo"
    commit="$(git rev-parse "$(upstream_refs "$url")$branch")"
    git read-tree --prefix="$path/" -u "$commit"
    printf '[splice]\n\tcommit = %s\n[upstream "origin"]\n\turl = %s\n' "$commit" "$url" >"$path/.splice"
    git add "$path"
    git commit -q -m "add $path"
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
# so tests about how the base branch is resolved behave the same everywhere.
# Bats runs each test in its own subshell, so this never leaks.
hermetic_git_config() {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
}

# Sources every lib/*.sh file so tests can call functions directly, mirroring
# the order the real entrypoint uses.
load_lib() {
  local lib_dir="$BATS_TEST_DIRNAME/../lib" file
  for file in common rebuild state pager clone init fetch merge pull push status diff log key; do
    # shellcheck disable=SC1090
    source "$lib_dir/$file.sh"
  done
}
