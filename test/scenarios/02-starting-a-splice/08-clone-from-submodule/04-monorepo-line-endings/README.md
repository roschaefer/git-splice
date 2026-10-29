# Scenario: clone-from-submodule, under the monorepo's line endings

Git applies a repository's `.gitattributes` to its own files, never to a
submodule's. Once the submodule is a folder, the monorepo's attributes
would apply to its files too, so the conversion unsets those that
change a checkout for the folder: `text` and `eol` for line endings, as
here, and `filter`, `ident` and `working-tree-encoding`.

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

The conversion adds a line to `.gitattributes` that unsets them, and the
other attributes that change a checkout, for the folder again:

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
===  vendor/a: unset text eol filter ident working-tree-encoding for it in .gitattributes -- Git never applied these from above a submodule to its files
ok   vendor/a: cloned [0-9a-f]{7} from the submodule (regex)
===  vendor/a: pinned at [0-9a-f]{7}, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin (regex)
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

```scrut
$ cat .gitattributes
*.bat text eol=crlf
vendor/a/** !text !eol !filter !ident !working-tree-encoding
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

With the `.gitattributes` from before the conversion, Git stores
`build.bat` with LF the next time it's added, and the next push would
send that change to the upstream:

```scrut
$ git checkout -q HEAD^ -- .gitattributes && git add --renormalize vendor/a && git status --short
M  .gitattributes
M  vendor/a/build.bat
```

And a checkout would give `run.bat`, which the submodule had with LF,
CRLF instead (`^M`):

```scrut
$ rm vendor/a/run.bat && git checkout -- vendor/a/run.bat && cat -A vendor/a/run.bat
echo run^M$
```
