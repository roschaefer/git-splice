# Scenario: pushed-then-pulled: a new id after the push

The same state as in [pushed-then-pulled](README.md): the monorepo pushed
a change, and `.splice` still names `seed`. Then someone gives the splice
a new id by editing `.splice`. From then on, the splice can't push.

A new [id](../../../../../concepts/splice-identity/README.md#what-an-id-is)
makes it a new splice. Its history starts at the commit with the new id,
on top of the synced commit in `.splice`. A push doesn't move that synced
commit ([why](../../../../../concepts/sync-model/README.md#r-is-computed-not-stored)),
so it still names `seed`. The new history therefore has the pushed change
again, in another commit, and the upstream's commit isn't part of it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_pushed_then_pulled
```

The upstream has the pushed commit, and `.splice` still names `seed`:

```scrut
$ git -C "$UPSTREAM" log --format='%h %s' main
e859a6b local change
bde4164 seed
```

```scrut
$ git log -1 --format='%h %s' "$(git config --file vendor/a/.splice splice.commit)"
bde4164 seed
```

## A new id

`.splice` gets a new id, and the folder a new change:

```scrut
$ git config --file vendor/a/.splice splice.id 1111111111111111 &&
>   git commit -q -am "vendor/a: new id"
```

```scrut
$ echo "next change" >>vendor/a/file.txt &&
>   git commit -q -am "next change"
```

The splice's history now starts at the new id, on top of `seed`. The
commit with the new id has the files of the pushed change, so `log` marks
it and the upstream's `local change` with `=`, the same change on both
sides:

```scrut
$ git splice log vendor/a
===  vendor/a (main)
< 1ecefa1 next change  (Test <test@example.com>)
= e859a6b local change  (Test <test@example.com>)
= 6ea51da vendor/a: new id  (Test <test@example.com>)
```

But the upstream's commit isn't part of the history, so the two sides
have diverged:

```scrut
$ git splice status
On branch main

  ahead 2, behind 1  vendor/a
```

The push is refused:

```scrut
$ git splice push vendor/a
!!   vendor/a: upstream has commits this branch lacks
!!   Failed: vendor/a
[1]
```

A pull merges the upstream's commit into a folder that has its change
already, and moved on since. It conflicts:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
Auto-merging vendor/a/file.txt
CONFLICT (content): Merge conflict in vendor/a/file.txt
!!   vendor/a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a: pull failed
!!   Failed: vendor/a
[1]
```

```scrut
$ git status --short
M  vendor/a/.splice
UU vendor/a/file.txt
```

## Bump before the new id

A [bump](bump-after-push.md) moves the synced commit up to the pushed
one. Done before the new id, the new history starts on top of what the
upstream has, and the next push goes through:

```scrut
$ git cherry-pick --abort && git reset -q --hard HEAD~2
```

```scrut
$ git splice pull --bump vendor/a
ok   vendor/a fetched
ok   vendor/a: bumped the synced commit to e859a6b
```

```scrut
$ git config --file vendor/a/.splice splice.id 1111111111111111 &&
>   git commit -q -am "vendor/a: new id"
```

```scrut
$ echo "next change" >>vendor/a/file.txt &&
>   git commit -q -am "next change"
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 67ca358 to main
```

```scrut
$ git -C "$UPSTREAM" log --format='%h %s' main
67ca358 next change
e859a6b local change
bde4164 seed
```
