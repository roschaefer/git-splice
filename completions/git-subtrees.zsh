#compdef git-subtrees
# Zsh completion for git-subtrees.
#
# Install into a directory on your $fpath as `_git-subtrees` (the leading
# underscore and hyphen are the convention zsh's own `_git` uses to find
# completions for third-party "git-<name>" subcommands, and are also what
# lets this file complete the standalone git-subtrees executable via
# #compdef above):
#
#   ln -s /path/to/git-subtrees.zsh /usr/local/share/zsh/site-functions/_git-subtrees
#
# Then start a new shell (or run `compinit`).

# Subtree paths: git remotes whose name matches an existing directory.
# Mirrors discover_subtrees() in lib/common.sh.
__git_subtrees_paths() {
  local remote
  git remote 2>/dev/null | while IFS= read -r remote; do
    [[ -n "$remote" && -d "$remote" ]] && print -r -- "$remote"
  done
}

# Branches usable as --base: local and remote-tracking. Listed here rather
# than through zsh's own __git_subtrees_branches, which only exists once `_git`
# has been loaded -- not guaranteed when completing the standalone command.
__git_subtrees_branches() {
  local -a branches
  branches=("${(@f)$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)}")
  _describe -t branches 'base branch' branches
}

_git-subtrees() {
  local curcontext="$curcontext" state line
  local -a commands options paths

  commands=(
    'diff:show file changes that push would send'
    'init:one-time bootstrap of a path/url pair'
    'fetch:fetch every subtree'\''s remote'
    'merge:squash-merge fetched changes into subtree paths'
    'pull:fetch, then merge'
    'prune:prune stale remote-tracking refs'
    'push:push local subtree changes upstream'
    'status:show sync state of every remote'
  )

  options=(
    '-h:show usage'
    '--help:show usage'
    '--version:show version'
  )

  if ((CURRENT == 2)); then
    if [[ $PREFIX == -* ]]; then
      _describe -t options 'option' options
    else
      _describe -t commands 'git subtrees command' commands
    fi
    return
  fi

  case ${words[2]} in
    fetch | merge | pull)
      paths=("${(@f)$(__git_subtrees_paths)}")
      _describe -t paths 'subtree path' paths
      ;;
    diff | push | status)
      paths=("${(@f)$(__git_subtrees_paths)}")
      _arguments \
        '--base=[monorepo base branch to compare against]:branch:__git_subtrees_branches' \
        '(-h --help)'{-h,--help}'[show usage]' \
        '*:subtree path:->paths'
      if [[ $state == paths ]]; then
        _describe -t paths 'subtree path' paths
      fi
      ;;
    prune)
      paths=("${(@f)$(__git_subtrees_paths)}")
      _arguments \
        '(-n --dry-run)'{-n,--dry-run}'[show stale refs without pruning]' \
        '(-h --help)'{-h,--help}'[show usage]' \
        '*:subtree path:->paths'
      if [[ $state == paths ]]; then
        _describe -t paths 'subtree path' paths
      fi
      ;;
    init)
      # _arguments counts positionals from words[2]; drop "git-subtrees" so
      # "init" is the command name and the path is argument 1.
      shift words
      ((CURRENT--))
      _arguments \
        '--base=[monorepo base branch to add from when the remote lacks the current one]:branch:__git_subtrees_branches' \
        '(-h --help)'{-h,--help}'[show usage]' \
        '1:subtree path:_files -/' \
        '2:url:'
      ;;
  esac
}

_git-subtrees "$@"
