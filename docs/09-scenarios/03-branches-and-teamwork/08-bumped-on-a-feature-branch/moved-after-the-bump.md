# Scenario: bumped-on-a-feature-branch, moved after the bump

> **Known bug, [#466](https://github.com/roschaefer/git-splice/issues/466).** This page shows what `git-splice` does today, bug included. See [all known bugs](../../99-known-bugs.md).

As in [the README](README.md), the library deletes the branch a bump
recorded, so a fresh clone makes the synced commit again from the
monorepo's history. Here the monorepo moved the splice after the bump,
and the clone doesn't find the commit that recorded it: it looks for it
at the splice's path now, where the move is the first commit to name
it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_bumped_on_a_feature_branch &&
>   MONOREPO="$PWD"
```

A feature, pushed to the library's `feature` branch, and bumped there:

```scrut
$ git switch -q -c feature &&
>   echo "an option" >>vendor/a/file.txt &&
>   git commit -qam "an option"
```

```scrut
$ git splice push vendor/a >/dev/null && git splice pull --bump vendor/a
ok   vendor/a fetched
ok   vendor/a: bumped the synced commit to c625212
```

`main` takes it, and then moves the splice:

```scrut
$ git switch -q main &&
>   git merge -q --ff-only feature &&
>   mkdir -p libs &&
>   git mv vendor/a libs/a &&
>   git commit -qm "move vendor/a to libs/a"
```

The library deletes its `feature` branch, and its `gc` removes the
commit the bump recorded:

```scrut
$ git -C "$UPSTREAM" branch -q -D feature &&
>   git -C "$UPSTREAM" gc -q --prune=now
```

A fresh clone of the monorepo:

```scrut
$ cd "$(dirname "$MONOREPO")" &&
>   git clone -q "file://$MONOREPO" colleague &&
>   cd colleague &&
>   git splice fetch libs/a
ok   libs/a fetched
```

```scrut
$ git splice status libs/a
On branch main

  ?? synced commit c625212 isn't here  libs/a  run 'git splice fetch libs/a', or check that upstream has it
```
