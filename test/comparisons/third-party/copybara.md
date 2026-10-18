# Copybara compared

[Copybara requires one repository to be authoritative](https://github.com/google/copybara#readme).
In the common workflow where that source of truth is an internal monorepo,
a public pull request is imported and submitted there. For example, XLA's
[Copybara notes](https://github.com/openxla/xla/blob/main/docs/copybara.md#pr-merge-status-and-diff-inconsistencies)
explain that the original pull request is closed rather than marked as
merged, while a separate commit is applied publicly.

Meta works the same way, with its own tools. This repository splices
[scrut](https://github.com/facebookincubator/scrut) into `scrut/`, so we
see it from outside:

- **The source of truth is internal.** scrut's commit messages name a
  `scrut/BUCK` file and dependencies in `fbsource//third-party`, which
  aren't on GitHub, and say that `Cargo.toml` is generated from them.
- **Every public commit is an export.** Almost all of them end with
  `Differential Revision: D…`, an internal review, and
  `fbshipit-source-id: …`, the internal commit it came from. The committer
  is a bot, `meta-codesync`, and the author keeps their name.
- **A pull request is imported, not merged.** The bot comments that the
  pull request was "imported" into an internal review, and later "merged
  this pull request in" a new commit, with
  `Pull Request resolved: …/pull/48` in its message
  ([#48](https://github.com/facebookincubator/scrut/pull/48)). On GitHub,
  the pull request is closed.
- **Drift is fixed by hand.** When the two sides differ, the bot opens a
  pull request to "re-sync with internal repository", to be merged on
  GitHub with the export turned off
  ([#59](https://github.com/facebookincubator/scrut/pull/59)).

The tool behind this was [FBShipIt](https://github.com/facebook/fbshipit),
now archived: it maps a folder of the internal repository to the
public one and leaves out internal files. `meta-codesync` likely
continues it. The internal repository is likely on
[Sapling](../vcs/sapling.md), Meta's version control system, whose own
public commits are exported the same way. `fbshipit-source-id` is a sync
point as text in the commit message, like `cherry-pick -x`
([weak parents](../../../docs/going-forward/weak-parents.md)).

For a contribution, that means it comes back as a different commit, and
a change that adds a Rust dependency also needs one in Meta's
`third-party` folder.

With `git-splice`, the monorepo can pull the contributor's branch for its
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
