# Committed conflict markers

In the [same state](README.md), the conflict in `vendor/a/.splice` is
committed with its markers. git-splice doesn't notice: it reads `.splice`
with `git config`, which stops at the first marker, and hides the error.
The URL comes before the markers, so it's still read; the synced commit
comes after them, so it's read as missing. This is a known bug,
[#37](https://github.com/roschaefer/git-splice/issues/37).

## Output

`scenario_concurrent_pulls` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_concurrent_pulls
```
-->

The folder's files are resolved, `.splice` isn't:

```scrut
$ git merge origin/main >/dev/null; git checkout --ours -- vendor/a/file.txt && git add vendor/a && git commit -q --no-edit
```

`git config` can't read it:

```scrut
$ git config --blob HEAD:vendor/a/.splice --get splice.commit
error: bad config line 3 in blob HEAD:vendor/a/.splice
[1]
```

But `status` reports nothing wrong, since the folder still matches the
upstream:

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```

The next change shows the damage. Without a synced commit, the splice's
whole history looks unrelated to the upstream's, and the advice includes
`push --force`, which would replace the upstream's branch:

```scrut
$ echo "local change" >>vendor/a/file.txt && git commit -q -a -m "local change"
```

```scrut
$ git splice status
??   vendor/a -> main (unrelated history -- see 'git splice merge vendor/a' for options)
```

```scrut
$ git splice merge vendor/a
??   vendor/a: upstream and the splice share no history -- pick a side:

  # keep the upstream version, discarding local changes under vendor/a:
  git rm -r -q -- vendor/a && git commit -m 'remove vendor/a'
  git splice clone -- https://git.example.com/a.git vendor/a

  # OR: keep both, resolving every file that differs as a conflict:
  git rm -q -- vendor/a/.splice && git commit -m 'unsplice vendor/a'
  git splice clone --merge -- https://git.example.com/a.git vendor/a

  # OR: keep the monorepo version, overwriting upstream's branch:
  git splice push --force -- vendor/a

!!   Failed: vendor/a
[1]
```

The fix is a readable `.splice` with the newer sync point. Here, the merge's
first parent has it:

```scrut
$ git checkout HEAD~1^1 -- vendor/a/.splice && git commit -q -m "fix vendor/a/.splice" && git splice status
ok   vendor/a -> main (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```
