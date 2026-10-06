# Scenario: upstream-rewritten-equal-tree

The upstream rewrote its history and force-pushed a new commit with
exactly the same files. The splice looks up to date, but its synced commit
is no longer part of the upstream's history. The next change on either
side then makes the splice `unrelated history`, and `pull` and `push`
refuse to continue, though the splice matched the upstream exactly. This
is a known bug, [#17](https://github.com/roschaefer/git-splice/issues/17).

- **Monorepo (`vendor/a`)**: cloned at `release`.
- **Upstream**: `seed`, `release`, then rewritten and force-pushed as one
  root commit, `release, history rewritten`, with `release`'s files.
  Already fetched.

`status` compares the files first. They're equal, so it reports `up to
date` without looking at the history, and `merge` doesn't record the new
commit in `.splice`.

Workaround: [keep the upstream's version](keep-the-upstream-version.md)
and redo the local changes on top of it. If the rewrite removed something,
like a secret, don't use the other ways out that `merge` prints for
`unrelated history` ([#38](https://github.com/roschaefer/git-splice/issues/38)). `git splice push --force` rebuilds on top of the old
synced commit, and so [publishes the rewritten-away history
again](push-force-undoes-the-rewrite.md). Keeping
both publishes the monorepo's own history of the folder, which contains
whatever the monorepo pulled before the rewrite.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_upstream_rewritten_equal_tree
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
release, history rewritten
```

The splice is up to date, so there is nothing to merge:

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```

```scrut
$ git splice merge vendor/a
ok   vendor/a: nothing to merge
```

But `.splice` still names the old `release`, which the upstream's history
no longer contains:

```scrut
$ git log -1 --format=%s "$(git config --file vendor/a/.splice splice.commit)"
release
```

The upstream's `main`, as fetched, is the ref ending in `-/main`:

```scrut
$ main="$(git for-each-ref --format='%(refname:lstrip=3) %(objectname)' refs/splices/ | sed -n 's#^main ##p')"
```

```scrut
$ git merge-base --is-ancestor "$(git config --file vendor/a/.splice splice.commit)" "$main" || echo "not in the upstream's history"
not in the upstream's history
```

A local change, and the splice has no history in common with the upstream
anymore:

```scrut
$ echo "local change" >>vendor/a/file.txt && git commit -q -a -m "local change"
```

```scrut
$ git splice status
??   vendor/a -> main (unrelated history -- see 'git splice merge vendor/a' for options)
```

```scrut
$ git splice push vendor/a
??   vendor/a: upstream and the splice share no history -- pick a side:

  # keep the upstream version, discarding local changes under vendor/a:
  git rm -r -q -- vendor/a && git commit -m 'remove vendor/a'
  git splice clone -- $UPSTREAM vendor/a

  # OR: keep both, resolving every file that differs as a conflict:
  git rm -q -- vendor/a/.splice && git commit -m 'unsplice vendor/a'
  git splice clone --merge -- $UPSTREAM vendor/a

  # OR: keep the monorepo version, overwriting upstream's branch:
  git splice push --force -- vendor/a

!!   Failed: vendor/a
[1]
```
