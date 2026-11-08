# Feature branches

By default, every splice follows the upstream branch named like the
monorepo's current branch.

If that branch does not exist upstream, `git-splice` compares the splice
with upstream's default branch instead. This works like a pull request or
merge request: the feature branch is compared with the default branch.

<div align="center">

![The monorepo and the splice upstream each have only a main branch](../09-scenarios/03-branches-and-teamwork/02-feature-branch-from-main/feature-branch-before-switch.drawio.svg)

</div>

The drawings in these docs share one language, the
[central legend](../10-contributing/02-writing.md#reading-the-drawings):
boxes name commits, lanes are splices, and dashed commits aren't on the
upstream yet.

This works across all the repositories involved. In the
[walkthrough sandbox](../01-getting-started/02-walkthrough.md), both splices start on `main`. Switch the
monorepo to `feature`; neither upstream has that branch:

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```

```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b >/dev/null &&
>   git splice pull --all >/dev/null
```
-->

```scrut
$ git switch -c feature
Switched to a new branch 'feature'
```

<div align="center">

![The monorepo's new feature branch starts at main, while the splice upstream still has only main](../09-scenarios/03-branches-and-teamwork/02-feature-branch-from-main/feature-branch-before-change.drawio.svg)

</div>

Both splices still match upstream `main`, so neither needs an upstream
branch of its own:

```scrut
$ git splice status
On branch feature

  unchanged, no upstream branch  vendor/pkg-a
  unchanged, no upstream branch  vendor/pkg-b
```

Change `pkg-b` on the feature branch:

```scrut
$ echo "a new option" >>vendor/pkg-b/file.txt &&
>   git commit -qam "pkg-b: add an option" &&
>   git splice status
On branch feature

  new, ahead 1                   vendor/pkg-b  push creates the branch

  unchanged, no upstream branch  vendor/pkg-a
```

The changed splice is ready to publish:

<div align="center">

![The monorepo's main branch at a and feature branch at b, and the upstream's main at k with b prime ready for a feature branch](../09-scenarios/03-branches-and-teamwork/02-feature-branch-from-main/feature-branch-from-main.drawio.svg)

</div>

Pushing all splices creates `feature` only in `pkg-b`'s upstream:

```scrut
$ git splice push --all
ok   vendor/pkg-a: nothing to push (upstream has no 'feature' branch, and a PR to 'main' would show no changes)
??   vendor/pkg-b: upstream has no 'feature' branch yet -- this push creates it
ok   vendor/pkg-b: pushed 5023101 to feature
```

<div align="center">

![The monorepo's main branch at a and feature branch at b, and the upstream's main at k and new feature branch at b prime](../09-scenarios/03-branches-and-teamwork/02-feature-branch-from-main/feature-branch-after-push.drawio.svg)

</div>

See [branch scenarios](../09-scenarios/03-branches-and-teamwork/02-feature-branch-from-main/README.md)
for squash merges, shared branches and tracked branches.
