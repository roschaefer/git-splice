# Scenario: clone-from-submodule, with a macro in upstream's attributes

> **Known bug, [#311](https://github.com/roschaefer/git-splice/issues/311).** This page shows what `git-splice` does today, bug included. See [known bugs and limitations](../../../99-known-bugs.md#known-bugs).

Upstream's own `.gitattributes` defines a macro. Git accepts macro
definitions only in the top-level `.gitattributes`, which upstream's is
in its own repository and in a submodule, but not in a splice's folder.
A converted submodule and a plain `clone` alike would lose the macro's
attributes, and no line above the folder can bring them back: both
refuse. A copy of the definition in the monorepo's root
`.gitattributes` brings them back, and upstream's own file stays as it
is. A macro that a later pull brings in isn't checked: its files are
checked out and stored as upstream's attributes wouldn't have them.

- **Monorepo, on `main`**: no `.gitattributes`. `vendor/a/` is a
  submodule of the upstream, checked out at `add run.bat`.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  a `.gitattributes` that defines `crlf-text` and gives it to `.bat`
  files, and `run.bat` committed with LF.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_upstream_macro https://git.example.com/a.git
```

```scrut
$ cat vendor/a/.gitattributes
[attr]crlf-text text eol=crlf
*.bat crlf-text
```

In the submodule, a repository of its own, the macro applies, and
`run.bat` is checked out with CRLF (`^M`):

```scrut
$ git -C vendor/a check-attr text eol -- run.bat && cat -A vendor/a/run.bat
run.bat: text: set
run.bat: eol: crlf
echo run^M$
```

Asked from the top of the monorepo, as checkout and `git add` ask once
`vendor/a` is a folder, Git rejects the definition, and the attributes
are gone:

```scrut
$ git check-attr text eol -- vendor/a/run.bat
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1
vendor/a/run.bat: text: unspecified
vendor/a/run.bat: eol: unspecified
```

So the conversion refuses, and says why:

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
!!   vendor/a: upstream's .gitattributes defines macros, which Git reads only in a repository's top-level .gitattributes, not in vendor/a/
[1]
```

And so does a plain `clone` of the same upstream:

```scrut
$ git splice clone https://git.example.com/a.git vendor/b
===  vendor/b: fetching https://git.example.com/a.git
!!   vendor/b: upstream's .gitattributes defines macros, which Git reads only in a repository's top-level .gitattributes, not in vendor/b/
[1]
```

## The definition in the monorepo's root

Git reads macro definitions in the monorepo's top-level
`.gitattributes`. Copy the definition there, and commit it:

```scrut
$ echo '[attr]crlf-text text eol=crlf' >>.gitattributes &&
>   git add .gitattributes &&
>   git commit -q -m "define crlf-text for vendor/a"
```

```scrut
$ cat .gitattributes
[attr]crlf-text text eol=crlf
```

Git still warns about the definition in `vendor/a/.gitattributes`, but
the rule below it now gets the attributes from the root's:

```scrut
$ git check-attr text eol -- vendor/a/run.bat
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1
vendor/a/run.bat: text: set
vendor/a/run.bat: eol: crlf
```

So the conversion goes through, with the warning each time Git reads
the file:

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1 (equal+)
ok   vendor/a: cloned 374055d from the submodule
===  vendor/a: pinned at 374055d, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

`run.bat` is checked out with CRLF, as in the submodule:

```scrut
$ cat -A vendor/a/run.bat
echo run^M$
```

Nothing shows as changed:

```scrut
$ git status --short
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1
```

## A macro a later pull brings in

The copy in the root covers the macros upstream defines at the clone.
`pull` doesn't check the attributes again, a known bug
([#311](https://github.com/roschaefer/git-splice/issues/311)). To pull,
the splice follows `main` instead of the submodule's pin:

```scrut
$ git config --file vendor/a/.splice --unset upstream.origin.default-pin &&
>   git commit -q -m "vendor/a: follow main" vendor/a/.splice
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1 (equal+)
```

Upstream defines a second macro, and gives it to `.cmd` files:

```scrut
$ git clone -q -c user.name=Test -c user.email=test@example.com https://git.example.com/a.git ../a-dev &&
>   printf '[attr]crlf-cmd text eol=crlf\n*.cmd crlf-cmd\n' >>../a-dev/.gitattributes &&
>   printf 'echo start\n' >../a-dev/start.cmd &&
>   git -C ../a-dev add .gitattributes start.cmd &&
>   git -C ../a-dev commit -q -m "add start.cmd" &&
>   git -C ../a-dev push -q
warning: in the working copy of 'start.cmd', LF will be replaced by CRLF the next time Git touches it
```

In upstream's checkout, `start.cmd` has CRLF:

```scrut
$ rm ../a-dev/start.cmd && git -C ../a-dev checkout -- start.cmd && cat -A ../a-dev/start.cmd
echo start^M$
```

and is stored with LF (`i/lf`):

```scrut
$ git -C ../a-dev ls-files --eol start.cmd
i/lf    w/crlf  attr/text eol=crlf    \tstart.cmd (escaped)
```

The pull goes through:

```scrut
$ git splice pull vendor/a
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1 (equal+)
ok   vendor/a fetched (main moved 374055d..45de624)
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1 (equal+)
ok   vendor/a: pulled 45de624
```

In the monorepo, the new macro's attributes are gone:

```scrut
$ git check-attr text eol -- vendor/a/start.cmd
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1
[attr]crlf-cmd text eol=crlf not allowed: vendor/a/.gitattributes:3
vendor/a/start.cmd: text: unspecified
vendor/a/start.cmd: eol: unspecified
```

and `start.cmd` is checked out with LF:

```scrut
$ cat -A vendor/a/start.cmd
echo start$
```

A one-line change to `start.cmd`, made with CRLF as in upstream's
checkout:

```scrut
$ printf 'echo start\r\necho test\r\n' >vendor/a/start.cmd && git commit -q -a -m "test in start.cmd"
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1
[attr]crlf-cmd text eol=crlf not allowed: vendor/a/.gitattributes:3
```

`status` shows nothing but the commit to push:

```scrut
$ git splice status
On branch main

  ahead 1  vendor/a
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 40de4e8 to main
```

The push stores `start.cmd` with CRLF (`i/crlf`), which upstream's own
attributes would have stored with LF:

```scrut
$ git -C ../a-dev pull -q && git -C ../a-dev ls-files --eol start.cmd
i/crlf  w/crlf  attr/text eol=crlf    \tstart.cmd (escaped)
```
