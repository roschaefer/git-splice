# Scenario: diverged-unrelated-history

Both sides moved since the subtree was added, but the remote's entire history was
then replaced with something that shares no ancestry with what was last
synced -- e.g. the upstream repo was rebuilt from scratch.

- **Monorepo (`vendor/a`)**: added at `seed`, then one local commit
  under `vendor/a`.
- **Remote**: the original bare repo is deleted and recreated from
  scratch with a brand new, unrelated root commit.
- **Common ancestor**: **no**. `git merge-base` between the commit this
  tool last synced against (recorded in the `git-subtree-split:` trailer
  of the squash commit) and the remote's current tip finds nothing.

This is the case `git subtrees pull`/`push` must **not** try to
auto-merge: there's no principled three-way merge when two sides don't
share history, only a human decision to keep one side and discard the
other's. Both commands detect this and print two manual recovery command
sequences instead of attempting anything (see the output below).

Both sequences were verified by hand against this exact scenario shape
before being wired into `lib/common.sh`'s `print_unrelated_history_guidance`.

## Output

`scenario_diverged_unrelated_history` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_diverged_unrelated_history
```
-->

```scrut
$ git subtrees status
??   vendor/a -> $UPSTREAM (unrelated history -- see 'git subtrees pull vendor/a' for options)
```

```scrut
$ git subtrees pull
ok   vendor/a fetched
??   vendor/a: remote and local share no history -- pick one side manually:

  # accept the remote's version, discarding local changes under vendor/a:
  git rm -r vendor/a
  git commit -m 'remove vendor/a before re-adopting it from its remote'
  git subtree add --prefix=vendor/a vendor/a main --squash

  # OR: accept the local (monorepo) version, overwriting vendor/a's history:
  git subtree split --prefix=vendor/a -b tmp-split-a
  git push --force vendor/a tmp-split-a:main
  git branch -D tmp-split-a

!!   Failed: vendor/a
[1]
```

`push` refuses with the same message.
