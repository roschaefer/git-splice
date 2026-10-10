# Fish completion for git-splice.
#
# Fish already completes any `git-<name>` executable on $PATH as `git
# <name>` (see __fish_git_custom_commands / __fish_git_complete_custom_command
# in fish's own git completions), delegating to whatever's registered for
# the standalone command. So this file, once installed, completes both
# `git-splice ...` and `git splice ...`.
#
# Install:
#   ln -s /path/to/git-splice.fish ~/.config/fish/completions/git-splice.fish

# Splice paths: folders with a .splice committed in HEAD. Mirrors
# discover_splices() in lib/common.sh.
function __git_splice_paths
    for file in (git diff-tree -r --name-only -z (git hash-object -t tree /dev/null) HEAD -- ':(top,glob)*/**/.splice' 2>/dev/null | string split0)
        string replace -r '/\.splice$' '' -- $file
    end
end

# True while the word being completed is positional argument number $argv[2]
# (counting from 0) of command $argv[1], options and the value after
# --upstream not counted.
function __git_splice_positional
    set -l seen 0
    set -l count 0
    set -l skip 0
    for token in (commandline -opc)
        if test $seen = 0
            test "$token" = $argv[1]; and set seen 1
            continue
        end
        if test $skip = 1
            set skip 0
            continue
        end
        switch $token
            case --upstream
                set skip 1
            case '-*'
            case '*'
                set count (math $count + 1)
        end
    end
    test $seen = 1 -a $count = $argv[2]
end

set -l commands clone init fetch merge pull push status diff log boundary key
set -l branches "(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)"

complete -c git-splice -f

complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a clone -d 'splice an existing repository in'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a init -d 'make a folder a splice of an empty repository'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a merge -d 'splice in already-fetched upstream changes'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a pull -d 'fetch, then merge'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a push -d 'publish local changes upstream'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a status -d "show each splice's sync state"
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a diff -d 'show the file changes push would send'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a log -d 'show the commits push and pull would move'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a boundary -d 'print the monorepo commit where a splice last synced'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a fetch -d 'fetch the upstreams'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -a key -d "print or rename the key of a splice's fetched refs"
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -s h -l help -d 'show usage'
complete -c git-splice -n "not __fish_seen_subcommand_from $commands" -l version -d 'show version'

complete -c git-splice -n "__fish_seen_subcommand_from $commands" -s h -l help -d 'show usage'
complete -c git-splice -n "__fish_seen_subcommand_from merge pull push status diff log fetch" -a "(__git_splice_paths)" -d splice
complete -c git-splice -n "__fish_seen_subcommand_from merge pull push" -l all -d 'every splice'
complete -c git-splice -n "__fish_seen_subcommand_from push status diff" -l base -x -a $branches -d 'monorepo base branch to compare against'
complete -c git-splice -n "__fish_seen_subcommand_from push" -l force -d "overwrite upstream's branch"
complete -c git-splice -n "__fish_seen_subcommand_from log" -l graph -d 'draw both sides as a graph'
complete -c git-splice -n "__fish_seen_subcommand_from clone" -l merge -d 'merge with an existing folder'
complete -c git-splice -n "__git_splice_positional clone 1" -a "(__fish_complete_directories)"
complete -c git-splice -n "__git_splice_positional init 0" -a "(__fish_complete_directories)"
complete -c git-splice -n "__git_splice_positional boundary 0" -a "(__git_splice_paths)" -d splice
complete -c git-splice -n "__git_splice_positional key 0" -a "(__git_splice_paths)" -d splice
complete -c git-splice -n "__fish_seen_subcommand_from key" -l upstream -x -d 'upstream named in .splice'
