# pull

`git splice pull [--upstream <name>] [--bump] (<path>… | --all)`

[`fetch`](fetch.md) and [`merge`](merge.md) in one. It also fetches the
splices nested in each, whose synced commits a pull can move
([nesting](../concepts/nesting/README.md)).

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b >/dev/null && git clone -q "$WALKTHROUGH/upstream/pkg-b.git" ../pkg-b && echo "pkg-b: add a feature" >>../pkg-b/file.txt && git -C ../pkg-b commit -qam "pkg-b: add a feature" && git -C ../pkg-b push -q
```

Both splices in the [sandbox](../../docs/sandbox.md) are behind now. Commands that
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
