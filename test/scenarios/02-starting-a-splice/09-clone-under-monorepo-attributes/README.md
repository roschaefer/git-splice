# Scenario: clone-under-monorepo-attributes

A plain `git splice clone` into a monorepo whose `.gitattributes` sets
line endings the upstream doesn't, next to `git subtree add` of the same
upstream. In upstream, only its own `.gitattributes` apply to its files.
`clone` refuses where the monorepo's would apply too, as
[clone --from-submodule](../08-clone-from-submodule/04-monorepo-line-endings/README.md)
does, and names the line that keeps them off; `git subtree` applies
them.

- **Monorepo, on `main`**: `.gitattributes` wants `.bat` files with
  CRLF.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `build.bat` committed with CRLF, `run.bat` with LF, and no
  `.gitattributes`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_clone_under_monorepo_attributes
```

```scrut
$ cat .gitattributes
*.bat text eol=crlf
```

The root's attributes would apply to the splice's files, so `clone`
refuses:

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
!!   vendor/a: attributes in .gitattributes or above it would change how Git checks out or stores some of its files, unlike in upstream -- add 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' to .gitattributes, commit it, and run clone again
[1]
```

With the line it names committed, the clone goes through:

```scrut
$ echo 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' >>.gitattributes && git commit -q -m "keep the monorepo's line endings off vendor/a" .gitattributes
```

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned 1c04918 from main
```

`build.bat`, committed with CRLF, doesn't show as changed, as Git would
otherwise store it with LF:

```scrut
$ git status --short
```

and `run.bat` is checked out with LF, as upstream has it:

```scrut
$ cat -A vendor/a/run.bat
echo run$
```

`git subtree add` reads the upstream's files into the monorepo just as
`clone` does, but applies the root's attributes: in another clone of
the monorepo, at the commit before the line,

```scrut
$ cd .. && git clone -q -c user.name=Test -c user.email=test@example.com monorepo other && cd other && git reset -q --hard HEAD~2
```

`build.bat` shows as changed right away:

```scrut
$ git subtree add -q --prefix=vendor/a https://git.example.com/a.git main >/dev/null 2>&1 && git status --short
 M vendor/a/build.bat
```

and `run.bat` is checked out with CRLF (`^M`):

```scrut
$ cat -A vendor/a/run.bat
echo run^M$
```
