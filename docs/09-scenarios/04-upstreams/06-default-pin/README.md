# Scenario: default-pin

The monorepo's default branch pins a release of the library, the tag
`v1`, instead of following a branch.

- **Monorepo (`vendor/a/`)**: cloned `v1`, and `.splice` names the tag
  as the upstream's `default-pin`.
- **Upstream**: `v1` on `main`, tagged `v1`, then `v2`, tagged `v2`.

`default-pin` names a tag or a complete commit id, and replaces
`default-branch`: an upstream has one or the other. Both stay where they
are, so the splice stays too: `pull` brings in nothing new until
`.splice` names another one, and `push` refuses on the default branch,
since nobody pushes to a tag. Feature branches are as always: they sync
with the upstream branch of the same name, and `push` creates it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_default_pin
```

```scrut
$ git config --file vendor/a/.splice upstream.origin.default-pin
v1
```

`fetch` fetches the tag `default-pin` names, into
`refs/splices/<key>/tags/`, next to the branches:

```scrut
$ git splice fetch
ok   vendor/a fetched
```

```scrut
$ git for-each-ref --format='%(refname)' refs/splices/
refs/splices/upstream/heads/main
refs/splices/upstream/tags/v1
```

`main` moved on to `v2`, but the splice stays with `v1`:

```scrut
$ git splice status
On branch main

  up to date  vendor/a -> tags/v1
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: nothing to pull
```

## A local change

A fix in the monorepo shows as ahead of the tag:

```scrut
$ echo "a fix for v1" >vendor/a/fix.txt &&
>   git add vendor/a/fix.txt &&
>   git commit -q -m "vendor/a: a fix for v1"
```

```scrut
$ git splice status
On branch main

  ahead 1  vendor/a -> tags/v1
```

`push` refuses on the default branch. On a feature branch, it pushes
the fix as a new upstream branch, for a pull request:

```scrut
$ git splice push vendor/a
!!   vendor/a: pinned at the tag 'v1' -- a tag isn't pushed to: push from a feature branch, or follow a branch again: git config --file vendor/a/.splice --unset upstream.origin.default-pin
!!   Failed: vendor/a
[1]
```

```scrut
$ git switch -q -c fix-for-v1 && git splice push vendor/a
??   vendor/a: upstream has no 'fix-for-v1' branch yet -- this push creates it
ok   vendor/a: pushed ede30c3 to fix-for-v1
```

```scrut
$ git switch -q main
```

## Upgrading

To take `v2`, name it in `.splice` and pull. The upgrade shows in
`.splice`, like a submodule bump:

```scrut
$ git config --file vendor/a/.splice upstream.origin.default-pin v2 &&
>   git commit -q -m "vendor/a: upgrade to v2" -- vendor/a/.splice
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled fefc564
```

```scrut
$ cat vendor/a/file.txt vendor/a/fix.txt
v1
v2
a fix for v1
```

```scrut
$ git splice status
On branch main

  ahead 2  vendor/a -> tags/v2
```

The fix is still ahead: it and the pull that joined it with `v2` are
what a push from a feature branch would send.

## A commit

A commit id pins one commit, whether or not a branch or tag has it.
`fetch` fetches it by id:

```scrut
$ v2="$(git rev-parse refs/splices/upstream/tags/v2^{commit})" &&
>   git config --file vendor/a/.splice upstream.origin.default-pin "$v2" &&
>   git commit -q -m "vendor/a: pin the commit of v2" -- vendor/a/.splice
```

```scrut
$ git splice status
On branch main

  ahead 2  vendor/a -> fefc564
```
