# clone

`git splice clone [--merge] <url> [<path>]`

Splices an existing repository into a new folder, as one commit.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

In the [sandbox](sandbox.md), `pkg-b.git` isn't spliced in yet:

```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b
===  vendor/pkg-b: fetching https://git.example.com/pkg-b.git
ok   vendor/pkg-b: cloned 9b3cb02 from main
```

The commit adds the upstream's files and `.splice`, which records the
upstream and the commit the folder now matches, U:

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
