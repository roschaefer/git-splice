# Scenario: concurrent-pulls

Two developers pull the same splice on `main` at different times. Each
pull writes a commit that changes the same line of `.splice`, the synced
commit, and the same lines of the files the upstream changed. When the
second developer merges the first one's work, Git reports conflicts in
both.

- **Upstream**: `seed`, `upstream 1`, `upstream 2`.
- **Alice's monorepo**, pushed as `origin/main`: cloned at `seed`, then
  pulled `upstream 1`.
- **Bob's monorepo**, this one: cloned at `seed`, then pulled `upstream 2`,
  without pulling the monorepo first.

To avoid this, pull the monorepo before you pull a splice. To get out of
it, resolve the conflict as below, or [redo the pull](redo-the-pull.md).
If `.splice` is committed with conflict markers anyway,
[every command stops](committed-conflict-markers.md) until it's fixed.

## Output

`scenario_concurrent_pulls` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_concurrent_pulls
```
-->

```scrut
$ git log --graph --format=%s HEAD origin/main
* splice: pull vendor/a from main at 4c1905d
| * splice: pull vendor/a from main at 72efaac
|/  
* splice: clone vendor/a from main at bde4164
* initial commit
```

```scrut
$ git merge origin/main
Auto-merging vendor/a/.splice
CONFLICT (content): Merge conflict in vendor/a/.splice
Auto-merging vendor/a/file.txt
CONFLICT (content): Merge conflict in vendor/a/file.txt
Automatic merge failed; fix conflicts and then commit the result.
[1]
```

```scrut
$ git status --short
UU vendor/a/.splice
UU vendor/a/file.txt
```

Both sides changed the synced commit (`expand` shows the tabs as spaces):

```scrut
$ expand vendor/a/.splice
[splice]
<<<<<<< HEAD
        commit = 4c1905de64f0df0a488c0b63482302ec229fdce9
=======
        commit = 72efaacc5c6b50e5d2a6fe51a30af958c8adae51
>>>>>>> origin/main
[upstream "origin"]
        url = https://git.example.com/a.git
```

While the merge is in progress, `pull` and `merge` refuse to start.
`status`, `log`, `diff` and `push` read the last commit, not the
conflicted files, so they still show the state from before the merge.
`status` adds that the folder has uncommitted changes, the conflicted
files:

```scrut
$ git splice pull vendor/a
!!   a cherry-pick or merge is in progress -- conclude it first
[1]
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
??   vendor/a has uncommitted changes -- push only sends committed ones
```

### Resolving

Keep the newer sync point: the one whose history contains the other's.
The fetched upstream branch shows both, newest first: Bob's `upstream 2`
contains Alice's `upstream 1`:

```scrut
$ git log --format='%h %s' splices/https%3A/%/git.example.com/a.git/-/main
4c1905d upstream 2
72efaac upstream 1
bde4164 seed
```

Only the upstream changed the folder on both sides, so the whole folder
is resolved to Bob's side, `--ours`, which has the newer sync point. Had
Alice also changed files in the folder herself, those would need resolving
by hand, but `.splice` would still take the newer sync point:

```scrut
$ git checkout --ours -- vendor/a && git add vendor/a
```

`git diff --check` finds leftover conflict markers, and `git config`
refuses a `.splice` it can't read:

```scrut
$ git diff --cached --check && git config --file vendor/a/.splice --list
splice.commit=4c1905de64f0df0a488c0b63482302ec229fdce9
upstream.origin.url=https://git.example.com/a.git
```

```scrut
$ git commit -q --no-edit && git splice status
ok   vendor/a -> main (up to date)
```
