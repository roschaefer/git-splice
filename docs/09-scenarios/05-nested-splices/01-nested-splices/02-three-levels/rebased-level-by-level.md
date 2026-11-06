# Scenario: nested-splices, three levels: rebased one level at a time

`git splice pull --rebase vendor/a/b/c` takes the innermost upstream in
on top of the last pull, and replays the monorepo's own commits on top
of it, with `git rebase`. This page does the same one level at a time,
by hand, as [pulled one level at a time](pulled-level-by-level.md) does
for a merge. Two things change:

- Each worktree starts at the level's synced commit, not at its
  rebuild: the pull lands on the upstream's history alone, without the
  monorepo's changes, and goes up level by level without a conflict.
- The monorepo's own commits are replayed last, in the monorepo: they
  are the only ones that are really there. The conflict comes up then.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=5 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/c.git GIT_CONFIG_KEY_2=user.name GIT_CONFIG_VALUE_2=Test GIT_CONFIG_KEY_3=user.email GIT_CONFIG_VALUE_3=test@example.com GIT_CONFIG_KEY_4=core.editor GIT_CONFIG_VALUE_4=true
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_three_levels https://git.example.com/b.git https://git.example.com/c.git
```

The inner upstream and the monorepo change the same file:

```scrut
$ git clone -q https://git.example.com/c.git ../c-work &&
>   echo "c upstream" >>../c-work/file.txt &&
>   git -C ../c-work commit -q -am "c upstream" &&
>   git -C ../c-work push -q origin main
```

```scrut
$ echo "c local" >>vendor/a/b/c/file.txt &&
>   git commit -q -am "c local"
```

```scrut
$ git splice fetch vendor/a vendor/a/b vendor/a/b/c
ok   vendor/a fetched
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched (main moved 0bfc154..68ea527)
```

<!--
```scrut
$ monorepo="$PWD" s="$(git rev-parse HEAD~1)" c="$(git rev-parse HEAD)" &&
>   k="$(git config --file vendor/a/.splice splice.commit)" &&
>   l="$(git config --file vendor/a/b/.splice splice.commit)" &&
>   n="$(git config --file vendor/a/b/c/.splice splice.commit)" &&
>   u="$(git rev-parse refs/splices/c/heads/main)"
```
-->

Each lane is one level, drawn inside the one above it. The monorepo's
*c* changes the innermost folder, so each level's rebuild, R, has a copy
of it, *c'*, on top of the synced commit. Only the innermost upstream
moved on, to *u*:

<div align="center">

![The monorepo's s and c, H at c; in vendor/a/, k, T and U(H), and on top of it, dashed, c prime, R; in vendor/a/b/ the same with l; in vendor/a/b/c/, n, U(H), u on top of it, T, and c prime on top of n, dashed, R](levels-before.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/levels-before.drawio.svg" \
>   s="$s" c="$c" k="$k" l="$l" n="$n" u="$u"
ok   levels-before.drawio.svg: 9 commits, 13 arrows, 8 boxes, 3 lanes
```
-->

## 1. The outer upstream's repository

`vendor/a/`'s synced commit, checked out in a worktree on a branch of
its own, `layer/a`: the outer upstream's history as the monorepo last
took it in, without its changes since:

```scrut
$ git worktree add -q -b layer/a ../a-layer "$(git config --file vendor/a/.splice splice.commit)"
```

The commands from here on run there, not in the monorepo:

```scrut
$ cd ../a-layer
```

## 2. The middle upstream's repository

In it, `b/` is a splice, and its synced commit, checked out as
`layer/b`, is the middle upstream's history the same way:

```scrut
$ git worktree add -q -b layer/b ../b-layer "$(git config --file b/.splice splice.commit)"
```

The commands from here on run there, one level further down:

```scrut
$ cd ../b-layer
```

```scrut
$ git log --format=%s
add c
b seed
```

## 3. The pull, one level down

Nothing here changed `c/`, so the pull has nothing to conflict with:

```scrut
$ git splice pull --branch main c
ok   c fetched
ok   c: pulled 68ea527
```

```scrut
$ git log --format=%s
splice: pull c from main at 68ea527
add c
b seed
```

The pull's commit, *p*, sits on *l* alone: the monorepo's *c'* isn't in
this repository, so nothing conflicts. Both *p* and *u*, which it brought
in, are blue:

<div align="center">

![The monorepo's s and c, H at c; in vendor/a/, k and its R, c prime, and the dashed box layer/a at k; in vendor/a/b/, shaded, l, c prime, R, and p, outlined blue, on l, dashed, layer/b; in vendor/a/b/c/, n, c prime, R, and u, outlined blue, T and U(p)](rebased-pulled-below.drawio.svg)

</div>

<!--
```scrut
$ (cd "$monorepo" &&
>   check_drawing "$TESTDIR/rebased-pulled-below.drawio.svg" \
>     s="$s" k="$k" l="$l" n="$n" u="$u" c="$c" p=layer/b)
ok   rebased-pulled-below.drawio.svg: 10 commits, 16 arrows, 10 boxes, 3 lanes
```
-->

## 4. Into the outer upstream's repository

The commands run in the outer upstream's repository again, one level up:

```scrut
$ cd ../a-layer
```

```scrut
$ git splice merge --rebuilt-commit layer/b b
ok   b: merged 28a49d9
```

```scrut
$ git log --format=%s
splice: pull c from main at 68ea527
add b
a seed
```

*q* takes *p* into `b/`, on *k*, again without a conflict:

<div align="center">

![As before, and in vendor/a/, shaded, q, outlined blue, on k, dashed, layer/a; l is U(q) too, and u U(q)](rebased-merged-into-a.drawio.svg)

</div>

<!--
```scrut
$ (cd "$monorepo" &&
>   check_drawing "$TESTDIR/rebased-merged-into-a.drawio.svg" \
>     s="$s" k="$k" l="$l" n="$n" u="$u" c="$c" p=layer/b q=layer/a)
ok   rebased-merged-into-a.drawio.svg: 11 commits, 17 arrows, 10 boxes, 3 lanes
```
-->

## 5. Into the monorepo, below its own commits

The commands run in the monorepo again:

```scrut
$ cd ../monorepo
```

The pull goes in where `vendor/a/` was last synced, at B, on a branch of
its own, `pulled`, below the monorepo's own commits:

```scrut
$ git switch -q -c pulled "$(git splice boundary vendor/a)"
```

```scrut
$ git splice merge --rebuilt-commit layer/a vendor/a
ok   vendor/a: merged d8dc240
```

`main` still has the monorepo's own commit, *c*, on the other side of B:

```scrut
$ git switch -q main
```

<div align="center">

![The monorepo's s, with c on main, H, and m, outlined blue, on pulled; the lanes as before](rebased-pulled-into-monorepo.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/rebased-pulled-into-monorepo.drawio.svg" \
>   s="$s" k="$k" l="$l" n="$n" u="$u" c="$c" m=pulled p=layer/b q=layer/a
ok   rebased-pulled-into-monorepo.drawio.svg: 12 commits, 19 arrows, 11 boxes, 3 lanes
```
-->

## 6. The monorepo's own commits on top

`main` is rebased onto `pulled`. The monorepo's *c* changed the same
lines as *u*, so the conflict comes up now, in the monorepo:

```scrut
$ git rebase pulled
Auto-merging vendor/a/b/c/file.txt
CONFLICT (content): Merge conflict in vendor/a/b/c/file.txt
error: could not apply *... c local (glob)
hint: Resolve all conflicts manually, mark them as resolved with
hint: "git add/rm <conflicted_files>", then run "git rebase --continue".
hint: You can instead skip this commit: run "git rebase --skip".
hint: To abort and get back to the state before "git rebase", run "git rebase --abort".
hint: Disable this message with "git config set advice.mergeConflict false"
Could not apply *... # c local (glob)
[1]
```

```scrut
$ printf 'c seed\nc local\nc upstream\n' >vendor/a/b/c/file.txt &&
>   git add vendor/a/b/c/file.txt &&
>   git rebase --continue
[detached HEAD *] c local (glob)
 1 file changed, 1 insertion(+)
Successfully rebased and updated refs/heads/main.
```

The pull is below the monorepo's own commit now, as `pull --rebase`
leaves it:

```scrut
$ git log --format=%s
c local
splice: pull c from main at 68ea527
add vendor/a
initial commit
```

*r* is *c* rebased onto *m*. Each level's rebuild follows: *r'* sits on
the pull, and the pull is the very commit the worktree made there, *q*
in `vendor/a/` and *p* in `vendor/a/b/`. At every level, the blue commit
is below the monorepo's own change:

<div align="center">

![The monorepo's s, m, outlined blue, pulled, and r, H; in vendor/a/, k, q, outlined blue, layer/a, and r prime, R; in vendor/a/b/, l, p, outlined blue, layer/b, and r prime, R; in vendor/a/b/c/, n, u, outlined blue, T and U(H), and r prime, R](rebased-rebased.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/rebased-rebased.drawio.svg" \
>   s="$s" k="$k" l="$l" n="$n" u="$u" m=pulled r=HEAD p=layer/b q=layer/a
ok   rebased-rebased.drawio.svg: 12 commits, 18 arrows, 10 boxes, 3 lanes
```
-->

The innermost splice has *c* to push. The levels above have the pull
too: its commit took the new `.splice` in as their own change, as in
[pulled one level at a time](pulled-level-by-level.md):

```scrut
$ git splice status
On branch main

  ahead 2  vendor/a
  ahead 2  vendor/a/b
  ahead 1  vendor/a/b/c
```

## 7. Pushed

```scrut
$ git splice push vendor/a/b/c vendor/a/b vendor/a
ok   vendor/a/b/c: pushed e561e61 to main
ok   vendor/a/b: pushed 56402be to main
ok   vendor/a: pushed 58854d1 to main
```

The innermost upstream has the monorepo's change on top of its own, in
one line, with no merge commit: what a rebase is for.

```scrut
$ git -C "$UPSTREAM-c.git" log --format=%s main
c local
c upstream
c seed
```

<div align="center">

![As before, with every commit solid, and T = R at each r prime](rebased-pushed.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/rebased-pushed.drawio.svg" \
>   s="$s" k="$k" l="$l" n="$n" u="$u" m=pulled r=HEAD p=layer/b q=layer/a
ok   rebased-pushed.drawio.svg: 12 commits, 18 arrows, 10 boxes, 3 lanes
```
-->
