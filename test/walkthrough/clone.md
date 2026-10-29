# clone

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice clone -h
NAME
    git-splice-clone - Splice an existing repository into the monorepo

SYNOPSIS
    git splice clone [--merge] [-m <message>] <url> [<path>]
    git splice clone --from-submodule [--recursive | -m <message>] <path>

DESCRIPTION
    Splices an existing upstream repository into <path> (default: the
    repository's name), as one ordinary commit with a new <path>/.splice.

    The upstream branch is the one named like the current branch, else the
    upstream's default branch; your first push then creates the missing
    branch. If the upstream's default branch is named differently from the
    monorepo's, .splice records it as the upstream's default-branch. Inside another splice,
    it's compared with that splice's default branch instead, and on the
    monorepo's default branch, that's the upstream branch: the monorepo's
    branch name isn't tried.

    If <path> already exists with exactly the upstream's content, clone only
    adds .splice. If its content differs, clone refuses, unless --merge is
    given: then every file that differs becomes a conflict to resolve, and
    nothing is lost. Resolve it and run 'git commit'.

    With --from-submodule, <path> is a submodule committed in HEAD, and clone
    turns it into a splice of the same upstream, at the same commit: the
    upstream is the submodule's URL in .gitmodules, and the folder gets the
    files of the commit the submodule points to. One commit replaces the
    submodule with the folder, and removes it from .gitmodules (the file too,
    once empty). Upstream must serve the commit, on a branch, a tag or by
    id, and a checkout of the submodule must be at that commit without
    changes; clone refuses otherwise. It asks git status for those changes,
    so it can't see the ones hidden by 'git update-index --assume-unchanged'
    or '--skip-worktree': an edited file keeps its edit, but a deleted one
    comes back. Clear these flags first. Files Git ignores in the checkout
    stay, and its repository stays in .git/modules/. Git never applied the
    monorepo's .gitattributes to the submodule's files: where text, eol,
    filter, ident or working-tree-encoding above the folder would change
    what a checkout writes, clone unsets these for the folder in the
    deepest .gitattributes above it.

    The splice keeps what the submodule followed. submodule.<name>.branch,
    the branch 'git submodule update --remote' follows, becomes the
    upstream's default-branch ("." needs none: a splice follows the branch
    named like the current one by default; inside a splice that pins a tag
    or a commit, it stays at its commit). Without it, the submodule stayed
    at its commit, and the upstream's default-pin pins that commit: on the
    monorepo's default branch, pull brings in nothing and push refuses until
    default-pin is removed. Other settings in .gitmodules are dropped.

    A submodule whose commit has submodules of its own is refused, unless
    --recursive is given: then clone converts those too, one commit each,
    top-down. Their URLs and settings come from the .gitmodules in the
    folder above, and a relative URL is relative to that folder's upstream.
    The upstream above still has the submodule, so the folder differs from
    it by that commit: the next push of the folder above sends it, which
    turns the submodule into a splice there too. Push it before that
    upstream moves its submodule to another commit: pulling such a change
    is refused. If a nested submodule is refused, the ones above stay
    converted; fix what the message says, then run clone on that path.

    -m gives the commit this message instead of the default one, which
    names the upstream branch and commit. Nothing reads the message back:
    .splice records them.
```
In the [walkthrough's repositories](README.md), `pkg-b.git` isn't spliced in yet:

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
$ cat vendor/pkg-b/.splice
[splice]
	id = 6c92e1a0e36b0b6d
	commit = 9b3cb02af44029fd61f1a57699c3dbf033958071
[upstream "origin"]
	url = https://git.example.com/pkg-b.git
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
===  vendor/pkg-b: pinned at 9b3cb02, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/pkg-b/.splice --unset upstream.origin.default-pin
===  vendor/pkg-b: the submodule's repository stays in $WALKTHROUGH/monorepo/.git/modules/vendor/pkg-b -- remove it once you don't need it
```

One commit replaces the submodule with its files and a `.splice`, and
removes it from `.gitmodules`, here the whole file:

```scrut
$ git show --stat --format=%s
splice: clone vendor/pkg-b from submodule at 9b3cb02

 .gitmodules           | 3 ---
 vendor/pkg-b          | 1 -
 vendor/pkg-b/.splice  | 6 ++++++
 vendor/pkg-b/file.txt | 1 +
 4 files changed, 7 insertions(+), 4 deletions(-)
```

The splice keeps what the submodule followed, its `branch` in
`.gitmodules`
([clone-from-submodule](../scenarios/02-starting-a-splice/08-clone-from-submodule/README.md)):

- **No `branch`**, as here: it stays at its commit, pinned with
  `default-pin`
  ([submodule-without-branch](../scenarios/02-starting-a-splice/08-clone-from-submodule/01-submodule-without-branch/README.md)).
- **`branch = <name>`**: it follows that branch, recorded as
  `default-branch`
  ([submodule-with-branch](../scenarios/02-starting-a-splice/08-clone-from-submodule/02-submodule-with-branch/README.md)).
- **`branch = .`**: it follows the branch named like the monorepo's, as
  every splice does without either setting
  ([submodule-with-branch-dot](../scenarios/02-starting-a-splice/08-clone-from-submodule/03-submodule-with-branch-dot/README.md)).

The upstream has to serve the commit, on a branch, a tag or by id, so
it's there for everyone after the switch. A checkout of the submodule
must be at it, without changes, or `clone` refuses. It finds those
changes with `git status`, which doesn't see the ones hidden by
`git update-index --assume-unchanged` or `--skip-worktree`: an edited
file keeps its edit, but a deleted one comes back. Clear these flags
before converting. Other settings in `.gitmodules` have no equivalent
and are dropped, with a warning. Other branches still have the
submodule; merging the converted main branch into them converts it there
too.

Every checkout that has the submodule's files, a colleague's clone or a
linked worktree, can't pull or merge the conversion: Git sees the files
as untracked ones in the way. `git submodule deinit -f vendor/pkg-b`
removes them first; it discards changes in the submodule's checkout, so
push them before.

> **Linked worktrees:** the conversion removes the submodule's settings,
> `submodule.<name>.*`, from `.git/config`, which all worktrees of the
> monorepo share. In another worktree that still has the submodule, it
> then counts as uninitialized
> ([submodule-in-linked-worktree](../scenarios/02-starting-a-splice/07-submodule-in-linked-worktree/README.md)).
> Git itself advises against several worktrees of a monorepo with
> submodules: their support "is incomplete"
> ([`git worktree`, BUGS](https://git-scm.com/docs/git-worktree#_bugs)).

## More

- If the folder already exists and differs, `clone` refuses. With
  `--merge`, every file that differs becomes a conflict to resolve, and
  nothing is lost
  ([clone-differing-content](../scenarios/02-starting-a-splice/02-clone-differing-content/README.md)).
  If the folder already has exactly the upstream's files, `clone` only
  adds `.splice` ([clone-copied-content](../scenarios/02-starting-a-splice/01-clone-copied-content/README.md)).
- On a branch the upstream doesn't have, `clone` takes the upstream's
  default branch. The first push creates the branch upstream, if the
  splice changed by then
  ([clone-on-feature-branch](../scenarios/02-starting-a-splice/03-clone-on-feature-branch/README.md)).
- A clone is a commit on top of `HEAD`, so a monorepo without commits
  needs a first one
  ([clone-without-commits](../scenarios/02-starting-a-splice/06-clone-without-commits/README.md)).
- An upstream with a submodule is refused, by `clone` and later by
  `merge` and `pull`: its `.gitmodules` would sit in the folder, where Git
  doesn't read it, so nobody could check the submodule out. Turn it into a
  splice in the upstream first.
- `clone --from-submodule --recursive` converts a submodule's own
  submodules too, one commit each. Its upstream still has them, so the
  next push of the folder sends that commit: it turns them into splices
  upstream too. Until then, `pull` brings in the upstream's other changes,
  but refuses one that moves such a submodule to another commit. If that
  upstream's owners keep their submodules, convert it in a fork of yours
  instead ([#153](https://github.com/roschaefer/git-splice/issues/153)).
- To publish a folder of the monorepo to a new, empty repository, use
  [`init`](init.md).
