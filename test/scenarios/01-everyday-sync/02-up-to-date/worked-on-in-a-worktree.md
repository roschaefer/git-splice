# Scenario: up-to-date, worked on in a worktree of the rebuild

`git splice rebuild vendor/a` prints the splice's history as its upstream
would have it: a commit of the upstream's repository, with the folder's
files at its root. Checked out in a worktree of the monorepo, it's that
repository, to work in as if it were a clone: build it on its own, or run
`git-splice` there for a splice inside it.

`git splice merge --rebuilt-commit` brings what was committed there back
into `vendor/a/`. It's a three-way merge from where the commit left the
rebuild, so the monorepo's own changes since then stay. The synced commit
doesn't move: the commit is local work, and the next push sends it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_up_to_date
```

The rebuild, checked out on a branch of its own:

```scrut
$ git worktree add -q -b work-on-a ../a-work "$(git splice rebuild vendor/a)"
```

```scrut
$ ls ../a-work
file.txt
```

A commit there:

```scrut
$ echo "from the worktree" >../a-work/other.txt &&
>   git -C ../a-work add other.txt &&
>   git -C ../a-work commit -q -m "add other.txt"
```

Meanwhile, the monorepo changes `vendor/a/` too:

```scrut
$ echo "monorepo change" >>vendor/a/file.txt &&
>   git commit -q -am "monorepo change"
```

## Back into the monorepo

```scrut
$ git splice merge --rebuilt-commit work-on-a vendor/a
ok   vendor/a: merged d55cb3f
```

One commit, with the worktree commit's message, and both changes:

```scrut
$ git log --format=%s -3
add other.txt
monorepo change
add vendor/a
```

```scrut
$ cat vendor/a/other.txt vendor/a/file.txt
from the worktree
seed
monorepo change
```

`.splice` still names `seed`, so both changes are ahead, and the push
sends them:

```scrut
$ git log -1 --format=%s "$(git config --file vendor/a/.splice splice.commit)"
seed
```

```scrut
$ git splice status
On branch main

  ahead 2  vendor/a
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 895449a to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
add other.txt
monorepo change
seed
```

## Nothing to merge

A commit in the worktree that changes no files, here the same commit
reworded, has nothing to bring back:

```scrut
$ git -C ../a-work commit -q --amend -m "add other.txt, reworded"
```

```scrut
$ git splice merge --rebuilt-commit work-on-a vendor/a
ok   vendor/a: a5e4a9e's changes are in the folder already -- nothing to merge
```

No commit, and no cherry-pick left in progress:

```scrut
$ git log --format=%s -1
add other.txt
```

```scrut
$ git status --short
```
