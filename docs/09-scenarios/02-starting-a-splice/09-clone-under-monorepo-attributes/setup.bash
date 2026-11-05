# See README.md in this directory.
scenario_clone_under_monorepo_attributes() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  commit_raw_file "$upstream" build.bat 'echo build\r\n'
  commit_raw_file "$upstream" run.bat 'echo run\n'
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    printf '*.bat text eol=crlf\n' >.gitattributes
    git add .gitattributes
    git commit -q -m "CRLF for .bat"
  )
}
