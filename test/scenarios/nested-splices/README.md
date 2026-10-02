# Scenario: nested-splices

A splice whose upstream uses git splice itself, so it brings a `.splice`
of its own one level down.

- **Upstream**: `file.txt`, and `extra/.splice`: its folder `extra/` is
  one of its own splices.
- **Monorepo (`vendor/pkg`)**: cloned from it, so it has
  `vendor/pkg/.splice` and `vendor/pkg/extra/.splice`.

Only the outermost `.splice` makes a splice. The inner one is content of
`vendor/pkg`, like any other file: the push rebuild only leaves out the
`.splice` at the splice's root, so the upstream's own `.splice` travels
both ways unchanged. A splice inside another one, or around one, can't be
created: only the outer one would count, and
`refs/splices/vendor/pkg/extra/main` could name either the branch
`extra/main` of `vendor/pkg` or the branch `main` of `vendor/pkg/extra`.

## Output

`scenario_nested_splices` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_nested_splices
```
-->

```scrut
$ git ls-files vendor/pkg
vendor/pkg/.splice
vendor/pkg/extra/.splice
vendor/pkg/file.txt
```

```scrut
$ git splice status
ok   vendor/pkg -> main (up to date)
```

```scrut
$ git splice clone "$UPSTREAM" vendor/pkg/extra
!!   nested splices are not supported: 'vendor/pkg/extra' and 'vendor/pkg' overlap
[1]
```

A local change pushed upstream keeps the upstream's own `.splice`:

```scrut
$ echo "local change" >>vendor/pkg/file.txt && git commit -qam "local change" && git splice push vendor/pkg
ok   vendor/pkg: pushed 92d46d9 to main
```

```scrut
$ git -C "$UPSTREAM" ls-tree -r --name-only main
extra/.splice
file.txt
```
