# Scenario: clone-from-submodule, with a macro in upstream's attributes

Upstream's own `.gitattributes` defines a macro. Git accepts macro
definitions only in the top-level `.gitattributes`, which upstream's is
in its own repository and in a submodule, but not in a splice's folder.
A converted submodule and a plain `clone` alike would lose the macro's
attributes, and no line above the folder can bring them back: both
refuse, and leave the decision to you. This is a known gap
([#311](https://github.com/roschaefer/git-splice/issues/311)).

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

So the conversion refuses, without a line to add:

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
!!   vendor/a: Git would check out or store some of its files otherwise than in upstream, and unsetting attributes above it can't change that
[1]
```

And so does a plain `clone` of the same upstream:

```scrut
$ git splice clone https://git.example.com/a.git vendor/b
===  vendor/b: fetching https://git.example.com/a.git
!!   vendor/b: Git would check out or store some of its files otherwise than in upstream, and unsetting attributes above it can't change that
[1]
```
