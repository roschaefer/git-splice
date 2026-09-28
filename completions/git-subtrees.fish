# Fish completion for git-subtrees.
#
# Fish already completes any `git-<name>` executable on $PATH as `git
# <name>` (see __fish_git_custom_commands / __fish_git_complete_custom_command
# in fish's own git completions), delegating to whatever's registered for
# the standalone command. So this file, once installed, completes both
# `git-subtrees ...` and `git subtrees ...`.
#
# Install:
#   ln -s /path/to/git-subtrees.fish ~/.config/fish/completions/git-subtrees.fish

# Subtree paths: git remotes whose name matches an existing directory.
# Mirrors discover_subtrees() in lib/common.sh.
function __git_subtrees_paths
    for remote in (git remote 2>/dev/null)
        if test -d $remote
            echo $remote
        end
    end
end

# True while the word being completed is init's first positional argument
# (the path): options and --base's value don't count, and the word right
# after --base is its value, not the path.
function __git_subtrees_init_needs_path
    set -l seen_init 0
    set -l count 0
    set -l skip 0
    for token in (commandline -opc)
        if test $seen_init = 0
            test "$token" = init; and set seen_init 1
            continue
        end
        if test $skip = 1
            set skip 0
            continue
        end
        switch $token
            case --base
                set skip 1
            case '-*'
            case '*'
                set count (math $count + 1)
        end
    end
    test $seen_init = 1 -a $count = 0 -a $skip = 0
end

set -l commands diff init fetch merge pull prune push status

complete -c git-subtrees -f

complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a diff -d 'show file changes that push would send'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a init -d 'bootstrap a path/url pair'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a fetch -d "fetch every subtree's remote"
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a merge -d 'squash-merge fetched changes'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a pull -d 'fetch, then merge'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a prune -d 'prune stale remote-tracking refs'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a push -d 'push local subtree changes'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -a status -d 'show sync state'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -s h -l help -d 'show usage'
complete -c git-subtrees -n "not __fish_seen_subcommand_from $commands" -l version -d 'show version'

complete -c git-subtrees -n "__fish_seen_subcommand_from diff fetch merge pull push status" -a "(__git_subtrees_paths)" -d 'subtree path'
complete -c git-subtrees -n "__fish_seen_subcommand_from diff fetch merge pull push status" -s h -l help -d 'show usage'
complete -c git-subtrees -n "__fish_seen_subcommand_from diff push status" -l base -x -a "(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)" -d 'monorepo base branch to compare against'
complete -c git-subtrees -n "__fish_seen_subcommand_from prune" -a "(__git_subtrees_paths)" -d 'subtree path'
complete -c git-subtrees -n "__fish_seen_subcommand_from prune" -s n -l dry-run -d 'show stale refs without pruning'
complete -c git-subtrees -n "__fish_seen_subcommand_from prune" -s h -l help -d 'show usage'

complete -c git-subtrees -n "__fish_seen_subcommand_from init" -s h -l help -d 'show usage'
complete -c git-subtrees -n "__fish_seen_subcommand_from init" -l base -x -a "(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null)" -d 'monorepo base branch to add from'
complete -c git-subtrees -n __git_subtrees_init_needs_path -a "(__fish_complete_directories)"
