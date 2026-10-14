# clone

`git splice clone [--merge] <url> [<path>]`\
`git splice clone --from-submodule <path>`

Splices an existing repository into a new folder, as one commit, or turns
a submodule into a splice.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

In the [sandbox](../../docs/sandbox.md), `pkg-b.git` isn't spliced in yet:

```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b
===  vendor/pkg-b: fetching https://git.example.com/pkg-b.git
ok   vendor/pkg-b: cloned 9b3cb02 from main
```

The commit adds the upstream's files and
[`.splice`](../concepts/splice-file/README.md), which records the
upstream and the commit the folder now matches, U(H):

```scrut
$ git show --stat --format=%s
splice: clone vendor/pkg-b from main at 9b3cb02

 vendor/pkg-b/.splice  | 5 +++++
 vendor/pkg-b/file.txt | 1 +
 2 files changed, 6 insertions(+)
```

```scrut
$ git config --file vendor/pkg-b/.splice --list
splice.id=6c92e1a0e36b0b6d
splice.commit=9b3cb02af44029fd61f1a57699c3dbf033958071
upstream.origin.url=https://git.example.com/pkg-b.git
```

## From a submodule

Here `vendor/pkg-b/` is a submodule of the same repository instead, and
its checkout is at the upstream's `main`:

<!-- The submodule's clone can't see the sandbox's url.<dir>.insteadOf,
which only the monorepo's config has, so it's added from the bare
repository and gets the URL a real one would have.
```scrut
$ git reset -q --hard HEAD^ && git -c protocol.file.allow=always submodule add -q "$WALKTHROUGH/upstream/pkg-b.git" vendor/pkg-b && git config --file .gitmodules submodule.vendor/pkg-b.url https://git.example.com/pkg-b.git && git submodule sync -q && git add .gitmodules && git commit -q -m "add vendor/pkg-b as a submodule"
```
-->

```scrut
$ cat .gitmodules
[submodule "vendor/pkg-b"]
	path = vendor/pkg-b
	url = https://git.example.com/pkg-b.git
```

`--from-submodule` keeps its URL and the commit it points to:

```scrut
$ git splice clone --from-submodule vendor/pkg-b
===  vendor/pkg-b: fetching https://git.example.com/pkg-b.git
ok   vendor/pkg-b: cloned 9b3cb02 from the submodule
===  vendor/pkg-b: the submodule's repository stays in $WALKTHROUGH/monorepo/.git/modules/vendor/pkg-b -- remove it once you don't need it
```

One commit replaces the submodule with its files and a `.splice`, and
removes it from `.gitmodules`, here the whole file:

```scrut
$ git show --stat --format=%s
splice: clone vendor/pkg-b from submodule at 9b3cb02

 .gitmodules           | 3 ---
 vendor/pkg-b          | 1 -
 vendor/pkg-b/.splice  | 5 +++++
 vendor/pkg-b/file.txt | 1 +
 4 files changed, 6 insertions(+), 4 deletions(-)
```

The commit has to be on a branch upstream, so it's there for everyone
after the switch. A checkout of the submodule must be at it, without
changes, or `clone` refuses. Settings in `.gitmodules` other than `path`
and `url` have no equivalent and are dropped, with a warning: a splice
syncs with the upstream branch named like the monorepo's current branch,
not with `submodule.<name>.branch`. Other branches still have the
submodule. Converting it on the main branch and merging that into them
avoids a conflict between the submodule and the folder.

## More

- If the folder already exists and differs, `clone` refuses. With
  `--merge`, every file that differs becomes a conflict to resolve, and
  nothing is lost
  ([clone-differing-content](../scenarios/clone-differing-content/README.md)).
  If the folder already has exactly the upstream's files, `clone` only
  adds `.splice` ([clone-copied-content](../scenarios/clone-copied-content/README.md)).
- On a branch the upstream doesn't have, `clone` takes the upstream's
  default branch. The first push creates the branch upstream, if the
  splice changed by then
  ([clone-on-feature-branch](../scenarios/clone-on-feature-branch/README.md)).
- A clone is a commit on top of `HEAD`, so a monorepo without commits
  needs a first one
  ([clone-without-commits](../scenarios/clone-without-commits/README.md)).
- To publish a folder of the monorepo to a new, empty repository, use
  [`init`](init.md).
