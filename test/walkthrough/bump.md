# Bumping the sync point

A push never writes to the monorepo, so after one, `.splice` still names
the upstream commit from before it. `git splice pull --bump` records the
upstream branch anyway, in a commit that only changes `.splice`, like a
submodule bump. Later rebuilds then start at the pushed commit, instead
of rebuilding every commit pushed since the last pull.

Bump on `main`. On a feature branch that also changes code outside the
splice, a bump makes `.splice` conflict when the branch is merged, if the
library squash-merges its pull requests. This walkthrough shows both, and
how to get out of the conflict.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

## On main, after a push

Bring `pkg-a` up to date, as in the [main walkthrough](README.md#pull),
then change it and push:

```scrut
$ git splice pull vendor/pkg-a >/dev/null
```

```scrut
$ echo "a faster parser" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a faster parser"
```

```scrut
$ git splice push vendor/pkg-a
ok   vendor/pkg-a: pushed 9816d9f to main
```

A pull right after the push has nothing to bring in, and leaves `.splice`
as it was:

```scrut
$ git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: nothing to pull
```

```scrut
$ git log -1 --format=%s "$(git config --file vendor/pkg-a/.splice splice.commit)"
pkg-a: a second commit, after the clone
```

With `--bump`, it records the pushed commit:

```scrut
$ git splice pull --bump vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: bumped the synced commit to 9816d9f
```

```scrut
$ git log -1 --format=%s "$(git config --file vendor/pkg-a/.splice splice.commit)"
pkg-a: a faster parser
```

```scrut
$ git log -1 --format=%s
splice: bump vendor/pkg-a from main at 9816d9f
```

## On a feature branch: a conflict

A feature that changes the library and the monorepo's code that uses it:

```scrut
$ git switch -q -c feature
```

```scrut
$ echo "an option" >>vendor/pkg-a/file.txt && mkdir -p app && echo "uses the option" >app/main.txt && git add app && git commit -qam "pkg-a: an option, and the app uses it"
```

The push creates `pkg-a`'s `feature` branch, the library's pull request.
A bump then records it on the monorepo's `feature`:

```scrut
$ git splice push vendor/pkg-a
??   vendor/pkg-a: upstream has no 'feature' branch yet -- this push creates it (changed since 'main')
ok   vendor/pkg-a: pushed 556e8b7 to feature
```

```scrut
$ git splice pull --bump vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: bumped the synced commit to 556e8b7
```

The library squash-merges the pull request: its `main` gets the same
change as a new commit. Here in a clone of `pkg-a`, as its maintainer
would:

```scrut
$ git clone -q "$WALKTHROUGH/upstream/pkg-a.git" "$WALKTHROUGH/pkg-a" && cd "$WALKTHROUGH/pkg-a" && git config user.name "Maintainer" && git config user.email "maintainer@example.com"
```

```scrut
$ git merge -q --squash origin/feature && git commit -q -m "an option (#1)" && git push -q origin main
Squash commit -- not updating HEAD
```

Back in the monorepo, `main` pulls it:

```scrut
$ cd "$WALKTHROUGH/monorepo" && git switch -q main
```

```scrut
$ git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched (main moved 9816d9f..0d27eb0)
ok   vendor/pkg-a: pulled 0d27eb0
```

`main` has the library's change now, but not the app's. So the monorepo's
`feature` still needs merging, and that conflicts: `main` changed
`.splice` to the squashed commit, and the bump on `feature` changed the
same line to the pull request's commit. A squash merge computes its
files like any merge, so it conflicts too:

```scrut
$ git merge --squash feature
Auto-merging vendor/pkg-a/.splice
CONFLICT (content): Merge conflict in vendor/pkg-a/.splice
Squash commit -- not updating HEAD
Automatic merge failed; fix conflicts and then commit the result.
[1]
```

```scrut
$ git reset -q --hard
```

Without the bump, `feature` wouldn't have changed `.splice`, and the merge
would take `main`'s.

## The way out: rebase the library's branch

Rebase the library's `feature` onto its `main`. The squashed commit
already has the change, so the rebase drops it, and `feature` becomes the
library's `main`:

```scrut
$ cd "$WALKTHROUGH/pkg-a" && git switch -q feature && git rebase -q main && git push -q -f origin feature
hint: use --reapply-cherry-picks to include skipped commits
hint: Disable this message with "git config set advice.skippedCherryPicks false"
```

```scrut
$ git log -1 --format=%s feature
an option (#1)
```

The monorepo's `feature` pulls it. The folder already has its files, so
`pull` records it, without the need for `--bump`:

```scrut
$ cd "$WALKTHROUGH/monorepo" && git switch -q feature
```

```scrut
$ git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched (feature moved 556e8b7..0d27eb0)
ok   vendor/pkg-a: recorded 0d27eb0 as the synced commit -- the folder already has its files
```

Now both branches name the same commit in `.splice`, and the merge only
brings in the app:

```scrut
$ git switch -q main && git merge --squash feature
Automatic merge went well; stopped before committing as requested
Squash commit -- not updating HEAD
```

```scrut
$ git status --short
A  app/main.txt
```

```scrut
$ git commit -q -m "app: use pkg-a's option" && git splice status
ok   vendor/pkg-a -> main (up to date)
```

If the library deleted its `feature` branch after the merge, there's
nothing to pull. Merge `main` into the monorepo's `feature` instead, and
resolve `.splice` to `main`'s version.

## A company fork

The rebase needs a library branch you can force-push. For a library you
don't maintain, that's a branch in your company's fork of it: push the
feature there, open the pull request from the fork, and rebase the fork's
branch once the original squash-merged it. A splice that follows both the
fork and the original needs several upstreams in one `.splice`
([#108](https://github.com/roschaefer/git-splice/pull/108)).
