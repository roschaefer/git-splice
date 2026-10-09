# Sync model

A splice's folder has two histories: the monorepo's, where it's a
folder, and its upstream's, where it's the whole repository. Commits
don't cross between them, changes do. Every command works out what to
cross from four commits:

| | Commit | Lives in |
|---|---|---|
| **B** | The boundary: the newest commit on the monorepo's first-parent history that changed `.splice`. | the monorepo |
| **U** | The synced commit: the upstream commit `.splice` records at B, the last one pulled. | the upstream |
| **T** | *Theirs*: the upstream branch as the monorepo last saw it, in `refs/splices/`. | the upstream |
| **R** | The rebuild, *ours*: the folder's history since B, rebuilt as upstream commits on top of U. | computed |

U and T may be missing: right after `init`, there's no U yet, and R
starts as a root commit; before the first fetch, there's no T, and the
splice is *never fetched*, or the upstream has *no such branch*.

The [walkthrough](../../walkthrough/README.md#b-u-t-and-r) shows the
Git commands that find each of them.

## R, the rebuild

The monorepo's commits that changed the folder are the splice's own
changes, but they have the monorepo's layout and the monorepo's history.
R copies each of them, since B, as an upstream commit: the folder's tree
without `.splice`, the same author, dates and message, on top of U.

R is never stored. It's computed from `HEAD` each time, and the same
`HEAD` always gives the same R. So a commit pushed once is rebuilt
identically, and the next push is a fast-forward. And since R is
computed, `.splice` needs no monorepo commit ids, which a rebase or a
squash merge would invalidate
([design](../../../docs/design/README.md#splicing-out-push-and-the-rebuild)).

## Three ways, both directions

R and T are two histories of the same folder, as upstream commits. How
they relate is the [sync state](../../../docs/sync-states.md):

| R and T | State | What crosses |
|---|---|---|
| the same files, or the same commit | up to date | nothing |
| T is an ancestor of R | push | `push` sends R, a fast-forward |
| R is an ancestor of T | pull | `pull` merges T in |
| neither, but with a common ancestor | diverged | `pull` merges T in, then `push` sends R |
| no common ancestor | unrelated history | nothing: `pull` and `push` refuse, and print the commands to keep either side, or both |

A pull is a **three-way merge**, in the monorepo's layout:

- **base**: the newest commit R and T have in common, `git merge-base R T`
- **ours**: `HEAD`, with the folder as it is
- **theirs**: `HEAD` with T's files in the folder

Git merges them as usual. Only the folder differs between base and
theirs, so only the folder can conflict. The result is one ordinary
monorepo commit, which records T as the new U, and is the new B.

The base is usually U. After a push, it's the pushed commit: R contains
it, so the merge doesn't replay changes the upstream already has. That's
also why U alone says little about where a splice stands. A push moves
T, and with it R's relation to T, but not U: a push never writes to the
monorepo.

## Output

The walkthrough's [sandbox](../../walkthrough/README.md), where
`vendor/pkg-a` is behind its upstream by one commit.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../walkthrough/scrut-setup.sh"
```
-->

`log --graph` draws R and T, labeled, down to the commit they have in
common, `o`. Nothing changed the folder since B, so R is U:

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
> 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
o 9bb866a (R) pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```

A change in the monorepo, to a file the upstream didn't change:

```scrut
$ echo "local" >vendor/pkg-a/local.txt && git add vendor/pkg-a/local.txt && git commit -q -m "pkg-a: a local file"
```

Now R has a commit T lacks, and the other way around:

```scrut
$ git splice status vendor/pkg-a
ok   vendor/pkg-a -> main (diverged: ahead 1, behind 1)
```

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
< f985b9f (R) pkg-a: a local file  (Walkthrough <walkthrough@example.com>)
| > 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
|/  
o 9bb866a pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```

The pull merges T in, with `o` as the base:

```scrut
$ git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: pulled 703b936
```

The pull commit is the new B. Its folder isn't T's tree, since it has the
local file too, so R joins the local commit with T by a merge, as
`git pull` would have:

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
<   6dc0e40 (R) splice: pull vendor/pkg-a from main at 703b936  (Walkthrough <walkthrough@example.com>)
|\  
< | f985b9f pkg-a: a local file  (Walkthrough <walkthrough@example.com>)
| o 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
|/  
o 9bb866a pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```

The push sends R, a fast-forward of T:

```scrut
$ git splice push vendor/pkg-a
ok   vendor/pkg-a: pushed 6dc0e40 to main
```

```scrut
$ git log --graph --format='%h %s' splices/pkg-a/main
*   6dc0e40 splice: pull vendor/pkg-a from main at 703b936
|\  
| * 703b936 pkg-a: a second commit, after the clone
* | f985b9f pkg-a: a local file
|/  
* 9bb866a pkg-a: seed
```

Now R and T are equal, and the splice is up to date. U is still the
commit the pull brought in. It lags behind T, since the push didn't
write to the monorepo:

```scrut
$ git splice status vendor/pkg-a
ok   vendor/pkg-a -> main (up to date)
```

```scrut
$ git config --file vendor/pkg-a/.splice splice.commit && git rev-parse splices/pkg-a/main
703b9360f7ac335a1134e9b5771a90a7c09ba39a
6dc0e40cd5eda556b7b18759d2e2bb1ae2ae214a
```
