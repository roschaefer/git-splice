# splice-refs: key renamed while fetching

`git splice key` renames an upstream's key: it moves the refs under
`refs/splices/<key>/` and the key's entry in the repository's config. A
`fetch`, `pull` or `push` looks the key up when it starts and writes its
refs under it seconds later, after the network. If a rename in another
worktree of the same repository falls between the two, the command writes
under the old key and reports success. A `push` records what it pushed
there too. `git remote rename` has the
[same gap](#plain-git-does-the-same), and Git accepts it for a rare,
manual rename; so does `git-splice`. The next fetch
[repairs it](#the-next-fetch-repairs-it).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_splice_refs
```

The monorepo splices in the upstream, whose key is `a`, and has a second
worktree:

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ git worktree add -q ../other
```

Someone pushes to the upstream's `main`, with
[`seed_bare_repo`](../../../tests/helpers/fixtures.bash):

```scrut
$ seed_bare_repo "$UPSTREAM" "upstream change"
```

### A rename during the fetch

A real fetch spends seconds on the network. To put the rename into that
time on every run, the upstream is served through Git's `ext::`
transport by a script that first renames the key in the other worktree,
then serves the upstream:

```scrut
$ mkdir ../bin && cat >../bin/rename-then-serve <<EOF
> #!/bin/sh
> git -C "$PWD/../other" splice key vendor/a lib >&2
> unset GIT_DIR GIT_WORK_TREE
> exec git "\${1#git-}" "\$2"
> EOF
```

```scrut
$ chmod +x ../bin/rename-then-serve &&
>   PATH="$PWD/../bin:$PATH" &&
>   git config protocol.ext.allow always &&
>   git config --unset "url.$UPSTREAM.insteadOf" &&
>   git config "url.ext::rename-then-serve %S $UPSTREAM.insteadOf" https://git.example.com/a.git
```

Both report success:

```scrut
$ git splice fetch
ok   vendor/a fetched (main moved bde4164..6045a98)
ok   vendor/a: renamed key 'a' to 'lib'
```

It wrote it under the old key, `a`. The renamed key, `lib`, has the refs
from before the fetch:

```scrut
$ git for-each-ref --format='%(objectname:short) %(subject) %(refname)' refs/splices
530decc parser fix refs/splices/a/heads/fix-parser
6045a98 upstream change refs/splices/a/heads/main
530decc parser fix refs/splices/lib/heads/fix-parser
bde4164 seed refs/splices/lib/heads/main
```

The config has only `lib`, so every command reads those. The splice
looks up to date, though the upstream moved, and a `pull` would merge
nothing:

```scrut
$ git config --get-regexp '^splice\.'
splice.lib.url https://git.example.com/a.git
```

```scrut
$ git splice status
On branch main

  up to date  vendor/a
```

### The next fetch repairs it

Fetching again, without the script, fills the renamed key:

```scrut
$ git config --unset "url.ext::rename-then-serve %S $UPSTREAM.insteadOf" &&
>   git config "url.$UPSTREAM.insteadOf" https://git.example.com/a.git
```

```scrut
$ git splice fetch
ok   vendor/a fetched (main moved bde4164..6045a98)
```

```scrut
$ git splice status
On branch main

  behind 1  vendor/a
```

The refs under the old key stay, as no key names them: `git gc` keeps
refs, and `fetch` only prunes under the current key. They cost little,
but keep their commits and the name `a` taken. A folder under
`refs/splices/` with no `splice.<key>.url` in the config is such a
leftover, and can be deleted:

```scrut
$ git for-each-ref --format='delete %(refname)' refs/splices/a/ |
>     git update-ref --stdin
```

```scrut
$ git for-each-ref --format='%(refname)' refs/splices
refs/splices/lib/heads/fix-parser
refs/splices/lib/heads/main
```

### Plain Git does the same

`git remote rename` moves a remote's remote-tracking branches and its
config entry, and a `git fetch` in another worktree that started before
writes under the old name. A clone of the upstream, its fetch served by a
script that renames `origin` to `lib` in a second worktree:

```scrut
$ git clone -q "$UPSTREAM" ../plain &&
>   cd ../plain &&
>   git worktree add -q ../plain-other &&
>   seed_bare_repo "$UPSTREAM" "another change"
```

```scrut
$ cat >../bin/remote-rename-then-serve <<EOF
> #!/bin/sh
> git -C "$PWD/../plain-other" remote rename origin lib >&2
> unset GIT_DIR GIT_WORK_TREE
> exec git "\${1#git-}" "\$2"
> EOF
```

```scrut
$ chmod +x ../bin/remote-rename-then-serve &&
>   git config protocol.ext.allow always &&
>   git config "url.ext::remote-rename-then-serve %S $UPSTREAM.insteadOf" "$UPSTREAM"
```

`git fetch` succeeds, and writes the new commit under `origin`, a remote
that no longer exists:

```scrut
$ git fetch -q origin && echo fetched
fetched
```

```scrut
$ git for-each-ref --format='%(subject) %(refname)' refs/remotes
upstream change refs/remotes/lib/HEAD
parser fix refs/remotes/lib/fix-parser
upstream change refs/remotes/lib/main
another change refs/remotes/origin/HEAD
parser fix refs/remotes/origin/fix-parser
another change refs/remotes/origin/main
```
