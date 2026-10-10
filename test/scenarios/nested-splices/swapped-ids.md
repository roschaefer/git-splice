# Scenario: nested-splices, a and b swap their `.splice`

a contains b, as in the [README](README.md). Then the two `.splice`
files trade places, ids and URLs included: the folder `vendor/a` names
b's upstream, and `vendor/a/b` names a's.

```text
before:  vendor/a    id a, a's upstream      after:  vendor/a    id b, b's upstream
           b/        id b, b's upstream                b/        id a, a's upstream
```

Nobody planned for this. This page records what git splice does, as it
is:

- **Nothing refuses it.** No id repeats in one line of nesting, so it
  isn't a cycle either, a splice that contains itself
  ([#86](https://github.com/roschaefer/git-splice/issues/86)).
- **Each path starts a new history at the swap**, since its `.splice`
  has another id there. Nothing from before it reaches the other
  upstream.
- **But a push replaces the upstream's files.** The swap reads as a
  plain `push: ahead 1`, and pushing `vendor/a` sends a's files to b's
  upstream, as a fast-forward. `clone` refuses a folder whose files
  differ from the upstream's, without `--merge`; a hand-edited `.splice`
  skips that check.
- **A later pull of the folder below doesn't nest a again.** The swap
  removed a's `b/` from it, so the merge keeps it removed.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
a with b spliced in at `b/`, cloned into the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

```scrut
$ git grep -e 'id = ' -e 'url = ' -- '*/.splice' | tr '\t' ' '
vendor/a/.splice: id = b23b165ba51e3878
vendor/a/.splice: url = $UPSTREAM
vendor/a/b/.splice: id = b260547af9afae07
vendor/a/b/.splice: url = https://git.example.com/b.git
```

## The swap

```scrut
$ git mv vendor/a/.splice tmp.splice && git mv vendor/a/b/.splice vendor/a/.splice && git mv tmp.splice vendor/a/b/.splice && git commit -q -m "swap the .splice files"
```

```scrut
$ git grep -e 'id = ' -e 'url = ' -- '*/.splice' | tr '\t' ' '
vendor/a/.splice: id = b260547af9afae07
vendor/a/.splice: url = https://git.example.com/b.git
vendor/a/b/.splice: id = b23b165ba51e3878
vendor/a/b/.splice: url = $UPSTREAM
```

Both read as an ordinary push, each starting at the swap:

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 1)
ok   vendor/a/b -> main (push: ahead 1)
```

```scrut
$ git splice log
===  vendor/a (main)
< [0-9a-f]{7} swap the \.splice files  \(Test <test@example\.com>\) (regex)
===  vendor/a/b (main)
< a813263 swap the .splice files  (Test <test@example.com>)
```

## A push replaces b's files

b's upstream before:

```scrut
$ git -C "$UPSTREAM-b.git" ls-tree -r --name-only main
file.txt
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed [0-9a-f]{7} to main (regex)
```

After, it has a's files, and a nested splice of a:

```scrut
$ git -C "$UPSTREAM-b.git" ls-tree -r --name-only main && git -C "$UPSTREAM-b.git" show main:file.txt
b/.splice
b/file.txt
file.txt
a seed
```

```scrut
$ git -C "$UPSTREAM-b.git" log --format=%s main
swap the .splice files
b seed
```

## A pull of the folder below

a's upstream moves on, still with b nested in it:

```scrut
$ seed_bare_repo "$UPSTREAM" "a moves on" >/dev/null 2>&1 && git -C "$UPSTREAM" ls-tree -r --name-only main
b/.splice
b/file.txt
file.txt
```

The pull of `vendor/a/b`, a's splice now, conflicts on `file.txt`, which
has b's lines here and a's there. a's `b/` doesn't come back:

```scrut
$ git splice pull vendor/a/b
ok   vendor/a/b fetched (main moved da334c3..bc51962)
Auto-merging vendor/a/b/file.txt
CONFLICT (content): Merge conflict in vendor/a/b/file.txt
!!   vendor/a/b: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a/b: pull failed
!!   Failed: vendor/a/b
[1]
```

```scrut
$ git status --short
M  vendor/a/b/.splice
UU vendor/a/b/file.txt
```
