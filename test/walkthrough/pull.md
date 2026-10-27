# pull

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice pull -h
NAME
    git-splice-pull - Fetch and splice in upstream changes

SYNOPSIS
    git splice pull [--upstream <name>] [--branch <name>] [--bump | --rebase] [--no-fork-point] (<path>... | --all)
    git splice pull [<option>...] -m <message> <path>

DESCRIPTION
    'git splice fetch' followed by 'git splice merge': fetches the splices'
    upstreams in parallel, then splices their changes in, as one ordinary
    commit per splice. Also fetches the splices below each: pulling a splice
    can move their synced commits. Top-down: a splice is pulled before the
    ones below it, and a failed fetch stops the splices above and below it.

    On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
    --abort' to give up), then re-run pull for any splices left. With
    --rebase, it's 'git rebase --continue' (or 'git rebase --abort').

    --upstream names one of the upstreams a splice's .splice names; without
    it, the splice's default upstream. A splice without the named upstream
    stops the command before it starts. The splices below, selected or not,
    are fetched from every upstream they name: names are only unique within one .splice, and
    any of them may have the synced commit the pull moves to.

    --branch names the upstream branch to pull, for this pull only; --rebase
    rebases instead of merging, like 'git pull --rebase'; see 'git splice
    merge --help' for both.

    --bump also moves the synced commit up to the upstream branch when there's
    nothing to pull, e.g. right after a push; see 'git splice merge --help'.

    --no-fork-point merges a rewritten upstream branch from Git's merge base,
    not from where the branch was before the rewrite; see 'git splice merge
    --help'.

    -m gives the commit this message, for one splice; see 'git splice merge
    --help'.
```
```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b >/dev/null &&
>   git clone -q "$WALKTHROUGH/upstream/pkg-b.git" ../pkg-b &&
>   echo "pkg-b: add a feature" >>../pkg-b/file.txt &&
>   git -C ../pkg-b commit -qam "pkg-b: add a feature" &&
>   git -C ../pkg-b push -q
```

Both splices of the [walkthrough's repositories](README.md) are behind now. Commands that
change the monorepo or an upstream name their splices, or take `--all`:

```scrut
$ git splice pull --all
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched (main moved 9b3cb02..b937c4f)
ok   vendor/pkg-a: pulled 703b936
ok   vendor/pkg-b: pulled b937c4f
```

Each splice gets one commit. The monorepo's history stays linear:

```scrut
$ git log --oneline
6ed2f79 splice: pull vendor/pkg-b from main at b937c4f
dcf70b0 splice: pull vendor/pkg-a from main at 703b936
a73990e splice: clone vendor/pkg-b from main at 9b3cb02
d2867e9 lib-c: first version
3aef6fd splice: clone vendor/pkg-a from main at 9bb866a
ebe3b2b initial commit
```

`-m` gives the commit your message instead, e.g. to say why you pull. It
takes one splice: each gets a commit of its own. `.splice` records the
upstream commit, so nothing needs to stay in the message:

```scrut
$ echo "pkg-b: fix the feature" >>../pkg-b/file.txt &&
>   git -C ../pkg-b commit -qam "pkg-b: fix the feature" &&
>   git -C ../pkg-b push -q
```

```scrut
$ git splice pull -m "take pkg-b's fix for the release" vendor/pkg-b
ok   vendor/pkg-b fetched (main moved b937c4f..e81697a)
ok   vendor/pkg-b: pulled e81697a
```

```scrut
$ git log -1 --format=%s
take pkg-b's fix for the release
```

## More

- When both sides changed the same lines, the pull stops at a conflict;
  resolve it and `git commit` ([diverged history](diverged.md)).
- Two developers who pull the same splice at different times get
  conflicts in `.splice` when one merges the other's work. Pull the
  monorepo before you pull a splice
  ([concurrent-pulls](../scenarios/03-branches-and-teamwork/04-concurrent-pulls/README.md)).
- A squash merge of the pull's branch keeps the sync point
  ([squash-merged-pull](../scenarios/03-branches-and-teamwork/03-squash-merged-pull/README.md)).
- When `git bisect` ends at a pull, the upstream commits squashed into
  it can be tested inside the monorepo, to find the one that broke it
  ([bisect-into-a-pull](../scenarios/03-branches-and-teamwork/05-bisect-into-a-pull/README.md)).
