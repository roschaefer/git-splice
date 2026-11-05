# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_upstream_macro() {
  local monorepo="$1" upstream="$2"
  scenario_clone_from_submodule "$@"
  commit_raw_file "$upstream" .gitattributes '[attr]crlf-text text eol=crlf\n*.bat crlf-text\n'
  commit_raw_file "$upstream" run.bat 'echo run\n'
  (
    cd "$monorepo"
    git -C vendor/a pull -q
    git commit -q -m "vendor/a with run.bat" vendor/a
  )
}
