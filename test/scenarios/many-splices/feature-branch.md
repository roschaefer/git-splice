# Status on a feature branch

On a feature branch, every splice syncs with the upstream branch of the
same name. Most upstreams don't have it, so the comparison is with their
default branch, as for a PR. Where that has every commit already, the
splice shows as unchanged, last. The others come first, and `push` would
create their branch upstream: `cli`, which changed on `feature`, and
`parser` and `store`, whose commits on `main` upstream doesn't have yet.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_many_splices
```

```scrut
$ git checkout -q -b feature
```

```scrut
$ echo "feature work" >> libs/cli/file.txt
```

```scrut
$ git commit -q -am "feature work"
```

```scrut
$ git splice status
On branch feature

  new, ahead 1                   libs/cli     push creates the branch
  new, ahead 1                   libs/parser  push creates the branch
  new, ahead 1, behind 1         libs/store   push creates the branch

  unchanged, no upstream branch  libs/http
  unchanged, no upstream branch  libs/theme
```

After the push, the upstream has the branch, and `cli` is up to date with
it:

```scrut
$ git splice push libs/cli
??   libs/cli: upstream has no 'feature' branch yet -- this push creates it
ok   libs/cli: pushed 4dd9993 to feature
```

```scrut
$ git splice status
On branch feature

  new, ahead 1                   libs/parser  push creates the branch
  new, ahead 1, behind 1         libs/store   push creates the branch

  up to date                     libs/cli
  unchanged, no upstream branch  libs/http
  unchanged, no upstream branch  libs/theme
```
