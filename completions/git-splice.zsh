#compdef git-splice
# Zsh completion for git-splice.
#
# Install into a directory on your $fpath as `_git-splice` (the leading
# underscore and hyphen are the convention zsh's own `_git` uses to find
# completions for third-party "git-<name>" subcommands, and are also what
# lets this file complete the standalone git-splice executable via
# #compdef above):
#
#   ln -s /path/to/git-splice.zsh /usr/local/share/zsh/site-functions/_git-splice
#
# Then start a new shell (or run `compinit`).

# Splice paths: folders with a .splice committed in HEAD, outermost only.
# Mirrors discover_splices() in lib/common.sh.
__git_splice_paths() {
  local -a files paths outermost
  local p o
  files=("${(@f)$(git ls-tree -r --name-only HEAD 2>/dev/null | grep -e '/\.splice$')}")
  paths=("${(@)files%/.splice}")
  for p in $paths; do
    for o in $paths; do
      [[ $p == $o/* ]] && continue 2
    done
    outermost+=("$p")
  done
  _describe -t paths 'splice' outermost
}

# Branches usable as --base: local and remote-tracking. Listed here rather
# than through zsh's own branch completion, which only exists once `_git`
# has been loaded -- not guaranteed when completing the standalone command.
__git_splice_branches() {
  local -a branches
  branches=("${(@f)$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)}")
  _describe -t branches 'base branch' branches
}

_git-splice() {
  local curcontext="$curcontext" state line
  local -a commands options

  commands=(
    'clone:splice an existing repository in'
    'init:make a folder a splice of an empty repository'
    'merge:splice in already-fetched upstream changes'
    'pull:fetch, then merge'
    'push:publish local changes upstream'
    'status:show each splice'\''s sync state'
    'diff:show the file changes push would send'
    'log:show the commits push and pull would move'
    'fetch:fetch the upstreams'
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
      _describe -t commands 'git splice command' commands
    fi
    return
  fi

  # _arguments counts positionals from words[2]; drop "git-splice" so the
  # command is the command name and its first argument is argument 1.
  local cmd=${words[2]}
  shift words
  ((CURRENT--))
  case $cmd in
    fetch | log)
      _arguments '(-h --help)'{-h,--help}'[show usage]' '*:splice:__git_splice_paths'
      ;;
    merge | pull)
      _arguments '--all[every splice]' '(-h --help)'{-h,--help}'[show usage]' '*:splice:__git_splice_paths'
      ;;
    status | diff)
      _arguments \
        '--base=[monorepo base branch to compare against]:branch:__git_splice_branches' \
        '(-h --help)'{-h,--help}'[show usage]' \
        '*:splice:__git_splice_paths'
      ;;
    push)
      _arguments \
        '--all[every splice]' \
        '--force[overwrite upstream'\''s branch]' \
        '--base=[monorepo base branch to compare against]:branch:__git_splice_branches' \
        '(-h --help)'{-h,--help}'[show usage]' \
        '*:splice:__git_splice_paths'
      ;;
    clone)
      _arguments \
        '--merge[merge with an existing folder]' \
        '(-h --help)'{-h,--help}'[show usage]' \
        '1:url:' \
        '2:path:_files -/'
      ;;
    init)
      _arguments \
        '(-h --help)'{-h,--help}'[show usage]' \
        '1:path:_files -/' \
        '2:url:'
      ;;
  esac
}

_git-splice "$@"
