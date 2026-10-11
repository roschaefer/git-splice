# Scenario: pushed-then-pulled: bump on a branch

The same state as in [pushed-then-pulled](README.md). A feature branch
pushes a change to the upstream's `feature` branch and bumps the sync
point to it, by hand, as a proposed `git splice pull --bump`
([#115](https://github.com/roschaefer/git-splice/issues/115)) would.
Then `main` merges the feature branch, and with it the bump: `main`'s
`.splice` now names a commit of the upstream's `feature` branch
([why the push isn't recorded](README.md#why-the-push-isnt-recorded)).

That holds only as long as the upstream keeps the commit. Here, the
upstream squash-merges `feature` and deletes the branch, as many hosts do
after a pull request.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_pushed_then_pulled
```

## The bump, on a feature branch

```scrut
$ git switch -q -c feature && echo "feature change" >>vendor/a/file.txt && git commit -q -a -m "feature change"
```

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'feature' branch yet -- this push creates it (changed since 'main')
ok   vendor/a: pushed 38fbc52 to feature
```

```scrut
$ U="$(git -C "$UPSTREAM" rev-parse feature)" && git config --file vendor/a/.splice splice.commit "$U" && git commit -q -m "splice: bump vendor/a from feature at ${U:0:7}" -- vendor/a/.splice
```

`main` merges the feature branch, and its `.splice` now names the
feature branch's commit:

```scrut
$ git switch -q main && git merge -q --no-ff -m "Merge branch 'feature'" feature
```

```scrut
$ git log -1 --format='%h %s' "$(git config --file vendor/a/.splice splice.commit)"
38fbc52 feature change
```

## The upstream squash-merges the feature branch

The upstream's maintainer squash-merges `feature` into `main`, deletes
the branch, and adds a change of their own:

```scrut
$ git clone -q "$UPSTREAM" ../maintainer && cd ../maintainer && git config user.name Maintainer && git config user.email maintainer@example.com
```

```scrut
$ git merge -q --squash origin/feature && git commit -q -m "feature change (squashed)" && git push -q origin main :feature
Squash commit -- not updating HEAD
```

```scrut
$ echo "upstream change" >upstream.txt && git add upstream.txt && git commit -q -m "add upstream.txt" && git push -q origin main
```

Nothing refers to the feature branch's commit any more, and the
upstream's `gc` removes it:

```scrut
$ git -C "$UPSTREAM" gc -q --prune=now && git -C "$UPSTREAM" cat-file -t "$U"
fatal: git cat-file: could not get object info
[128]
```

## A clone of the monorepo

A colleague clones the monorepo. `.splice` on `main` names a commit
they can't fetch:

```scrut
$ cd .. && git clone -q "file://$PWD/monorepo" colleague && cd colleague && git config user.name Colleague && git config user.email colleague@example.com
```

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched
```

```scrut
$ git splice status
??   vendor/a -> main (unrelated history -- see 'git splice merge vendor/a' for options)
```

Without the bump, `main`'s `.splice` would still name `seed`, which the
upstream keeps, and the pull would bring in `add upstream.txt`.
