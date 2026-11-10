# Nesting

An upstream can use `git-splice` itself, e.g. an app with its library
spliced in. Clone the app into the monorepo, and the library comes along
as a splice of its own, *nested* in the app's. Nothing has to be cloned
recursively, as with `git clone --recurse-submodules`: the library's
`.splice` is an ordinary file of the app.

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../09-scenarios/readme-setup.sh" &&
>   source "$TESTDIR/../09-scenarios/05-nested-splices/03-diamond/setup.bash" &&
>   scenario_diamond "$PWD/monorepo" "$UPSTREAM" >/dev/null 2>&1 &&
>   cd monorepo
```
-->

The app's upstream has its library at `c/`, with a `c/.splice`. One
`clone` gives the monorepo both:

```scrut
$ git splice clone https://git.example.com/a.git a
===  a: fetching https://git.example.com/a.git
ok   a: cloned 6962bd0 from main
ok   a/c fetched
```

```scrut
$ git splice status
On branch main

  up to date  a
  up to date  a/c
```

`a/c/` is a splice now, and `clone` fetched the library's upstream too,
as it does for every splice that comes along: both are ready to sync.

## Each splice syncs with the monorepo

A nested splice syncs like any other: `merge` and `pull` merge its
upstream straight into the monorepo, and `push` sends its own commits.
The library's folder ends up with the same files as if you pulled the
library in a clone of the app, and then the app into the monorepo. But no commit of the
app with the pulled library is made on the way, and each `.splice` is
read once, when the command starts
([#336](https://github.com/roschaefer/git-splice/issues/336)).

<div align="center">

![The monorepo commit a; in the lane vendor/a/, the upstream commits k and l; in the lane vendor/a/b/, drawn inside it, the upstream commit m, which the b/.splice of l records](../09-scenarios/05-nested-splices/01-nested-splices/nested-splices.drawio.svg)

</div>

The nested `.splice` is a file of the splice above, so it travels with
it. In the drawing, commit *l* of the upstream above has the `.splice` of
the splice below, which records *m*: U(l) = *m*. That ties the splices
together in three ways:

- **Pull top-down.** Pulling the splice above brings in the nested
  `.splice` as its upstream has it, which can move the synced commit of
  the splice below. So `merge` and `pull` take the splice above first.
- **The rebuild records the splices inside it.** The rebuild of the
  splice above writes into the nested `.splice` the rebuild of the
  splice below: the commit that splice's upstream gets with the same
  push. The push sends what the rebuild made and, as always, writes
  nothing to the monorepo, which keeps its own record. So one push of
  both leaves the upstream above recording what the one below got from
  the monorepo; an upstream that moved on is pulled first, as before any
  push
  ([scenario](../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/pulled-level-by-level.md)).
  The splice below goes first, so the record names a commit its upstream
  has, and `push --all` stops at a failed push before the splice above.
  Should the splice above be pushed on its own anyway, a clone of its
  upstream makes the recorded commit again from its own history
  ([scenario](../09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/failed-push-below.md)).
- **History from above.** The splice above came in squashed, so the
  monorepo lacks the older history of the splice below. A push takes it
  from the upstream above
  ([scenario](../09-scenarios/05-nested-splices/01-nested-splices/spliced-elsewhere.md)).

## Settings come from the splice above

You could run `git-splice` in a clone of the app, with the app as the
monorepo. A nested `.splice` has to mean the same there as here. So a
nested `.splice` without `default-branch` follows the default branch of
the splice above, which follows its own splice above, up to the
monorepo
([scenario](../09-scenarios/05-nested-splices/02-nested-default-branch/README.md)).
If a splice above is pinned with `default-pin` instead, the splice below
refuses until it records a `default-branch` of its own.

## Read more

- [Nested splices](../09-scenarios/05-nested-splices/01-nested-splices/README.md)
  that are dropped, replaced or pushed from above, and [three
  levels](../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/README.md).
- A [diamond](../09-scenarios/05-nested-splices/03-diamond/README.md):
  two apps that splice in the same library.
- A [cycle](../09-scenarios/05-nested-splices/04-cycle/README.md): a
  splice that contains itself.
