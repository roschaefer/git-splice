# Scenario: clone-from-submodule, under the monorepo's line endings

Git applies a repository's `.gitattributes` to its own files, never to a
submodule's. Once the submodule is a folder, the monorepo's attributes
would apply to its files too. Where they would change a checkout --
`text` and `eol` for line endings, as here, `filter`, `ident` and
`working-tree-encoding` -- the conversion refuses, and names the line
that unsets them for the folder. With that line committed, it converts.

- **Monorepo, on `main`**: `.gitattributes` wants `.bat` files with
  CRLF. `vendor/a/` is a submodule of the upstream, checked out at
  `add run.bat`.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `seed`, `newer`, then `build.bat` committed with CRLF and `run.bat`
  with LF.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_monorepo_line_endings https://git.example.com/a.git
```

```scrut
$ cat .gitattributes
*.bat text eol=crlf
```

The submodule is a repository of its own, and none of its attributes
are set:

```scrut
$ git -C vendor/a check-attr text eol -- build.bat run.bat
build.bat: text: unspecified
build.bat: eol: unspecified
run.bat: text: unspecified
run.bat: eol: unspecified
```

In the monorepo, the root's would apply. The conversion refuses, and
nothing changes:

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
!!   vendor/a: attributes in .gitattributes or above it would change how Git checks out or stores some of its files, unlike in upstream -- add 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' to .gitattributes, commit it, and run clone again
[1]
```

The line it names unsets them, and the other attributes that change a
checkout, for the folder again. Commit it:

```scrut
$ echo 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' >>.gitattributes && git commit -q -m "keep the monorepo's line endings off vendor/a" .gitattributes
```

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned f758343 from the submodule
===  vendor/a: pinned at f758343, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

```scrut
$ git check-attr text eol -- vendor/a/build.bat
vendor/a/build.bat: text: unspecified
vendor/a/build.bat: eol: unspecified
```

Nothing shows as changed:

```scrut
$ git status --short
```

## Attributes added later

The line wins over the lines before it in the same file. A rule added
after it applies to the splice again, a known gap ([#311](https://github.com/roschaefer/git-splice/issues/311)):

```scrut
$ printf '*.txt text eol=crlf\n' >>.gitattributes && git check-attr eol -- vendor/a/file.txt
vendor/a/file.txt: eol: crlf
```

So does one in a `.gitattributes` deeper than the line's, between the
root and the splice:

```scrut
$ git checkout -q -- .gitattributes && printf '*.txt text eol=crlf\n' >vendor/.gitattributes && git check-attr eol -- vendor/a/file.txt
vendor/a/file.txt: eol: crlf
```

```scrut
$ rm vendor/.gitattributes
```

## Without the line

With the `.gitattributes` from before the line, Git stores `build.bat`
with LF the next time it's added, and the next push would send that
change to the upstream:

```scrut
$ git checkout -q HEAD~2 -- .gitattributes && git add --renormalize vendor/a && git status --short
M  .gitattributes
M  vendor/a/build.bat
```

And a checkout would give `run.bat`, which the submodule had with LF,
CRLF instead (`^M`):

```scrut
$ rm vendor/a/run.bat && git checkout -- vendor/a/run.bat && cat -A vendor/a/run.bat
echo run^M$
```
