# See README.md in this directory.
scenario_init_copied_content() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git config init.defaultBranch main
    mkdir -p vendor/a
    git -C "$upstream" show main:file.txt >vendor/a/file.txt
    git add vendor/a
    git commit -q -m "copy vendor/a by hand"
  )
  # Deliberately: no remote registered yet -- cmd_init registers it itself.
}
