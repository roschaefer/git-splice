# Scenario: clone-from-submodule, under the monorepo's line endings

> **Known bug, [#311](https://github.com/roschaefer/git-splice/issues/311).** This page shows what `git-splice` does today, bug included. See [known bugs and limitations](../../../99-known-bugs.md#known-bugs).

Git applies a repository's `.gitattributes` to its own files, never to a
submodule's. Once the submodule is a folder, the monorepo's attributes
would apply to its files too. Where they would change a checkout --
`text` and `eol` for line endings, as here, `filter`, `ident`,
`working-tree-encoding` and Git's older `crlf` -- the conversion refuses, and names the line
that unsets them for the folder. With that line committed, it converts.
A rule added after the line applies to the folder again, and a push
then stores line endings the upstream doesn't have.

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
!!   vendor/a: attributes in .gitattributes or above it would change how Git checks out or stores some of its files, unlike in upstream -- add 'vendor/a/** !text !eol !filter !ident !working-tree-encoding !crlf' to .gitattributes, commit it, and run clone again
[1]
```

The line it names unsets them, and the other attributes that change a
checkout, for the folder again. Commit it:

```scrut
$ echo 'vendor/a/** !text !eol !filter !ident !working-tree-encoding !crlf' >>.gitattributes && git commit -q -m "keep the monorepo's line endings off vendor/a" .gitattributes
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

Back to the line:

```scrut
$ git reset -q --hard
```

## Attributes added later

The line wins over the lines before it in the same file. A rule
appended after it applies to the splice's files again, a known bug
([#311](https://github.com/roschaefer/git-splice/issues/311)). So does
one in a `.gitattributes` deeper than the line's, between the root and
the splice:

```scrut
$ printf '*.bat text eol=crlf\n' >vendor/.gitattributes && git check-attr text eol -- vendor/a/build.bat
vendor/a/build.bat: text: set
vendor/a/build.bat: eol: crlf
```

```scrut
$ rm vendor/.gitattributes
```

Here the rule from before the line comes back at the end, and is
committed:

```scrut
$ printf '*.bat text eol=crlf\n' >>.gitattributes && git commit -q -m "CRLF for .bat, again" .gitattributes
```

```scrut
$ git check-attr text eol -- vendor/a/build.bat
vendor/a/build.bat: text: set
vendor/a/build.bat: eol: crlf
```

No command runs at that moment. The upstream's checkout has `build.bat`
with CRLF (`^M`):

```scrut
$ git clone -q https://git.example.com/a.git ../a-dev && cat -A ../a-dev/build.bat
echo build^M$
```

A checkout in the monorepo now gives `run.bat`, which the upstream has
with LF, CRLF instead:

```scrut
$ rm vendor/a/run.bat && git checkout -- vendor/a/run.bat && cat -A vendor/a/run.bat
echo run^M$
```

To push, the splice follows `main` instead of the submodule's pin:

```scrut
$ git config --file vendor/a/.splice --unset upstream.origin.default-pin &&
>   git commit -q -m "vendor/a: follow main" vendor/a/.splice
```

A one-line change to `build.bat`, keeping its CRLF:

```scrut
$ printf 'echo test\r\n' >>vendor/a/build.bat && git commit -q -a -m "test in build.bat"
```

`status` shows nothing but the commit to push:

```scrut
$ git splice status
On branch main

  ahead 1  vendor/a
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 8f5490f to main
```

The upstream gets every line of `build.bat` changed, its CRLF stored as
LF:

```scrut
$ git -C ../a-dev pull -q && git -C ../a-dev diff --stat HEAD~
 build.bat | 3 ++-
 1 file changed, 2 insertions(+), 1 deletion(-)
```

```scrut
$ cat -A ../a-dev/build.bat
echo build$
echo test$
```
