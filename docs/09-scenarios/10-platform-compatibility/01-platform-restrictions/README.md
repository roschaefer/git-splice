# Scenario: non-UTF-8 input

Some repositories created by older tools contain names encoded in a legacy
character set. `git-splice` currently refuses non-UTF-8 arguments, paths and
commit author/committer identities rather than silently changing them.
Commit messages do not have this restriction.
See [known bugs and restrictions](../../99-known-bugs.md#input-and-platform-restrictions).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds a splice with one local commit to publish:

```scrut
$ build_scenario scenario_platform_restrictions
```

### An argument encoded in Latin-1

The byte `e9` represents an accented letter in Latin-1 but is not a complete
UTF-8 sequence. These examples use Bash's byte escapes to preserve it.

```scrut
$ git splice status $'caf\xe9'
!!   arguments must be valid UTF-8
[1]
```

### A repository path containing a non-UTF-8 byte

```scrut
$ mv ../monorepo ../$'repo-\xff' &&
>   cd ../$'repo-\xff'
```

```scrut
$ git splice status
!!   '.*/repo-�' isn't supported as the repository's path -- rename the folder: its name isn't valid UTF-8 (regex)
[1]
```

Renaming the folder restores a usable repository path:

```scrut
$ cd .. &&
>   mv $'repo-\xff' monorepo &&
>   cd monorepo
```

### A commit with a Latin-1 author name

Git's object plumbing can write an author name that is not UTF-8. The
rebuild refuses that commit rather than publish a different identity:

```scrut
$ original="$(git rev-parse HEAD)" &&
>   invalid_author="$(git cat-file commit HEAD |
>     sed $'s/^author Test /author Ren\xe9 /' |
>     git hash-object -t commit -w --stdin)" &&
>   git update-ref HEAD "$invalid_author"
```

```scrut
$ git splice rebuild vendor/a
!!   commit [0-9a-f]{40} isn't supported: its author or committer isn't valid UTF-8 (regex)
[1]
```

### A splice path containing a non-UTF-8 byte

Restore the original commit, then copy the splice state into a folder with
a non-UTF-8 name:

```scrut
$ git update-ref HEAD "$original" &&
>   mkdir $'caf\xe9' &&
>   cp vendor/a/.splice $'caf\xe9/.splice' &&
>   git add . &&
>   git commit -q -m "add a folder whose name is not UTF-8"
```

```scrut
$ git splice status
!!   'caf�/.splice' isn't supported as a splice path -- rename the folder: its name isn't valid UTF-8
[1]
```

Rename paths or rewrite legacy author/committer identities to UTF-8 before
using them with `git-splice`. The byte-name examples above target Unix file
systems; the scenario runner uses a POSIX shell.
