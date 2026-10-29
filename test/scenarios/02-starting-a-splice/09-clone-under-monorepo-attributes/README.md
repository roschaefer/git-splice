# Scenario: clone-under-monorepo-attributes

A plain `git splice clone` into a monorepo whose `.gitattributes` sets
line endings the upstream doesn't, next to `git subtree add` of the same
upstream. In upstream, only its own `.gitattributes` apply to its files.
`clone` keeps it that way, as [clone --from-submodule](../08-clone-from-submodule/04-monorepo-line-endings/README.md)
does; `git subtree` doesn't.

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

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
===  vendor/a: unset text eol filter ident working-tree-encoding for it in .gitattributes -- in upstream, only its own .gitattributes apply to its files
ok   vendor/a: cloned [0-9a-f]{7} from main (regex)
```

The clone added a line to `.gitattributes` that unsets the root's
attributes for the splice, in its own commit:

```scrut
$ git show --stat --format=%s
splice: clone vendor/a from main at [0-9a-f]{7} (regex)

 .gitattributes     | 1 +
 vendor/a/.splice   | 5 +++++
 vendor/a/build.bat | 1 +
 vendor/a/file.txt  | 1 +
 vendor/a/run.bat   | 1 +
 5 files changed, 9 insertions(+)
```

```scrut
$ cat .gitattributes
*.bat text eol=crlf
vendor/a/** !text !eol !filter !ident !working-tree-encoding
```

So `build.bat`, committed with CRLF, doesn't show as changed, as Git
would otherwise store it with LF:

```scrut
$ git status --short
```

and `run.bat` is checked out with LF, as upstream has it:

```scrut
$ cat -A vendor/a/run.bat
echo run$
```

`git subtree add` reads the upstream's files into the monorepo just as
`clone` does, but leaves the root's attributes on: in another clone of
the monorepo, at the commit before the splice,

```scrut
$ cd .. && git clone -q -c user.name=Test -c user.email=test@example.com monorepo other && cd other && git reset -q --hard HEAD^
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
