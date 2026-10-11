# Scenario: many-splices

A monorepo with five splices, each in a different state, on the
monorepo's default branch.

- **Monorepo (`libs/*`)**: `cli`, `http`, `parser`, `store` and `theme`,
  each with its own upstream. Then a local commit in `parser` and one in
  `store`.
- **Upstreams**: two new commits in `http`'s, one in `store`'s. `theme`'s
  default branch is `master`.

`status` gives every splice a line. Those that need something come first,
most urgent first: diverged, then behind, then ahead. Those with nothing
to do come last, after a blank line. A splice names its upstream branch
only where it differs from the monorepo's, like `theme`'s `master`.

The other documents here show the same monorepo
[on a feature branch](feature-branch.md),
[with uncommitted changes](uncommitted-changes.md) and
[in a fresh clone](fresh-clone.md).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_many_splices
```

```scrut
$ git splice status
On branch main

  ahead 1, behind 1  libs/store
  behind 2           libs/http
  ahead 1            libs/parser

  up to date         libs/cli
  up to date         libs/theme -> master
```
