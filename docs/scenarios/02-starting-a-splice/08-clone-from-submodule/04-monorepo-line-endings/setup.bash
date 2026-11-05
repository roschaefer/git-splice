# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_monorepo_line_endings() {
  local monorepo="$1" upstream="$2"
  scenario_clone_from_submodule "$@"
  commit_raw_file "$upstream" build.bat 'echo build\r\n'
  commit_raw_file "$upstream" run.bat 'echo run\n'
  (
    cd "$monorepo"
    git -C vendor/a pull -q
    printf '*.bat text eol=crlf\n' >.gitattributes
    git add .gitattributes vendor/a
    git commit -q -m "CRLF for .bat, vendor/a with its scripts"
  )
}
