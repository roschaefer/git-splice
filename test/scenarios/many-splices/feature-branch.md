# Status on a feature branch

On a feature branch, every splice syncs with the upstream branch of the
same name. Most upstreams don't have it, and most splices don't change on
it: they show as unchanged, last. The one that changed is first, and
`push` would create its branch upstream.

"Unchanged" and "new" compare with the base branch the header names: the
monorepo's default branch, or `--base`.

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
On branch feature (base: main)

  new, ahead 1                   libs/cli  push creates the branch

  unchanged, no upstream branch  libs/http
  unchanged, no upstream branch  libs/parser
  unchanged, no upstream branch  libs/store
  unchanged, no upstream branch  libs/theme
```

After the push, the upstream has the branch, and `cli` is up to date with
it:

```scrut
$ git splice push libs/cli
??   libs/cli: upstream has no 'feature' branch yet -- this push creates it (changed since 'main')
ok   libs/cli: pushed 4dd9993 to feature
```

```scrut
$ git splice status
On branch feature (base: main)

  up to date                     libs/cli
  unchanged, no upstream branch  libs/http
  unchanged, no upstream branch  libs/parser
  unchanged, no upstream branch  libs/store
  unchanged, no upstream branch  libs/theme
```
