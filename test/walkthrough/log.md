# log

`git splice log [--upstream <name>] [--graph] [path…]`

Shows the commits `push` would publish, marked `<`, and `pull` would
bring in, marked `>`, with their authors. Like `status`, it uses what
was fetched last.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

In the [sandbox](README.md), the monorepo changes `vendor/pkg-a`, and so
does its upstream:

```scrut
$ echo "a local fix" >>vendor/pkg-a/local.txt && git add vendor/pkg-a && git commit -qm "pkg-a: a local fix"
```

```scrut
$ git splice log
===  vendor/pkg-a (main)
< 9cdfdbb pkg-a: a local fix  (Walkthrough <walkthrough@example.com>)
> 703b936 pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
```

`--graph` draws both sides as a graph, down to the commit they build on,
`o`, and labels T, the fetched upstream branch, and R, the rebuild
`push` would send ([B, U, T and R](status.md#b-u-t-and-r)):

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
< 9cdfdbb (R) pkg-a: a local fix  (Walkthrough <walkthrough@example.com>)
| > 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
|/  
o 9bb866a pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```
