# Scenario: diverged-unrelated-history

Upstream was rebuilt from scratch: it shares no history with the splice.

- **Monorepo (`vendor/a`)**: cloned at `seed`, then a local commit.
- **Upstream**: deleted and recreated with one unrelated commit, fetched.

There's no common ancestor to merge from, so the tool doesn't guess.

## Output

`scenario_diverged_unrelated_history` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_diverged_unrelated_history
```
-->

```scrut
$ git splice status
??   vendor/a -> main (unrelated history -- see 'git splice merge vendor/a' for options)
```

`merge` prints the commands to keep either side, or both:

```scrut
$ git splice merge vendor/a
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
