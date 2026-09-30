# Scenario: shared-remote-url

Two subtree remotes with different names but the same URL -- the same
upstream repo checked out into two directories.

- **Monorepo**: remotes `vendor/a` and `vendor/b` both point at the same
  bare repo; both directories were added at `seed`, no local changes since.
- **Remote**: one commit (`seed`).

Each remote has its own tracking refs, so the tool treats the two
directories like two clones of one repo, each pushing to and pulling from
the same branch:

- A push from `vendor/a` shows up as `pull` for `vendor/b` after the next
  fetch, and `git subtrees pull` brings it into `vendor/b`.
- If both directories changed, the first push wins. The second is rejected
  as non-fast-forward by the remote, just like a push from a stale clone;
  nothing gets overwritten. Pull it, then push again.

## Output

`scenario_shared_remote_url` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_shared_remote_url
```
-->

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
ok   vendor/b -> $UPSTREAM (up to date)
```

A push from `vendor/a` shows up as `pull` for `vendor/b`:

```scrut
$ echo "change from a" >>vendor/a/file.txt && git commit -qam "change vendor/a"
```

```scrut
$ git subtrees push
git push using:  vendor/a main
To $UPSTREAM
   bde4164..7f225db  7f225db71d6934878a4c2a7109dc44e4467b433a -> main
ok   vendor/a: pushed
ok   vendor/b: nothing to push
```

```scrut
$ git subtrees fetch
ok   vendor/a fetched
ok   vendor/b fetched (main moved bde4164..7f225db)
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
ok   vendor/b -> $UPSTREAM (pull)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git subtrees pull
ok   vendor/a fetched
ok   vendor/a: nothing to pull
ok   vendor/b fetched
Merge made by the 'ort' strategy.
 vendor/b/file.txt | 1 +
 1 file changed, 1 insertion(+)
ok   vendor/b: pulled
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
ok   vendor/b -> $UPSTREAM (up to date)
```
