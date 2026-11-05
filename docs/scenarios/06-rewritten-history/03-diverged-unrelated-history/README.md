# Scenario: diverged-unrelated-history

Upstream was rebuilt from scratch: it shares no history with the splice.

<div align="center">

![The monorepo commit a clones the upstream commit k, then b changes the folder, rebuilt as b prime on top of k, R; the upstream now has only z, T, unrelated to k, which is dashed](unrelated-history.drawio.svg)

</div>

There's no common ancestor to merge from, so the tool doesn't guess.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_diverged_unrelated_history
```

<!--
```scrut
$ k="$(git config --file vendor/a/.splice splice.commit)" &&
>   check_drawing "$TESTDIR/unrelated-history.drawio.svg" k="$k" a=HEAD~1 b=HEAD z=splices/upstream/heads/main
ok   unrelated-history.drawio.svg: 5 commits, 5 arrows, 3 boxes, 1 lanes
```
-->

```scrut
$ git splice status
On branch main

  !! unrelated history  vendor/a  see 'git splice merge vendor/a' for options
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
