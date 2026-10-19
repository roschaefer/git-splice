# Scenario: nested-splices, replaced in the upstream above

The outer upstream replaces the inner upstream with another repository,
the replacement, at the same path `b/`. The monorepo has a change in
`vendor/a/b/` that it hasn't pushed yet, so its pull of `vendor/a/`
conflicts there, and it keeps its own `vendor/a/b/`.

Up to the pull, the history of `vendor/a/b/` would come from the outer
upstream ([spliced elsewhere](spliced-elsewhere.md)). But the outer
upstream has another splice at `b/` now, with another `id`: its history
isn't the inner splice's. So the history of `vendor/a/b/` comes from the
monorepo alone, as if the outer upstream didn't splice anything in
there. Before, the rebuild joined the replacement's history into it,
which a push of `vendor/a/b/` would have published to the inner
upstream, and until the replacement's commits were fetched, `status`
failed on a synced commit of the replacement's.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=4 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-b2.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/b2.git GIT_CONFIG_KEY_2=user.name GIT_CONFIG_VALUE_2=Test GIT_CONFIG_KEY_3=user.email GIT_CONFIG_VALUE_3=test@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
the outer upstream with the inner one spliced in at `b/`, cloned into
the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

A change in `vendor/a/b/`, not pushed yet:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local"
```

## The outer upstream replaces the inner one

The replacement is another repository, `$UPSTREAM-b2.git`:

```scrut
$ make_bare_repo "$UPSTREAM-b2.git" &&
>   seed_bare_repo "$UPSTREAM-b2.git" "b2 seed" >/dev/null 2>&1
```

In a clone of the outer upstream, `b/` is removed and the replacement
spliced in there:

```scrut
$ git clone -q "$UPSTREAM" ../a-work &&
>   cd ../a-work &&
>   git rm -q -r b &&
>   git commit -q -m "remove b" &&
>   git splice clone https://git.example.com/b2.git b &&
>   git push -q origin HEAD:main &&
>   cd ../monorepo
===  b: fetching https://git.example.com/b2.git
ok   b: cloned 4d884bd from main
```

The replacement's `.splice` has another id than the inner splice's:

```scrut
$ git -C ../a-work config --file b/.splice splice.id
> git config --file vendor/a/b/.splice splice.id
88a02361b312d5a4
548ac82ad47ea22d
```

## The monorepo keeps its own `vendor/a/b/`

The pull of `vendor/a/` conflicts in `vendor/a/b/`:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved ddf42f3..e114b33)
ok   vendor/a/b fetched
Auto-merging vendor/a/b/file.txt
CONFLICT (content): Merge conflict in vendor/a/b/file.txt
!!   vendor/a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a: pull failed
!!   Failed: vendor/a
[1]
```

The monorepo keeps its own `vendor/a/b/`, `.splice` included, and
commits the pull:

```scrut
$ git checkout HEAD -- vendor/a/b && git commit -q --no-edit
```

`vendor/a/b/` has only its own history: `b local`, on top of its synced
commit.

```scrut
$ git splice status vendor/a/b
On branch main

  ahead 1  vendor/a/b
```

```scrut
$ git splice log vendor/a/b
===  vendor/a/b (main)
< 701ab17 b local  (Test <test@example.com>)
```
