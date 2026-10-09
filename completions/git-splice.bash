# Bash completion for git-splice.
#
# Works both as a `git splice ...` completion (git-completion.bash
# dispatches to a function named _git_splice for the "splice" subcommand)
# and as a standalone completion for the git-splice executable itself, so
# it's safe to source unconditionally.
#
# Install (pick one):
#   source /path/to/git-splice.bash        # e.g. from ~/.bashrc
#   cp /path/to/git-splice.bash /etc/bash_completion.d/git-splice

# Splice paths: folders with a .splice committed in HEAD. Mirrors
# discover_splices() in lib/common.sh.
__git_splice_paths() {
  local file
  while IFS= read -r -d '' file; do
    printf '%s\n' "${file%/.splice}"
  done < <(git diff-tree -r --name-only -z "$(git hash-object -t tree /dev/null)" HEAD -- ':(top,glob)*/**/.splice' 2>/dev/null)
}

# Sets COMPREPLY to the lines on stdin that start with $1, shell-quoted.
# Branch names, splice paths and directory names can come from an upstream
# or a cloned repo, so they never go through `compgen -W`: it expands its
# word list, and a branch named like origin/$(cmd) -- a valid name that any
# remote can publish -- would run cmd on <TAB>. Quoting keeps such a name
# from running when the completed command line is executed.
__git_splice_reply() {
  local prefix="$1" word quoted
  COMPREPLY=()
  while IFS= read -r word; do
    [[ -n "$word" && "$word" == "$prefix"* ]] || continue
    printf -v quoted '%q' "$word"
    COMPREPLY+=("$quoted")
  done
}

# Branches usable as --base: local and remote-tracking.
__git_splice_branches() {
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null
}

# True if the word being completed is --base's value. bash splits words at
# "=" (it's in COMP_WORDBREAKS), so the value can follow "--base" or
# "--base =", and for "--base=" the current word is the "=" itself. Sets
# base_prefix to the part of the value typed so far.
__git_splice_completing_base() {
  local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD - 1]:-}"
  base_prefix="$cur"
  if [[ "$prev" == --base ]]; then
    [[ "$cur" == = ]] && base_prefix=""
    return 0
  fi
  [[ "$prev" == = && "${COMP_WORDS[COMP_CWORD - 2]:-}" == --base ]]
}

# Counts the positional arguments before the word being completed, skipping
# options. $1 is the index of the subcommand in COMP_WORDS.
__git_splice_positionals() {
  local i count=0
  for ((i = $1 + 1; i < COMP_CWORD; i++)); do
    case "${COMP_WORDS[i]}" in
      -*) ;;
      *) ((count++)) ;;
    esac
  done
  printf '%s\n' "$count"
}

# Completes splice paths, or one of the options $2... when the current word
# starts with "-".
__git_splice_paths_or_options() {
  local cur="$1"
  shift
  __git_splice_reply "$cur" < <(
    __git_splice_paths
    printf '%s\n' "$@"
  )
}

_git_splice() {
  local cur start cmd base_prefix
  cur="${COMP_WORDS[COMP_CWORD]}"

  # Skip past "git splice" when dispatched by git-completion.bash, or just
  # "git-splice" when this command is completed directly.
  start=1
  [[ "${COMP_WORDS[0]}" == git ]] && start=2

  if ((COMP_CWORD == start)); then
    mapfile -t COMPREPLY < <(compgen -W "clone init fetch merge pull push status diff log rebuild key -h --help --version" -- "$cur")
    return
  fi

  cmd="${COMP_WORDS[start]}"
  case "$cmd" in
    fetch)
      __git_splice_paths_or_options "$cur" -h --help
      ;;
    log)
      __git_splice_paths_or_options "$cur" --graph -h --help
      ;;
    merge | pull)
      __git_splice_paths_or_options "$cur" --all -h --help
      ;;
    push | status | diff)
      if __git_splice_completing_base; then
        __git_splice_reply "$base_prefix" < <(__git_splice_branches)
      elif [[ "$cmd" == push ]]; then
        __git_splice_paths_or_options "$cur" --all --base --force -h --help
      else
        __git_splice_paths_or_options "$cur" --base -h --help
      fi
      ;;
    clone)
      if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "--merge -h --help" -- "$cur")
      elif (($(__git_splice_positionals "$start") == 1)); then
        # compgen -d only lists matching directories; quote them like the rest.
        __git_splice_reply "" < <(compgen -d -- "$cur")
      fi
      ;;
    init)
      if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "-h --help" -- "$cur")
      elif (($(__git_splice_positionals "$start") == 0)); then
        __git_splice_reply "" < <(compgen -d -- "$cur")
      fi
      ;;
    rebuild)
      if [[ "$cur" == -* ]] || (($(__git_splice_positionals "$start") == 0)); then
        __git_splice_paths_or_options "$cur" -h --help
      fi
      ;;
    key)
      # The word after --upstream is the upstream's name, not a positional.
      local i positionals=0
      for ((i = start + 1; i < COMP_CWORD; i++)); do
        case "${COMP_WORDS[i]}" in
          --upstream) ((i++)) ;;
          -*) ;;
          *) ((positionals++)) ;;
        esac
      done
      if [[ "${COMP_WORDS[COMP_CWORD - 1]}" == --upstream ]]; then
        :
      elif [[ "$cur" == -* ]] || ((positionals == 0)); then
        __git_splice_paths_or_options "$cur" --upstream -h --help
      fi
      ;;
    *) ;;
  esac
}

complete -o bashdefault -o default -F _git_splice git-splice 2>/dev/null
