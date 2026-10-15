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
ok   after-pull.drawio.svg: 12 commits, 17 arrows, 6 boxes, 2 frames, 1 lanes
```

Otherwise it prints each difference, with what to change, and fails:

```
!!   R points at d', the code says e'
!!   b' is solid, but no upstream branch has it: dash it
```

A circle's label is the commit's subject. A commit whose subject makes
a poor label, like `add vendor/a`, gets a short one, given as
`<label>=<rev>`, a revision of the monorepo: `a=HEAD~3`.

Drawings for readers who don't know the sync model yet can use other
names, given as `--alias <name>=<term>`, before the labels. With Git's
names for a three-way merge:

```sh
check-drawing/check-drawing before-pull-git-names.drawio.svg \
  --alias HEAD=H --alias BOUNDARY=B --alias OURS=R --alias THEIRS=T \
  --alias 'BASE=merge-base(R,T)' a=HEAD~3
```

An alias works inside `U(…)` too: `U(BOUNDARY)` is U(B). Without
`--alias`, a name like `OURS` is an upstream branch.

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
  looked up on the monorepo's first-parent history, then upstream. A
  label with a trailing `'` (*b'* for *b*) is the rebuild's copy of the
  commit without it: the same message, author and dates, in R's history.
- **Parent arrow**: an arrow between two commits points from a parent to
  its child.
- **Box**: points at the commit its label names: H, B, T or R, U(x),
  the commit x's `.splice` records, where x is H, B or a drawn commit, or
  an upstream branch by its name, e.g. `main`, as fetched, or
  `merge-base(R,T)`, the newest commit R and T have in common. Several
  names
  are joined by ` = `, e.g. `U(H) = U(B)`: each must name that commit.
- **Lane**: a shape labelled with a splice's folder, e.g. `vendor/a/`,
  holds that splice's upstream commits and boxes.
  - A monorepo with several splices needs one per splice it draws. With
    one splice, lanes are optional, and the generic `path/` names it.
  - A shape belongs to the innermost lane it lies wholly inside. A nested
    splice's lane is drawn inside the lane of the splice above it.
  - What a lane shows stays in it: arrows between commits don't cross
    into another lane.
  - A box sits on the side of what it names: H and B outside every lane,
    T, R and upstream branches in their splice's lane. U(x) bridges the
    two: it sits next to x, or in the lane of the commit it names. With
    one splice, a box outside every lane is that splice's; with several,
    a frame around x says whose U(x) it is.
- **Frame**: labelled `x:<path>/.splice`, Git's name for that file in
  commit x, holds commit x, and usually the box U(x). `<path>` is the
  splice's folder in x's repository: in the monorepo, or in the upstream
  of the lane x is in. The generic `path` stands for the splice of the
  lane the frame is in.
- **Dashed**: commits and arrows into them that aren't in the upstream's
  history yet: no upstream branch has them, like R's copies of monorepo
  commits, or commits a rewrite of the upstream removed. A solid commit
  that T lacks needs a box for an upstream branch that has it.

What a drawing shows is checked, not where: positions only matter for
which lane or frame a shape is in.

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
  branch called H, B, T, R, `U(…)` or `path/`.
- **Several upstreams**: only a splice's default upstream is checked.
- **B with several splices**: outside every lane, B can't say which
  splice's boundary it is, so drawings with several splices leave it out.
- **Rewrites of shared history**: an upstream that shares commits with
  the monorepo and later drops one of them.
- **Old sync points**: a commit reachable only from an earlier `.splice`
  value is found by its label only when given as `<label>=<rev>`.
- **Moved splices**: a frame names the splice's current folder, not the
  one a commit from before the move had.

## Tests

In `git-splice`, [`test/drawing.bats`](../test/drawing.bats) and
[`test/drawing-lanes.bats`](../test/drawing-lanes.bats) run it against
`git-splice`'s test scenarios, and each [scenario](../test/scenarios/)
with a drawing checks it in its README.
