# Scenario: init-then-cloned

A splice made by `init` was published, and a colleague clones the
monorepo. Until the clone fetches, `status`, `merge`, `log` and `diff`
treat the upstream as empty, though it has commits. This is a known bug,
[#11](https://github.com/roschaefer/git-splice/issues/11).

- **Monorepo (`lib/a`)**: a fresh clone of a monorepo in which `lib/a` was
  made a splice with `init` and pushed twice.
- **Upstream**: the two pushed commits, `first version` and
  `second version`.

A splice made by `init` records no synced commit, and `push` doesn't write
one. A fresh clone has no fetched refs either, so it can't tell this
splice from one whose upstream is still empty. A splice made by `clone`
records its synced commit, and a fresh clone says it was
[never fetched](../never-fetched/README.md).

Workaround: `git splice fetch` (or `pull`, which fetches) in the clone.
Nothing is lost meanwhile: a push without a fetch is rejected by the
upstream unless it fast-forwards.

## Output

`scenario_init_then_cloned` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_init_then_cloned
```
-->

`.splice` has no synced commit:

```scrut
$ git config --file lib/a/.splice --list
splice.url=$UPSTREAM
```

`status` says the upstream has no such branch, though it has:

```scrut
$ git splice status
??   lib/a -> main (upstream has no such branch -- push would create it)
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
second version
first version
```

`log` shows both published commits as unpushed:

```scrut
$ git splice log
===  lib/a (upstream has no 'main' branch)
< ef82a18 second version  (Test <test@example.com>)
< 766bf9a first version  (Test <test@example.com>)
```

`merge` finds nothing to merge:

```scrut
$ git splice merge lib/a
ok   lib/a: upstream has no 'main' branch -- nothing to merge
```

After a fetch, the clone sees the upstream as it is:

```scrut
$ git splice fetch
ok   lib/a fetched
```

```scrut
$ git splice status
ok   lib/a -> main (up to date)
```
