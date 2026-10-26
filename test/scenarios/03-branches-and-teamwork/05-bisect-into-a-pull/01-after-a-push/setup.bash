# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_after_a_push() {
  local monorepo="$1" upstream="$2" lib
  scenario_bisect_into_a_pull "$monorepo" "$upstream"
  (
    cd "$monorepo"
    echo "a local line" >>vendor/a/file.txt
    git commit -q -am "e: a local change in vendor/a"
    splice push vendor/a
  )
  lib="$(mktemp -d)"
  git clone -q "$upstream" "$lib" 2>/dev/null
  (
    cd "$lib"
    git config user.name "Upstream"
    git config user.email "upstream@example.com"
    echo "an upstream file" >upstream.txt
    git add upstream.txt
    git commit -q -m "o: add upstream.txt"
    git push -q origin main
  )
  (cd "$monorepo" && splice pull vendor/a)
}
