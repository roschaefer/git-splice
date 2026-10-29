# Scenario: clone-under-monorepo-attributes

A plain `git splice clone` into a monorepo whose `.gitattributes` sets
line endings the upstream doesn't, next to `git subtree add` of the same
upstream. Unlike [clone --from-submodule](../08-clone-from-submodule/04-monorepo-line-endings/README.md),
`clone` doesn't keep the monorepo's attributes off the splice yet, and
neither does `git subtree`.

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
ok   vendor/a: cloned [0-9a-f]{7} from main (regex)
```

The root's attributes apply to the splice's files. `build.bat` shows as
changed right away, as Git would store it with LF:

```scrut
$ git status --short
 M vendor/a/build.bat
```

and `run.bat`, LF upstream, is checked out with CRLF (`^M`):

```scrut
$ cat -A vendor/a/run.bat
echo run^M$
```

`git subtree add` gives the same result: it reads the upstream's files
into the monorepo just as `clone` does, and Git applies the same
attributes. It refuses to start in a worktree with changes, so this
runs in another clone of the monorepo, at the commit before the splice:

```scrut
$ cd .. && git clone -q -c user.name=Test -c user.email=test@example.com monorepo other && cd other && git reset -q --hard HEAD^
```

```scrut
$ git subtree add -q --prefix=vendor/a https://git.example.com/a.git main >/dev/null 2>&1 && git status --short
 M vendor/a/build.bat
```

```scrut
$ cat -A vendor/a/run.bat
echo run^M$
```
