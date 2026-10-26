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
`git-splice`'s [sync model](../test/concepts/sync-model/README.md),
H, B, T, R and U(x).

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

## Requirements

- Bash, Git, awk and [xmlstarlet](https://xmlstar.sourceforge.net/)
- `git-splice` on `PATH`

From `git-splice`, it uses the commands `boundary`, `rebuild` and `key`,
and two functions of its `lib/common.sh`: the list of splices,
`state_files`, and the upstream branch a monorepo branch maps to,
`upstream_branch_for`. It finds `lib/` next to the `git-splice` on
`PATH`, as in a checkout of `git-splice`, or in `share/git-splice/`
beside it, as installed; `$GIT_SPLICE_LIB` overrides both.

## The drawing's vocabulary

- **Commit**: a circle (ellipse). Its label is the commit's subject,
  or the subject's start before `: `, looked up on the monorepo's first-parent history, then upstream. A
  label with a trailing `'` (*b'* for *b*) is the rebuild's copy of the
  commit without it: the same message, author and dates, in R's history
  or on a fetched upstream branch, where a push put it.
- **Parent arrow**: an arrow between two commits points from a parent to
  its child.
- **Box**: points at the commit its label names: H, B, T or R, U(x),
  the commit *x*'s `.splice` records, where *x* is H, B or a drawn commit, or
  a branch by its name: in a box on a monorepo commit, the monorepo's,
  e.g. `main` or `origin/main`, otherwise the upstream's, as fetched, or
  `merge-base(R,T)`, the newest commit R and T have in common. Several
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
- **Moved splices**: U(x) reads *x*'s `.splice` under the splice's current
  folder, so a commit from before the splice moved has none there.

## Tests

In `git-splice`, [`test/drawing.bats`](../test/drawing.bats) and
[`test/drawing-lanes.bats`](../test/drawing-lanes.bats) and
[`test/drawing-upstreams.bats`](../test/drawing-upstreams.bats) run it against
`git-splice`'s test scenarios, and each [scenario](../test/scenarios/)
with a drawing checks it in its README.
