# See README.md in this directory.
scenario_clone_differing_content() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "only upstream" main upstream.txt
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    mkdir -p vendor/a
    echo "local version" >vendor/a/file.txt
    echo "only local" >vendor/a/local.txt
    git add vendor/a
    git commit -q -m "vendor/a, maintained by hand"
  )
}
