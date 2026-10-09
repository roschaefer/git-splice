# Covers the completions for all three shells. bash's completion function is
# called directly, the way bash calls it: with the command line split into
# COMP_WORDS, including bash's split at "=". The "interactive bash" tests
# also run the real bash, driven through zsh; zsh and fish run the real shell.
# Tests needing zsh or fish skip when it isn't installed; `nix develop`
# provides both, and the compat matrix provides zsh.

setup() {
  load 'helpers/fixtures'
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../completions/git-splice.bash"
  init_monorepo "$BATS_TEST_TMPDIR/monorepo"
  cd "$BATS_TEST_TMPDIR/monorepo"
  add_splice_file vendor/a
}

# Commits an (empty) .splice in folder $1: enough to make it a splice for
# completion, which only lists them.
add_splice_file() {
  mkdir -p "$1"
  : >"$1/.splice"
  git add -- "$1/.splice"
  git commit -q -m "splice $1"
}

# Completes the words given as arguments; the last one is the word under the
# cursor. Prints one candidate per line.
complete_words() {
  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMPREPLY=()
  _git_splice
  printf '%s\n' "${COMPREPLY[@]}"
}

@test "completion: commands and --version at the top level" {
  run complete_words git-splice p
  [ "$output" = "pull"$'\n'"push" ]
  run complete_words git-splice --v
  [ "$output" = "--version" ]
}

@test "completion: works when dispatched by git-completion.bash" {
  run complete_words git splice push vend
  [ "$output" = "vendor/a" ]
}

@test "completion: commands complete splice paths, and no other folders" {
  mkdir -p vendor/b
  local cmd
  for cmd in merge pull push status diff log fetch; do
    run complete_words git-splice "$cmd" vend
    [ "$output" = "vendor/a" ]
  done
}

@test "completion: --all only where a command needs it" {
  run complete_words git-splice push --a
  [ "$output" = "--all" ]
  run complete_words git-splice status --a
  [ -z "$output" ]
}

@test "completion: --graph only for log" {
  run complete_words git-splice log --g
  [ "$output" = "--graph" ]
  run complete_words git-splice fetch --g
  [ -z "$output" ]
}

@test "completion: push completes branches for '--base <value>', '--base=<value>' and '--base='" {
  run complete_words git-splice push --base ma
  [ "$output" = "main" ]
  run complete_words git-splice push --base = ma
  [ "$output" = "main" ]
  run complete_words git-splice status --base =
  [ "$output" = "main" ]
}

@test "completion: push completes paths again after a '--base=<value>'" {
  run complete_words git-splice push --base = main vend
  [ "$output" = "vendor/a" ]
}

# `compgen -W` expands its word list, so a branch named like $(cmd) -- valid,
# and any remote can publish one -- would run cmd on <TAB>.
@test "completion: a branch name with a command substitution is never run" {
  local name='x$(touch${IFS}pwned)'
  git update-ref "refs/heads/$name" HEAD
  run complete_words git-splice push --base x
  [ ! -e pwned ]
  # Offered shell-quoted, so running the completed line doesn't run it either.
  [ "$output" = 'x\$\(touch\$\{IFS\}pwned\)' ]
  [ "$(eval "printf '%s' $output")" = "$name" ]
}

@test "completion: a splice path with a command substitution is never run" {
  add_splice_file 'vendor/$(touch${IFS}pwned)'
  run complete_words git-splice push 'vendor/$'
  [ ! -e pwned ]
  [ "$output" = 'vendor/\$\(touch\$\{IFS\}pwned\)' ]
}

@test "completion: clone completes a directory for the path, not for the url" {
  mkdir -p libs
  run complete_words git-splice clone li
  [ -z "$output" ]
  run complete_words git-splice clone --merge https://example.com/x.git li
  [ "$output" = "libs" ]
}

@test "completion: init completes a directory for the path, not for the url" {
  run complete_words git-splice init vend
  [ "$output" = "vendor" ]
  run complete_words git-splice init vendor/a vend
  [ -z "$output" ]
}

@test "completion: push completes branches for --rebuild, e.g. one with an edited rebuild" {
  git branch edited
  run complete_words git-splice push --reb
  [ "$output" = "--rebuild" ]
  run complete_words git-splice push --rebuild edi
  [ "$output" = "edited" ]
  run complete_words git-splice push --rebuild edited vend
  [ "$output" = "vendor/a" ]
}

@test "completion: rebuild completes one splice path" {
  run complete_words git-splice rebuild vend
  [ "$output" = "vendor/a" ]
  run complete_words git-splice rebuild vendor/a vend
  [ -z "$output" ]
}

@test "completion: key completes a splice path, and nothing for the new key" {
  run complete_words git-splice key vend
  [ "$output" = "vendor/a" ]
  run complete_words git-splice key vendor/a vend
  [ -z "$output" ]
}

@test "completion: key offers --upstream, and doesn't count its value as the path" {
  run complete_words git-splice key --up
  [ "$output" = "--upstream" ]
  run complete_words git-splice key --upstream origin vend
  [ "$output" = "vendor/a" ]
  run complete_words git-splice key --upstream vend
  [ -z "$output" ]
  run complete_words git-splice key --upstream origin vendor/a vend
  [ -z "$output" ]
}

@test "completion: init offers a directory with a command substitution quoted" {
  mkdir 'z$(touch${IFS}pwned)'
  run complete_words git-splice init z
  [ ! -e pwned ]
  [ "$output" = 'z\$\(touch\$\{IFS\}pwned\)' ]
}

# Skips the test unless shell $1 is installed. Call it outside `run`: under
# `run`, skip only ends run's subshell, and the test goes on with empty
# output.
require_shell() {
  command -v "$1" >/dev/null || skip "$1 not installed"
}

# Prints what zsh lists for a command line, one candidate per line.
zsh_complete() {
  zsh "$BATS_TEST_DIRNAME/helpers/zsh-complete.zsh" \
    "$BATS_TEST_DIRNAME/../completions/git-splice.zsh" "$1"
}

# Completes a command line with one Tab in a real interactive bash, runs
# it, and prints the arguments git-splice receives, as "[arg][arg]...".
# The harness drives bash through zsh's pty module.
bash_tab_enter() {
  zsh "$BATS_TEST_DIRNAME/helpers/bash-complete.zsh" \
    "$BATS_TEST_DIRNAME/../completions/git-splice.bash" "$1"
}

# Prints what fish completes for a command line, one candidate per line.
fish_complete() {
  LINE="$1" fish --no-config -c 'source $argv[1]; complete -C "$LINE"' \
    "$BATS_TEST_DIRNAME/../completions/git-splice.fish" | cut -f1
}

@test "zsh completion: commands" {
  require_shell zsh
  run zsh_complete "git-splice pu"
  [[ "$output" == *"pull"* && "$output" == *"push"* ]]
}

@test "zsh completion: --version at the top level, but no options before a -" {
  require_shell zsh
  run zsh_complete "git-splice --v"
  [[ "$output" == *"--version"* ]]
  run zsh_complete "git-splice pu"
  [[ "$output" != *"--version"* ]]
}

@test "zsh completion: push completes splice paths" {
  require_shell zsh
  run zsh_complete "git-splice push vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "zsh completion: init completes the path, and nothing for the url" {
  require_shell zsh
  run zsh_complete "git-splice init vend"
  [[ "$output" == *"vendor/"* ]]
  run zsh_complete "git-splice init vendor/a vend"
  [ -z "$output" ]
}

@test "zsh completion: push completes branches for --rebuild" {
  require_shell zsh
  git branch edited
  run zsh_complete "git-splice push --rebuild=edi"
  [[ "$output" == *"edited"* ]]
}

@test "zsh completion: rebuild completes one splice path" {
  require_shell zsh
  run zsh_complete "git-splice rebuild vendor/"
  [[ "$output" == *"vendor/a"* ]]
  run zsh_complete "git-splice rebuild vendor/a vend"
  [ -z "$output" ]
}

@test "zsh completion: key completes a splice path, and nothing for the new key" {
  require_shell zsh
  run zsh_complete "git-splice key vendor/"
  [[ "$output" == *"vendor/a"* ]]
  run zsh_complete "git-splice key vendor/a vend"
  [ -z "$output" ]
}

@test "zsh completion: key offers --upstream" {
  require_shell zsh
  run zsh_complete "git-splice key --up"
  [[ "$output" == *"--upstream"* ]]
}

@test "zsh completion: push completes branches for --base" {
  require_shell zsh
  run zsh_complete "git-splice push --base=ma"
  [[ "$output" == *"main"* ]]
}

@test "zsh completion: log completes --graph" {
  require_shell zsh
  run zsh_complete "git-splice log --g"
  [[ "$output" == *"--graph"* ]]
}

@test "fish completion: commands" {
  require_shell fish
  run fish_complete "git-splice pu"
  [[ "$output" == *"pull"* && "$output" == *"push"* ]]
}

@test "fish completion: --version at the top level" {
  require_shell fish
  run fish_complete "git-splice --v"
  [ "$output" = "--version" ]
}

@test "fish completion: push completes splice paths" {
  require_shell fish
  run fish_complete "git-splice push vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "fish completion: init completes the path, and nothing for the url" {
  require_shell fish
  run fish_complete "git-splice init vend"
  [[ "$output" == *"vendor/"* ]]
  run fish_complete "git-splice init vendor/a vend"
  [ -z "$output" ]
}

@test "fish completion: push completes branches for --rebuild" {
  require_shell fish
  git branch edited
  run fish_complete "git-splice push --rebuild edi"
  [[ "$output" == *"edited"* ]]
}

@test "fish completion: rebuild completes one splice path" {
  require_shell fish
  run fish_complete "git-splice rebuild vendor/"
  [[ "$output" == *"vendor/a"* ]]
  run fish_complete "git-splice rebuild vendor/a vend"
  [ -z "$output" ]
}

@test "fish completion: key completes a splice path, and nothing for the new key" {
  require_shell fish
  run fish_complete "git-splice key vendor/"
  [[ "$output" == *"vendor/a"* ]]
  run fish_complete "git-splice key vendor/a vend"
  [ -z "$output" ]
}

@test "fish completion: key offers --upstream, and doesn't count its value as the path" {
  require_shell fish
  run fish_complete "git-splice key --up"
  [ "$output" = "--upstream" ]
  run fish_complete "git-splice key --upstream origin vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "fish completion: push completes branches for --base" {
  require_shell fish
  run fish_complete "git-splice push --base ma"
  [[ "$output" == *"main"* ]]
}

@test "fish completion: log completes --graph" {
  require_shell fish
  run fish_complete "git-splice log --g"
  [ "$output" = "--graph" ]
}

@test "interactive bash: Tab completes a splice path" {
  require_shell zsh
  run bash_tab_enter "git-splice push vend"
  [ "$output" = "[push][vendor/a]" ]
}

@test "interactive bash: Tab completes the branch in all three --base forms" {
  require_shell zsh
  run bash_tab_enter "git-splice push --base ma"
  [ "$output" = "[push][--base][main]" ]
  run bash_tab_enter "git-splice push --base=ma"
  [ "$output" = "[push][--base=main]" ]
  run bash_tab_enter "git-splice push --base="
  [ "$output" = "[push][--base=main]" ]
}

@test "interactive bash: a completed branch name with a command substitution runs neither on Tab nor on Enter" {
  require_shell zsh
  git update-ref 'refs/heads/x$(touch${IFS}pwned)' HEAD
  run bash_tab_enter "git-splice push --base x"
  [ ! -e pwned ]
  [ "$output" = '[push][--base][x$(touch${IFS}pwned)]' ]
}

@test "interactive bash: a completed directory with a command substitution isn't run" {
  require_shell zsh
  mkdir 'z$(touch${IFS}pwned)'
  run bash_tab_enter "git-splice init z"
  [ ! -e pwned ]
  [ "$output" = '[init][z$(touch${IFS}pwned)]' ]
}
