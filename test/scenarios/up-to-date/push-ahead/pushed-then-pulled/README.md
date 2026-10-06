# Scenario: pushed-then-pulled

The monorepo pushed a change. Pulling right after the push brings nothing
in, and `.splice` keeps the commit it had before the push. Only a pull that
brings in an upstream change moves it.

- **Monorepo (`vendor/a`)**: cloned at `seed`, then a local commit, pushed
  with `git splice push`.
- **Upstream**: `seed`, then the pushed commit.
- **Synced commit**: still `seed`.

## Why the push isn't recorded

`.splice` is committed in the monorepo, so recording the push would take a
monorepo commit, on the branch that pushed. Merging that branch would then
carry the record to a branch that syncs with a different upstream branch:
a feature branch's `.splice` would name a commit of the upstream's feature
branch, and after the merge, `main`'s would too.

It isn't needed either. `status` compares the folder's content with the
upstream branch, and after the push they're the same, so the splice is
`up to date` though `.splice` still names `seed`. And `pull` doesn't merge
from the synced commit, but from where the monorepo's history and the
upstream's meet. It finds that by rebuilding the monorepo's commits from
the synced commit on, as `push` does. The rebuild is deterministic: it
produces the pushed commit again, with the same hash, so the histories meet
at the pushed commit, not at `seed`.
[The design](../../../../../docs/design/README.md#the-sync-point) explains the
sync point.

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

The upstream has the pushed commit:

```scrut
$ git -C "$UPSTREAM" log --format='%h %s' main
e859a6b local change
bde4164 seed
```

`.splice` still names `seed`, the commit from before the push:

```scrut
$ git log -1 --format='%h %s' "$(git config --file vendor/a/.splice splice.commit)"
bde4164 seed
```

Yet the splice is up to date, because the folder's content equals the
upstream's:

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```

So a pull right after the push has nothing to bring in, and doesn't change
`.splice`:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: nothing to pull
```

```scrut
$ git log -1 --format='%h %s' "$(git config --file vendor/a/.splice splice.commit)"
bde4164 seed
```

Once someone else pushes to the upstream, the next pull brings their commit
in. It merges from the pushed commit, so the local change isn't applied a
second time:

```scrut
$ seed_bare_repo "$UPSTREAM" "upstream change"
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved e859a6b..de87439)
ok   vendor/a: pulled de87439
```

Now `.splice` names the upstream's new tip, in the pull's commit:

```scrut
$ git log -1 --format='%h %s' "$(git config --file vendor/a/.splice splice.commit)"
de87439 upstream change
```

```scrut
$ git log --format=%s
splice: pull vendor/a from main at de87439
local change
add vendor/a
initial commit
```
