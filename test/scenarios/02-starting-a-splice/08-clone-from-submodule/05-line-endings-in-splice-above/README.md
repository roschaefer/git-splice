# Scenario: clone-from-submodule, under the line endings of the splice above

As in [monorepo-line-endings](../04-monorepo-line-endings/README.md),
but the attributes come from the upstream of the submodule above, whose
own submodule `--recursive` converts too.

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out with its own submodules.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `.gitattributes` wants `.h` files with LF, and `libs/inner/` is a
  submodule of the inner upstream.
- **Inner upstream** (`$UPSTREAM-inner`, reached as
  `https://git.example.com/inner.git`): `settings.h` committed with CRLF.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git GIT_CONFIG_KEY_1="url.$UPSTREAM-inner.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/inner.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_line_endings_in_splice_above https://git.example.com/a.git https://git.example.com/inner.git
```

```scrut
$ cat vendor/a/.gitattributes
*.h text eol=lf
```

```scrut
$ git splice clone --from-submodule --recursive vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned [0-9a-f]{7} from the submodule (regex)
===  vendor/a: pinned at [0-9a-f]{7}, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin (regex)
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
===  vendor/a/libs/inner: fetching https://git.example.com/inner.git
===  vendor/a/libs/inner: unset text eol filter ident working-tree-encoding for it in vendor/a/.gitattributes -- in upstream, only its own .gitattributes apply to its files
ok   vendor/a/libs/inner: cloned [0-9a-f]{7} from the submodule (regex)
===  vendor/a/libs/inner: pinned at [0-9a-f]{7}, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/libs/inner/.splice --unset upstream.origin.default-pin (regex)
===  vendor/a/libs/inner: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a/modules/libs/inner -- remove it once you don't need it (regex)
===  vendor/a: upstream still has libs/inner as a submodule -- 'git splice push vendor/a' turns it into a splice there too
```

The line goes to the `.gitattributes` of the splice above, the deepest
one above the folder, where it wins over the line it undoes:

```scrut
$ cat vendor/a/.gitattributes
*.h text eol=lf
libs/inner/** !text !eol !filter !ident !working-tree-encoding
```

```scrut
$ git status --short
```

That file belongs to `vendor/a`'s upstream, so pushing `vendor/a` sends
the line there, together with the change that turns `libs/inner` into a
folder. That upstream would need it as much.
