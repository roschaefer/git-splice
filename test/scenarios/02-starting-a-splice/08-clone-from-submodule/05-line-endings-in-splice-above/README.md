# Scenario: clone-from-submodule, under the line endings of the splice above

As in [monorepo-line-endings](../04-monorepo-line-endings/README.md),
but the attributes come from the upstream of the submodule above, whose
own submodule `--recursive` converts too. The refusal comes when the
conversion reaches the nested submodule, with the one above converted.

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

The conversion of `vendor/a` goes through. That of `libs/inner` stops
before it changes anything, as the splice above's attributes would apply
to its files:

```scrut
$ git splice clone --from-submodule --recursive vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned 74902fd from the submodule
===  vendor/a: pinned at 74902fd, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
===  vendor/a/libs/inner: fetching https://git.example.com/inner.git
!!   vendor/a/libs/inner: attributes in vendor/a/.gitattributes or above it would change how Git checks out or stores some of its files, unlike in upstream -- add 'libs/inner/** !text !eol !filter !ident !working-tree-encoding' to vendor/a/.gitattributes, commit it, and run clone again
!!   vendor/a/libs/inner: not converted -- vendor/a and what was converted before stay; fix the above, then run 'git splice clone --from-submodule --recursive vendor/a/libs/inner'
[1]
```

The line it names goes to the `.gitattributes` of the splice above, the
deepest one above the folder, where it wins over the line it undoes:

```scrut
$ echo 'libs/inner/** !text !eol !filter !ident !working-tree-encoding' >>vendor/a/.gitattributes && git commit -q -m "keep vendor/a's line endings off libs/inner" vendor/a/.gitattributes
```

and clone on `libs/inner` resumes:

```scrut
$ git splice clone --from-submodule --recursive vendor/a/libs/inner
===  vendor/a/libs/inner: fetching https://git.example.com/inner.git
ok   vendor/a/libs/inner: cloned 59ad078 from the submodule
===  vendor/a/libs/inner: pinned at 59ad078, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/libs/inner/.splice --unset upstream.origin.default-pin
===  vendor/a/libs/inner: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a/modules/libs/inner -- remove it once you don't need it (regex)
===  vendor/a: upstream still has libs/inner as a submodule -- 'git splice push vendor/a' turns it into a splice there too
```

```scrut
$ git status --short
```

That file belongs to `vendor/a`'s upstream, so pushing `vendor/a` sends
the line there, together with the change that turns `libs/inner` into a
folder. That upstream would need it as much.
