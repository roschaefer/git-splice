# See README.md in this directory.

scenario_bisect_into_a_pull() {
  local monorepo="$1" upstream="$2" lib
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  (
    cd "$monorepo"
    printf '#!/bin/sh\n# Production forbids debug logging.\n! grep -q "level = debug" vendor/a/config.txt 2>/dev/null\n' >check.sh
    chmod +x check.sh
    git add check.sh
    git commit -q -m "add check.sh"
  )
  lib="$(mktemp -d)"
  git clone -q "$upstream" "$lib" 2>/dev/null
  (
    cd "$lib"
    git config user.name "Upstream"
    git config user.email "upstream@example.com"
    echo "level = info" >config.txt
    git add config.txt
    git commit -q -m "add config.txt"
    echo "level = debug" >config.txt
    git commit -q -am "log at debug level"
    echo "seed, fixed" >file.txt
    git commit -q -am "fix a typo"
    git push -q origin main
  )
  (
    cd "$monorepo"
    splice pull vendor/a
    echo "notes" >notes.txt
    git add notes.txt
    git commit -q -m "add notes"
  )
}
