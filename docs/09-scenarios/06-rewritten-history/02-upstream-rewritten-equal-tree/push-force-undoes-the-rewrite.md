# `push --force` undoes the rewrite

> **Limitation.** This page shows behaviour `git-splice` keeps on purpose, and the way out. See [known bugs and limitations](../../99-known-bugs.md#limitations).

In the [same state](README.md), after a local change made before a
`merge` or `pull` recorded the rewritten commit, `git splice push
--force` makes the monorepo's side win. Its rebuild starts from the old
synced commit, so the upstream gets back the history the rewrite removed.
Don't use it when the rewrite removed something, like a secret;
[keep the upstream's version](keep-the-upstream-version.md) instead.
Plain Git [does the same](#plain-git-does-the-same): a forced push from a
clone made before the rewrite publishes the old history again, and
nothing Git prints warns about it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_upstream_rewritten_equal_tree
```

<!--
```scrut
$ w="$(git -C "$UPSTREAM" rev-parse main)"
```
-->

```scrut
$ echo "local change" >>vendor/a/file.txt &&
>   git commit -q -a -m "local change" &&
>   git splice push --force vendor/a
ok   vendor/a: pushed 2543d4c to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
local change
r: release
k: seed
```

### Plain Git does the same

A clone of the upstream, with the old history, and a change of its own:

```scrut
$ git clone -q -c user.name=Test -c user.email=test@example.com "$UPSTREAM" ../plain &&
>   cd ../plain &&
>   echo "plain change" >>file.txt &&
>   git commit -q -a -m "plain change"
```

The upstream's owners rewrite its history again, back to *w*:

```scrut
$ git -C "$UPSTREAM" update-ref refs/heads/main "$w" &&
>   git -C "$UPSTREAM" log --format=%s main
w: release, history rewritten
```

`git fetch` notes the forced update, and `git status` and `git pull`
treat it as two branches that diverged:

```scrut
$ git fetch 2>&1 | sed "s#$UPSTREAM#\$UPSTREAM#"
From $UPSTREAM
 + 2543d4c...5cc12da main       -> origin/main  (forced update)
```

```scrut
$ git status
On branch main
Your branch and 'origin/main' have diverged,
and have 4 and 1 different commits each, respectively.
  (use "git pull" if you want to integrate the remote branch with yours)

nothing to commit, working tree clean
```

```scrut
$ git pull
hint: You have divergent branches and need to specify how to reconcile them.
hint: You can do so by running one of the following commands sometime before
hint: your next pull:
hint:
hint:   git config pull.rebase false  # merge
hint:   git config pull.rebase true   # rebase
hint:   git config pull.ff only       # fast-forward only
hint:
hint: You can replace "git config" with "git config --global" to set a default
hint: preference for all repositories. You can also pass --rebase, --no-rebase,
hint: or --ff-only on the command line to override the configured default per
hint: invocation.
fatal: Need to specify how to reconcile divergent branches.
[128]
```

`git push --force-with-lease` passes the lease, since the fetch saw the
rewritten commit, and publishes the old history again:

```scrut
$ git push -q --force-with-lease
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
plain change
local change
r: release
k: seed
```
