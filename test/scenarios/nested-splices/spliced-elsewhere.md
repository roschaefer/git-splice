# Scenario: nested-splices, spliced into another monorepo

**A known limitation**
([#74](https://github.com/roschaefer/git-splice/issues/74)). The
monorepo pushes a change in b, the splice below a. Then another monorepo
splices a in. There, b's files already have the change, but b's
`.splice` still names the synced commit from before it, and
`git splice clone` brought in none of the history between the two. So
b's first local change there reads as diverged from b's upstream, and
`pull` conflicts on a line both sides have.

A plain `git clone` of a's upstream doesn't run into this: it has the
history in between, as the monorepo does.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Other GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=other@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
a with b spliced in at `b/`, cloned into the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

The monorepo changes b and pushes both, bottom-up:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local" && git splice push vendor/a/b vendor/a
ok   vendor/a/b: pushed f47c373 to main
ok   vendor/a: pushed 1a17dce to main
```

b's `.splice` still names b's synced commit from before the change. That's
fine here: the monorepo has the commit `b local` in between, and rebuilds
it into exactly the commit it pushed. a's push publishes this `.splice`:

```scrut
$ git -C "$UPSTREAM" show main:b/.splice | git config --file - splice.commit | xargs git -C "$UPSTREAM-b.git" log -1 --format=%s
b seed
```

## Another monorepo splices a in

```scrut
$ git init -q -b main ../other && cd ../other && git commit -q --allow-empty -m "other monorepo"
```

```scrut
$ git splice clone "$UPSTREAM" vendor/a && git splice fetch
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned 1a17dce from main
ok   vendor/a fetched
ok   vendor/a/b fetched
```

`clone` squashed a's history into one commit, so that commit is b's
boundary. b's files there already have `b local`, but its `.splice` names
`b seed`:

```scrut
$ git log --format=%s
splice: clone vendor/a from main at 1a17dce
other monorepo
```

```scrut
$ cat vendor/a/b/file.txt; git log -1 --format=%s "$(git config --file vendor/a/b/.splice splice.commit)"
b seed
b local
b seed
```

Up to date, since b's files match b's upstream:

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
ok   vendor/a/b -> main (up to date)
```

The first change to b here:

```scrut
$ echo "b other" >>vendor/a/b/file.txt && git commit -q -a -m "b other"
```

With no history between `b seed` and the clone, the rebuild can't tell
that the clone's files are the commit already pushed. It makes a new
commit for them, so b reads as diverged:

```scrut
$ git splice status vendor/a/b
ok   vendor/a/b -> main (diverged: ahead 2, behind 1)
```

`log` shows the two as the same change, `=`: the commit `b local` that
the monorepo pushed, and the one the rebuild made from the clone:

```scrut
$ git splice log vendor/a/b
===  vendor/a/b (main)
< 5bdc591 b other  (Other <other@example.com>)
= f47c373 b local  (Other <other@example.com>)
= 7355b90 splice: clone vendor/a from main at 1a17dce  (Other <other@example.com>)
```

And `pull` conflicts. Merged on top of `b seed`, the upstream's side adds
`b local`, and this side adds `b local` and `b other`:

```scrut
$ git splice pull vendor/a/b
ok   vendor/a/b fetched
Auto-merging vendor/a/b/file.txt
CONFLICT (content): Merge conflict in vendor/a/b/file.txt
!!   vendor/a/b: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a/b: pull failed
!!   Failed: vendor/a/b
[1]
```
