# Scenario: clone-from-submodule, with a macro in upstream's attributes

Upstream's own `.gitattributes` defines a macro. Git accepts macro
definitions only in the top-level `.gitattributes`, which upstream's is
in its own repository and in a submodule, but not in a splice's folder.
This is a known gap, for a converted submodule and a plain `clone`
alike ([#311](https://github.com/roschaefer/git-splice/issues/311)).

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

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
??   vendor/a: Git applies other text eol filter ident working-tree-encoding attributes to some of its files than in upstream, which unsetting them above it can't change -- e.g. those of a macro its own .gitattributes defines, which Git accepts only at the top
\[attr\]crlf-text text eol=crlf not allowed: vendor/a/\.gitattributes:1 (regex+)
ok   vendor/a: cloned [0-9a-f]{7} from the submodule (regex)
===  vendor/a: pinned at [0-9a-f]{7}, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin (regex)
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

Git warns each time it reads the definition. Asked from the top of the
monorepo, as checkout and `git add` ask, the attributes are gone. The
conversion says so (`??`) and adds no line to `.gitattributes`: one
only resets what comes from above, and can't bring the macro back.

```scrut
$ git check-attr text eol -- vendor/a/run.bat
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1
vendor/a/run.bat: text: unspecified
vendor/a/run.bat: eol: unspecified
```

So the file the submodule checked out with CRLF shows as changed:

```scrut
$ git status --short
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1
 M vendor/a/run.bat
```

A plain `clone` of the same upstream checks `run.bat` out with LF, unlike
a clone of the upstream itself:

```scrut
$ git checkout -q -- vendor/a && git splice clone https://git.example.com/a.git vendor/b 2>/dev/null >/dev/null && cat -A vendor/b/run.bat
[attr]crlf-text text eol=crlf not allowed: vendor/a/.gitattributes:1
echo run$
```
