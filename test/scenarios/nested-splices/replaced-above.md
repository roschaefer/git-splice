# Scenario: nested-splices, replaced in the upstream above

a's upstream replaces b with another repository, b2, at the same
path `b/`. The monorepo has a change in b that it hasn't pushed yet, so
its pull of a conflicts there, and it keeps its own b.

Up to the pull, b's history would come from a's upstream
([spliced elsewhere](spliced-elsewhere.md)). But a's upstream has
another splice at `b/` now, with another `id`: its history isn't b's.
So b's history comes from the monorepo alone, as if a's upstream
didn't splice anything in there. Before, the rebuild joined b2's history
into b's, which a push of b would have published to b's upstream, and
until b2's commits were fetched, `status` failed on a synced commit of
b2's.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=4 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-b2.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/b2.git GIT_CONFIG_KEY_2=user.name GIT_CONFIG_VALUE_2=Test GIT_CONFIG_KEY_3=user.email GIT_CONFIG_VALUE_3=test@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
a with b spliced in at `b/`, cloned into the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

A change in b, not pushed yet:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local"
```

## a's upstream replaces b

b2 is another repository:

```scrut
$ make_bare_repo "$UPSTREAM-b2.git" && seed_bare_repo "$UPSTREAM-b2.git" "b2 seed" >/dev/null 2>&1
```

In a clone of a's upstream, b is removed and b2 spliced in at `b/`:

```scrut
$ git clone -q "$UPSTREAM" ../a-work && cd ../a-work && git rm -q -r b && git commit -q -m "remove b" && git splice clone https://git.example.com/b2.git b && git push -q origin HEAD:main && cd ../monorepo
===  b: fetching https://git.example.com/b2.git
ok   b: cloned 4d884bd from main
```

b2's `.splice` has another id than b's:

```scrut
$ git -C ../a-work config --file b/.splice splice.id; git config --file vendor/a/b/.splice splice.id
4ac6da537149443f
b260547af9afae07
```

## The monorepo keeps its own b

The pull of a conflicts in b:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved da334c3..e2f3da1)
ok   vendor/a/b fetched
Auto-merging vendor/a/b/file.txt
CONFLICT (content): Merge conflict in vendor/a/b/file.txt
!!   vendor/a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a: pull failed
!!   Failed: vendor/a
[1]
```

The monorepo keeps its own b, `.splice` included, and commits the pull:

```scrut
$ git checkout HEAD -- vendor/a/b && git commit -q --no-edit
```

b has only its own history: `b local`, on top of b's synced commit.

```scrut
$ git splice status vendor/a/b
ok   vendor/a/b -> main (push: ahead 1)
```

```scrut
$ git splice log vendor/a/b
===  vendor/a/b (main)
< 701ab17 b local  (Test <test@example.com>)
```
