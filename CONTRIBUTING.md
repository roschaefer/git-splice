# Contributing

Bug reports, ideas and pull requests are welcome.

## Issues

Describe what you ran, what you expected and what happened instead. Real
but rare problems are labeled
[`edge case`](https://github.com/roschaefer/git-splice/issues?q=label%3A%22edge+case%22):
they are handled later, not in the pull request that found them.

## Pull requests

1. Set up the [development environment](docs/development.md).
2. Change behaviour together with a test whose name states it. If the
   output changes, `just docs-check --write` updates the scenarios and
   walkthroughs, and the diff shows readers what changed.
3. Write documentation by the rules in [writing the docs](docs/writing.md):
   which markup marks a command, a commit, a role or a splice.
4. Run `just ci`: lint, formatting, tests, docs-check and the site build.
5. Open the pull request as a draft. Expensive checks such as the
   benchmark run only once it is marked ready for review.

Pull requests are squash-merged, so the title becomes the commit message
on `main`. It must follow
[Conventional Commits](https://www.conventionalcommits.org/), e.g.
`fix(push): ...`, since release-please builds the changelog from it. The
description should say why the change is needed.
