# Covers the completions for all three shells. bash's completion function is
# called directly, the way bash calls it: with the command line split into
# COMP_WORDS, including bash's split at "=". The "interactive bash" tests
# also run the real bash, driven through zsh; zsh and fish run the real shell.
# Tests needing zsh or fish skip when it isn't installed; `nix develop`
# provides both, and the compat matrix provides zsh.

setup() {
  load 'helpers/fixtures'
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../completions/git-subtrees.bash"
  init_monorepo "$BATS_TEST_TMPDIR/monorepo"
  cd "$BATS_TEST_TMPDIR/monorepo"
  mkdir -p vendor/a
  git remote add vendor/a "$BATS_TEST_TMPDIR/unused.git"
}

# Completes the words given as arguments; the last one is the word under the
# cursor. Prints one candidate per line.
complete_words() {
  COMP_WORDS=("$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  COMPREPLY=()
  _git_subtrees
  printf '%s\n' "${COMPREPLY[@]}"
}

@test "completion: push completes subtree paths" {
  run complete_words git-subtrees push vend
  [ "$output" = "vendor/a" ]
}

@test "completion: push completes branches for '--base <value>'" {
  run complete_words git-subtrees push --base ma
  [ "$output" = "main" ]
}

# bash passes "--base=ma" as "--base", "=", "ma".
@test "completion: push completes branches for '--base=<value>'" {
  run complete_words git-subtrees push --base = ma
  [ "$output" = "main" ]
}

# bash passes "--base=" as "--base", "=", with "=" as the current word.
@test "completion: push completes branches right after '--base='" {
  run complete_words git-subtrees push --base =
  [ "$output" = "main" ]
}

@test "completion: diff and status complete branches for '--base=<value>'" {
  run complete_words git-subtrees diff --base = ma
  [ "$output" = "main" ]
  run complete_words git-subtrees status --base = ma
  [ "$output" = "main" ]
}

@test "completion: push completes paths again after a '--base=<value>'" {
  run complete_words git-subtrees push --base = main vend
  [ "$output" = "vendor/a" ]
}

# `compgen -W` expands its word list, so a branch named like $(cmd) -- valid,
# and any remote can publish one -- would run cmd on <TAB>.
@test "completion: a branch name with a command substitution is never run" {
  local name='x$(touch${IFS}pwned)'
  git update-ref "refs/heads/$name" HEAD

  run complete_words git-subtrees push --base x
  [ ! -e pwned ]
  # Offered shell-quoted, so running the completed line doesn't run it either.
  [ "$output" = 'x\$\(touch\$\{IFS\}pwned\)' ]
  [ "$(eval "printf '%s' $output")" = "$name" ]
}

@test "completion: a subtree path with a command substitution is never run" {
  local name='vendor/$(touch${IFS}pwned)'
  mkdir -p "$name"
  git remote add "$name" "$BATS_TEST_TMPDIR/unused.git"

  run complete_words git-subtrees push 'vendor/$'
  [ ! -e pwned ]
  [ "$output" = 'vendor/\$\(touch\$\{IFS\}pwned\)' ]
}

@test "completion: init offers a directory with a command substitution quoted" {
  mkdir 'z$(touch${IFS}pwned)'
  run complete_words git-subtrees init z
  [ ! -e pwned ]
  [ "$output" = 'z\$\(touch\$\{IFS\}pwned\)' ]
}

@test "completion: init completes a directory as its first argument" {
  run complete_words git-subtrees init vend
  [[ "$output" == *"vendor"* ]]
}

@test "completion: init completes the path after --base and its value" {
  run complete_words git-subtrees init --base main vend
  [[ "$output" == *"vendor"* ]]
}

@test "completion: init completes the path after --base=<value> split by bash" {
  run complete_words git-subtrees init --base = main vend
  [[ "$output" == *"vendor"* ]]
}

@test "completion: init offers no directory for the url" {
  run complete_words git-subtrees init --base main vendor/a vend
  [ -z "$output" ]
}

@test "completion: init completes branches after --base" {
  run complete_words git-subtrees init --base ma
  [[ "$output" == *"main"* ]]
}

@test "completion: init completes branches for '--base=<value>' and right after '--base='" {
  run complete_words git-subtrees init --base = ma
  [ "$output" = "main" ]
  run complete_words git-subtrees init --base =
  [ "$output" = "main" ]
}

@test "completion: init never runs a branch name with a command substitution" {
  git update-ref 'refs/heads/x$(touch${IFS}pwned)' HEAD
  run complete_words git-subtrees init --base x
  [ ! -e pwned ]
  [ "$output" = 'x\$\(touch\$\{IFS\}pwned\)' ]
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
    "$BATS_TEST_DIRNAME/../completions/git-subtrees.zsh" "$1"
}

# Completes a command line with one Tab in a real interactive bash, runs
# it, and prints the arguments git-subtrees receives, as "[arg][arg]...".
# The harness drives bash through zsh's pty module.
bash_tab_enter() {
  zsh "$BATS_TEST_DIRNAME/helpers/bash-complete.zsh" \
    "$BATS_TEST_DIRNAME/../completions/git-subtrees.bash" "$1"
}

# Prints what fish completes for a command line, one candidate per line.
fish_complete() {
  LINE="$1" fish --no-config -c 'source $argv[1]; complete -C "$LINE"' \
    "$BATS_TEST_DIRNAME/../completions/git-subtrees.fish" | cut -f1
}

@test "zsh completion: subcommands" {
  require_shell zsh
  run zsh_complete "git-subtrees pu"
  [[ "$output" == *"pull"* && "$output" == *"push"* ]]
}

@test "zsh completion: push completes subtree paths" {
  require_shell zsh
  run zsh_complete "git-subtrees push vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "zsh completion: init completes the path, also after --base" {
  require_shell zsh
  run zsh_complete "git-subtrees init vend"
  [[ "$output" == *"vendor/"* ]]
  run zsh_complete "git-subtrees init --base main vend"
  [[ "$output" == *"vendor/"* ]]
  run zsh_complete "git-subtrees init --base=main vend"
  [[ "$output" == *"vendor/"* ]]
}

@test "zsh completion: init offers no directory for the url" {
  require_shell zsh
  run zsh_complete "git-subtrees init vendor/a vend"
  [ -z "$output" ]
}

@test "zsh completion: init completes branches for --base" {
  require_shell zsh
  run zsh_complete "git-subtrees init --base=ma"
  [[ "$output" == *"main"* ]]
}

@test "fish completion: subcommands" {
  require_shell fish
  run fish_complete "git-subtrees pu"
  [[ "$output" == *"pull"* && "$output" == *"push"* ]]
}

@test "fish completion: push completes subtree paths" {
  require_shell fish
  run fish_complete "git-subtrees push vendor/"
  [[ "$output" == *"vendor/a"* ]]
}

@test "fish completion: init completes the path, also after --base" {
  require_shell fish
  run fish_complete "git-subtrees init vend"
  [[ "$output" == *"vendor/"* ]]
  run fish_complete "git-subtrees init --base main vend"
  [[ "$output" == *"vendor/"* ]]
  run fish_complete "git-subtrees init --base=main vend"
  [[ "$output" == *"vendor/"* ]]
}

@test "fish completion: init offers no directory for the url" {
  require_shell fish
  run fish_complete "git-subtrees init vendor/a vend"
  [ -z "$output" ]
}

@test "fish completion: init completes branches for --base" {
  require_shell fish
  run fish_complete "git-subtrees init --base ma"
  [[ "$output" == *"main"* ]]
}

@test "interactive bash: Tab completes a subtree path" {
  require_shell zsh
  run bash_tab_enter "git-subtrees push vend"
  [ "$output" = "[push][vendor/a]" ]
}

@test "interactive bash: Tab completes the branch in all three --base forms" {
  require_shell zsh
  run bash_tab_enter "git-subtrees push --base ma"
  [ "$output" = "[push][--base][main]" ]
  run bash_tab_enter "git-subtrees push --base=ma"
  [ "$output" = "[push][--base=main]" ]
  run bash_tab_enter "git-subtrees push --base="
  [ "$output" = "[push][--base=main]" ]
  run bash_tab_enter "git-subtrees init --base=ma"
  [ "$output" = "[init][--base=main]" ]
}

@test "interactive bash: a completed branch name with a command substitution runs neither on Tab nor on Enter" {
  require_shell zsh
  git update-ref 'refs/heads/x$(touch${IFS}pwned)' HEAD
  run bash_tab_enter "git-subtrees push --base x"
  [ ! -e pwned ]
  [ "$output" = '[push][--base][x$(touch${IFS}pwned)]' ]
}

@test "interactive bash: a completed directory with a command substitution isn't run" {
  require_shell zsh
  mkdir 'z$(touch${IFS}pwned)'
  run bash_tab_enter "git-subtrees init z"
  [ ! -e pwned ]
  [ "$output" = '[init][z$(touch${IFS}pwned)]' ]
}
