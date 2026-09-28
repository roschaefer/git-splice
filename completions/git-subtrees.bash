# Bash completion for git-subtrees.
#
# Works both as a `git subtrees ...` completion (git-completion.bash
# dispatches to a function named _git_subtrees for the "subtrees"
# subcommand) and as a standalone completion for the git-subtrees
# executable itself, so it's safe to source unconditionally.
#
# Install (pick one):
#   source /path/to/git-subtrees.bash        # e.g. from ~/.bashrc
#   cp /path/to/git-subtrees.bash /etc/bash_completion.d/git-subtrees

# Subtree paths: git remotes whose name matches an existing directory.
# Mirrors discover_subtrees() in lib/common.sh.
__git_subtrees_paths() {
  local remote
  while IFS= read -r remote; do
    [[ -n "$remote" && -d "$remote" ]] && printf '%s\n' "$remote"
  done < <(git remote 2>/dev/null)
}

# Sets COMPREPLY to the lines on stdin that start with $1, shell-quoted.
# Branch names, subtree paths and directory names can come from a remote or
# a cloned repo, so they never go through `compgen -W`: it expands its word
# list, and a branch named like origin/$(cmd) -- a valid name that any
# remote can publish -- would run cmd on <TAB>. Quoting keeps such a name
# from running when the completed command line is executed.
__git_subtrees_reply() {
  local prefix="$1" word quoted
  COMPREPLY=()
  while IFS= read -r word; do
    [[ -n "$word" && "$word" == "$prefix"* ]] || continue
    printf -v quoted '%q' "$word"
    COMPREPLY+=("$quoted")
  done
}

# Branches usable as --base: local and remote-tracking.
__git_subtrees_branches() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

# True if the word being completed is --base's value. bash splits words at
# "=" (it's in COMP_WORDBREAKS), so the value can follow "--base" or
# "--base =", and for "--base=" the current word is the "=" itself. Sets
# base_prefix to the part of the value typed so far.
__git_subtrees_completing_base() {
  local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD - 1]:-}"
  base_prefix="$cur"
  if [[ "$prev" == --base ]]; then
    [[ "$cur" == = ]] && base_prefix=""
    return 0
  fi
  [[ "$prev" == = && "${COMP_WORDS[COMP_CWORD - 2]:-}" == --base ]]
}

# Counts the positional arguments before the word being completed, skipping
# options and --base's value (bash may split "--base=main" into "--base",
# "=" and "main"). $1 is the index of the subcommand in COMP_WORDS.
__git_subtrees_positionals() {
  local i count=0
  for ((i = $1 + 1; i < COMP_CWORD; i++)); do
    case "${COMP_WORDS[i]}" in
      --base)
        [[ "${COMP_WORDS[i + 1]:-}" == = ]] && ((i++))
        ((i++))
        ;;
      -*) ;;
      *) ((count++)) ;;
    esac
  done
  printf '%s\n' "$count"
}

_git_subtrees() {
  local cur start cmd base_prefix
  cur="${COMP_WORDS[COMP_CWORD]}"

  # Skip past "git subtrees" when dispatched by git-completion.bash, or
  # just "git-subtrees" when this command is completed directly.
  start=1
  [[ "${COMP_WORDS[0]}" == git ]] && start=2

  if ((COMP_CWORD == start)); then
    mapfile -t COMPREPLY < <(compgen -W "diff init fetch merge pull prune push status -h --help --version" -- "$cur")
    return
  fi

  cmd="${COMP_WORDS[start]}"
  case "$cmd" in
    fetch | merge | pull)
      __git_subtrees_reply "$cur" < <(
        __git_subtrees_paths
        printf '%s\n' -h --help
      )
      ;;
    diff | push | status)
      if __git_subtrees_completing_base; then
        __git_subtrees_reply "$base_prefix" < <(__git_subtrees_branches)
      else
        __git_subtrees_reply "$cur" < <(
          __git_subtrees_paths
          printf '%s\n' --base -h --help
        )
      fi
      ;;
    prune)
      __git_subtrees_reply "$cur" < <(
        __git_subtrees_paths
        printf '%s\n' -n --dry-run -h --help
      )
      ;;
    init)
      if __git_subtrees_completing_base; then
        __git_subtrees_reply "$base_prefix" < <(__git_subtrees_branches)
      elif [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "--base -h --help" -- "$cur")
      elif (($(__git_subtrees_positionals "$start") == 0)); then
        # compgen -d only lists matching directories; quote them like the rest.
        __git_subtrees_reply "" < <(compgen -d -- "$cur")
      fi
      ;;
    *) ;;
  esac
}

complete -o bashdefault -o default -F _git_subtrees git-subtrees 2>/dev/null
