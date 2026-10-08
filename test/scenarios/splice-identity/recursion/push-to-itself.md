# Scenario: splice-identity/recursion: push to itself

`vendor/a/i` is a splice of the monorepo's own upstream. So its push
sends a copy of the monorepo, from when a's upstream last pulled it, to
the monorepo's `main`. If nobody pushed the monorepo since, that's a
fast-forward, and the push succeeds.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_recursion
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved bde4164..2073178)
ok   vendor/a: pulled 2073178
```

A change in the copy:

```scrut
$ echo "note" >vendor/a/i/note.txt && git add vendor/a/i/note.txt && git commit -q -m "note in i"
```

```scrut
$ git splice push vendor/a/i
??   vendor/a/i: upstream has no 'main' branch yet -- this push creates it
ok   vendor/a/i: pushed 38027ee to main
```

The warning is wrong: the upstream has a `main`. `vendor/a/i` was never
fetched, since the pull read which splices there are before it existed.
`status` would say so, but `push` takes the missing refs for a missing
branch, as `status` does after `init` in
[#11](https://github.com/roschaefer/git-splice/issues/11).

The monorepo's upstream now has the copy as `main`, which is neither
the monorepo's history nor its tree:

```scrut
$ git -C "$UPSTREAM-m" log --format=%s main
note in i
add vendor/a
initial commit
```

```scrut
$ git -C "$UPSTREAM-m" ls-tree --name-only main
note.txt
vendor
```

```scrut
$ git ls-tree --name-only HEAD
vendor
```

The next `git push` of the monorepo is rejected, as the upstream's `main`
isn't an ancestor of the monorepo's any more:

```scrut
$ git push -q https://git.example.com/m.git main
To $UPSTREAM-m
 ! [rejected]        main -> main (non-fast-forward)
error: failed to push some refs to '$UPSTREAM-m'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. If you want to integrate the remote changes,
hint: use 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
[1]
```
