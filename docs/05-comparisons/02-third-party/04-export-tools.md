# Export tools compared

Copybara and Meta's ShipIt move changes between repositories while keeping
a single source of truth. In these export workflows, that is an internal monorepo:
public contributions must land there before they are exported back to GitHub.

## Copybara

[Copybara requires one authoritative repository](https://github.com/google/copybara#readme).
XLA's [contribution notes](https://github.com/openxla/xla/blob/main/docs/copybara.md#pr-merge-status-and-diff-inconsistencies)
explain the consequence: a pull request is tested and submitted internally,
then exported as a separate commit. GitHub shows the PR as closed, not merged;
transformations can also change its diff.

## Meta's ShipIt

ShipIt keeps the internal repository as its single source of truth:
changes are accepted there first to avoid accepting changes independently
in two places. See scrut's [origin](https://github.com/facebookincubator/scrut)
and [fork](https://github.com/roschaefer/scrut).

<div align="center">

![A public PR is imported into private review, accepted internally at the single source of truth, and exported to public main. The PR is closed rather than merged.](shipit-contribution.drawio.svg)

</div>

The result is public, but the internal review is private and GitHub
shows the PR as closed rather than merged.

## With git-splice

The PR can merge directly into public `main`. The monorepo can pull from
the PR branch to test it before the merge, or from `main` afterwards.
Public acceptance does not have to wait for the internal review.

<div align="center">

![The same public and internal repositories, with additional routes: the PR can merge directly into public main, and the monorepo can import either the PR branch or public main.](splice-contribution.drawio.svg)

</div>

The example below tests a PR branch in the monorepo, merges it in public,
then pulls public `main`.

The setup: `https://git.example.com/lib.git`, a public library with 30
commits, and a monorepo with an app. [How these pages run](../01-git/README.md).

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
$ git clone -q https://git.example.com/lib.git ../contributor &&
>   git -C ../contributor switch -q -c contribution &&
>   echo "external contribution" >>../contributor/src/parse.txt &&
>   git -C ../contributor commit -q -a -m "external contribution" &&
>   git -C ../contributor push -q origin contribution
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
$ git -C ../contributor switch -q main &&
>   git -C ../contributor merge -q --no-ff contribution -m "Merge external contribution" &&
>   git -C ../contributor push -q origin main
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
$ git log -1 --format=%s
splice: pull vendor/lib from main at c174d0d
```

```scrut
$ tail -n 1 vendor/lib/src/parse.txt
external contribution
```
