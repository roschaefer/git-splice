# Copybara compared

[Copybara requires one repository to be authoritative](https://github.com/google/copybara#readme).
In the common workflow where that source of truth is an internal monorepo,
a public pull request is imported and submitted there. For example, XLA's
[Copybara notes](https://github.com/openxla/xla/blob/main/docs/copybara.md#pr-merge-status-and-diff-inconsistencies)
explain that the original pull request is closed rather than marked as
merged, while a separate commit is applied publicly.

With `git splice`, the monorepo can pull the contributor's branch for its
own tests without publishing anything. The maintainers then merge the pull
request in the public repository, and the monorepo pulls the resulting
`main`. This page shows that workflow; it doesn't run Copybara.

The setup: `https://git.example.com/lib.git`, a public library with 30
commits, and a monorepo with an app. [How these pages run](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```
-->

The monorepo has the library as a splice:

```scrut
$ git splice clone https://git.example.com/lib.git vendor/lib
===  vendor/lib: fetching https://git.example.com/lib.git
ok   vendor/lib: cloned bafd496 from main
```

## An external contribution

A contributor opens a pull request in the public library, from a
`contribution` branch:

```scrut
$ git clone -q https://git.example.com/lib.git ../contributor && git -C ../contributor switch -q -c contribution && echo "external contribution" >>../contributor/src/parse.txt && git -C ../contributor commit -q -a -m "external contribution" && git -C ../contributor push -q origin contribution
```

## Test it in the monorepo

On a monorepo branch of the same name, `pull` brings the contribution in,
to test it together with the app:

```scrut
$ git switch -q -c contribution && git splice pull vendor/lib
ok   vendor/lib fetched
ok   vendor/lib: pulled 4085e21
```

```scrut
$ tail -n 1 vendor/lib/src/parse.txt
external contribution
```

Nothing is published: the public `main` is unchanged, and the monorepo's
`main` doesn't have the contribution.

```scrut
$ git -C "$COMPARISON/upstream/lib.git" log --format=%s -1 main
lib commit 30
```

```scrut
$ git show main:vendor/lib/src/parse.txt | tail -n 1
line 30
```

## Merge it in public

The maintainers merge the pull request in the public library, where the
contributor sees it as merged:

```scrut
$ git -C ../contributor switch -q main && git -C ../contributor merge -q --no-ff contribution -m "Merge external contribution" && git -C ../contributor push -q origin main
```

```scrut
$ git -C "$COMPARISON/upstream/lib.git" log --graph --format=%s -4 main
*   Merge external contribution
|\  
| * external contribution
|/  
* lib commit 30
* lib commit 29
```

The monorepo's `main` pulls the merge result:

```scrut
$ git switch -q main && git splice pull vendor/lib
ok   vendor/lib fetched (main moved bafd496..c174d0d)
ok   vendor/lib: pulled c174d0d
```

```scrut
$ git log -1 --format=%s && tail -n 1 vendor/lib/src/parse.txt
splice: pull vendor/lib from main at c174d0d
external contribution
```
