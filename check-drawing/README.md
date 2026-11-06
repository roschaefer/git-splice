# check-drawing

Checks a draw.io drawing of commit graphs against the repositories it
shows.

A drawing that explains a Git history goes stale without anyone
noticing: the history in the docs' setup changes, and the picture still
shows the old one. `check-drawing` reads the diagram embedded in a
`.drawio.svg`, looks up each commit, arrow and label in the real
repositories, and names every difference.

It's made for drawings of [`git-splice`](../README.md) histories: a
monorepo, the upstreams of its splices, and the names of
`git-splice`'s [sync model](../docs/03-concepts/02-sync-model.md),
H, B, T, R, U(x) and tracked(x).

## Usage

In the monorepo, with the path to `check-drawing/check-drawing`:

```sh
check-drawing/check-drawing <drawing> [<label>=<rev>...]
```

`<drawing>` is a `.drawio.svg`, or a `.drawio` file. When everything
matches, it prints what it checked and succeeds:

```
ok   after-pull.drawio.svg: 12 commits, 16 arrows, 5 boxes, 1 lanes
```

Otherwise it prints each difference, with what to change, and fails:

```
!!   R points at d', the code says e'
!!   b' is solid, but no upstream branch has it: dash it
```

A circle's label is the commit's subject, or its start up to a colon:
*a* is `a: add vendor/a`. Another tool's commit, whose message you
can't choose, gets a label given as `<label>=<rev>`, a revision of the
monorepo: `a=HEAD~3`. A box's name
given that way points at that revision, e.g. a commit another tool
records, as `parent=<rev>`.

Drawings for readers who don't know the sync model yet can use other
names, given as `--alias <name>=<term>`, before the labels. With Git's
names for a three-way merge:

```sh
check-drawing/check-drawing before-pull-git-names.drawio.svg \
  --alias HEAD=H --alias boundary=B --alias ours=R --alias theirs=T \
  --alias 'base=merge-base(R,T)' a=HEAD~3
```

An alias works inside `U(…)` too: `U(boundary)` is U(B). Without
`--alias`, a name like `ours` is an upstream branch.

Sourced, the file defines the function `check_drawing`, with the same
arguments.

### Labels in the prose

```sh
check-drawing/check-drawing labels <page>...
```

checks that each Markdown page shows every commit its prose names in
italics, *k* or *b'*: a circle in a drawing the page embeds has the
label, or a code block on the page shows a subject starting `k: `. An
italic that starts with a capital, *X*, is a variable, and a word,
*mount*, a term; neither is checked. Code and hidden blocks
(`<!--` … `-->`) name nothing. `just docs-check` runs it over the
README and `docs/`.

### Drawings next to their checks

```sh
check-drawing/check-drawing placement <page>...
```

checks that every drawing a `check_drawing` call on the pages checks is
shown at least once where it shows the current state: an image of it
next to a block that checks it, hidden or not, with only prose between.
Any other code block, hidden or not, may change the state, so it counts
as one that does. An image in a hidden block (`<!--` … `-->`) fails: no reader
sees it, so show it or delete it. `just docs-check` runs it over the README and `docs/`.

## Requirements

- Git, and `just build` run in this checkout: it builds the checker, the
  Rust tool in `src/`, into `target/debug`

The script `check-drawing` runs that tool. What it reads about a splice, its
boundary, rebuild and keys, and the folders it had before it moved, comes from
`git-splice`'s own code, so a drawing is checked against what the tool really
does.

## The drawing's vocabulary

- **Commit**: a circle (ellipse). Its label is the commit's subject,
  or the subject's start before `: `, looked up on the monorepo's first-parent history, then upstream. A
  label with a trailing `'` (*b'* for *b*) is the rebuild's copy of the
  commit without it, and a copy of a drawn commit is labelled so: the same message, author and dates, in R's history
  or on a fetched upstream branch, where a push put it. Where several
  copies look alike, e.g. a pushed *b'* and R's *c'* after `git rebase`
  copied *b* to *c*, give the copy in full: `b'=<rev>`.
- **Parent arrow**: an arrow between two commits points from a parent to
  its child.
- **Message arrow**: an arrow styled `message=1` points from a commit to
  one its message names by hash, e.g. the `git-subtree-mainline:` line
  of a `git subtree split --rejoin`.
- **Box**: points at the commit its label names: H, B, T or R, U(x),
  the commit *x*'s `.splice` records, where *x* is H, B or a drawn commit, or
  a branch by its name: in a box on a monorepo commit, the monorepo's,
  e.g. `main` or `origin/main`, otherwise the upstream's, as fetched,
  `tracked(<branch>)`, the upstream branch the splice tracks on that
  monorepo branch, as fetched, or `merge-base(R,T)`, the newest commit R
  and T have in common. Several
  names
  are joined by ` = `, e.g. `U(H) = U(B)`: each must name that commit.
- **Lane**: a shape labelled with a splice's folder, e.g. `vendor/a/`,
  holds that splice's upstream commits and boxes.
  - A monorepo with several splices needs one per splice it draws. With
    one splice, lanes are optional. Without splices, e.g. in a drawing
    of what `git subtree` makes, there are none: commits and their
    arrows are checked in the monorepo alone.
  - A shape belongs to the innermost lane it lies wholly inside. A nested
    splice's lane is drawn inside the lane of the splice above it.
  - What a lane shows stays in it: arrows between commits don't cross
    into another lane.
  - A box sits with the commit it points at: H and B outside every lane,
    all others, U(x) too, in the lane of the commit they name. With one
    splice, a box outside every lane is that splice's.
  - U(x) reads *x*'s `.splice` of the splice whose lane the box is in: in
    a nested drawing, U(l) in the lane of `vendor/a/b/` reads the
    `b/.splice` of l, a commit of `vendor/a/`'s upstream.
- **Separator**: a dashed vertical line (draw.io's line shape,
  `direction=south`) splits a lane for a splice with several upstreams,
  side by side. A text on each side names the upstream whose commits
  that side holds, e.g. `origin` and `fork`: every side one upstream,
  each upstream one side. Outside a split lane, a text is read by its
  label, like any other shape.
  - A solid commit on a side is on a fetched branch of that side's
    upstream, and a box for a branch, e.g. `main`, names that upstream's
    branch.
  - A commit both upstreams have is drawn on each side, with one
    label: the two circles are one commit. Each side draws it once.
  - Arrows and boxes stay on their commit's side, as they stay in its
    lane.
- **Dashed**: commits and arrows into them that aren't in the upstream's
  history yet: no upstream branch has them, like R's copies of monorepo
  commits, or commits a rewrite of the upstream removed. A solid commit
  that T lacks needs a box for an upstream branch that has it.
  - A dashed box in a lane names a branch of the monorepo, not the
    upstream's, e.g. one checked out in a worktree of the rebuild. The
    commits it has that no upstream branch has belong to the lane, and
    are dashed. Only a branch's box can be dashed, and a box in a lane
    naming a branch only the monorepo has is dashed.

- **Legend**: a shape styled `legend=1`, with a sample commit inside
  for each mark the drawing's commits use, and the words for it next to
  it. Its shapes are no commits, boxes or texts of the drawing. It
  explains each color below the drawing uses, and no other. A dash and
  a trailing `'` are the
  [central legend's](../docs/10-contributing/02-writing.md#reading-the-drawings),
  which explains them for every drawing, so a `legend=1` doesn't. A
  legend styled `legend=full`, as in the README, explains them too.
- **Filled and outlined**: what the next rebuild does with a commit,
  in a drawing whose legend has a sample of the color.
  - Outlined orange, `#E07000`, if the legend has an orange sample: a
    change the rebuild carries across, on
    both ends: a walked commit R copies, and its copy, a commit with a
    trailing `'` in R's history since U(B). Every other commit is
    outlined black.
  - Filled grey, `#E0E0E0`, if the legend has a grey sample: a monorepo
    commit on the first-parent history since B, which the rebuild walks.
    Every other commit is white.
  - Without the color's sample, every commit is outlined black and white
    inside.
    In a drawing without splices, e.g. of what `git subtree` makes,
    neither is checked.

What a drawing shows is checked, not where: positions only matter for
which lane a shape is in.

## Saving drawings

Draw with [draw.io](https://www.drawio.com/) desktop, and save as an
uncompressed `.drawio.svg`: File > Properties > Compressed off. Labels
are plain text, not HTML, so viewers without HTML support in SVG show
them too. To export a `.drawio` file:

```sh
drawio -x -f svg -e -u --theme auto -b 10 -o x.drawio.svg x.drawio
```

`check-drawing` reads the diagram, and readers see the picture. An edit
of the diagram without exporting again would leave the two apart, so
[`check-export`](check-export) exports each drawing again from its
diagram, with draw.io, and compares the pictures:

```sh
just drawings-check          # fails on a stale picture
just drawings-check --write  # exports the stale ones again
```

It runs in `nix develop .#drawings`, which has a headless draw.io, and
in CI whenever a drawing changes. The documentation site serves each
drawing without its diagram, as a plain SVG:
[`drawings.js`](../website/src/drawings.js).

## Limits

`check-drawing` is as strict as the drawings it checks need it to be.
What no drawing has needed yet, it doesn't handle:

- **Notes**: free text is read by its label, as a box or a lane.
- **Branch names that read as names of the vocabulary**: an upstream
  branch called H, B, T, R or `U(…)`.
- **Several upstreams without a separator**: a lane that isn't split is
  checked against the splice's default upstream only.
- **Split lanes beyond the drawings here**: a split lane may leave out
  an upstream, or a shared commit's copy on one side; a label in two
  split lanes is read as one commit; and the splice needs a default
  upstream.
- **B with several splices**: outside every lane, B can't say which
  splice's boundary it is, so drawings with several splices leave it out.
- **Rewrites of shared history**: an upstream that shares commits with
  the monorepo and later drops one of them.
- **Old sync points**: a commit reachable only from an earlier `.splice`
  value is found by its label only when given as `<label>=<rev>`.

## Tests

In `git-splice`, [`docs/tests/drawing.bats`](../docs/tests/drawing.bats) and
[`docs/tests/drawing-lanes.bats`](../docs/tests/drawing-lanes.bats) and
[`docs/tests/drawing-upstreams.bats`](../docs/tests/drawing-upstreams.bats) and
[`docs/tests/drawing-tracked.bats`](../docs/tests/drawing-tracked.bats) and
[`docs/tests/drawing-local-branch.bats`](../docs/tests/drawing-local-branch.bats) run it against
`git-splice`'s test scenarios, and each [scenario](../docs/09-scenarios/)
with a drawing checks it in its README. [`docs/tests/drawing-export.bats`](../docs/tests/drawing-export.bats)
tests `check-export`, with draw.io.
