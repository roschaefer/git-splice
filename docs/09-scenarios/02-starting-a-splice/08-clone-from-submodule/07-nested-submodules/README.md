# Scenario: clone-from-submodule, with a nested submodule, pushed

> **Limitation.** This page shows behaviour `git-splice` keeps on purpose, and the way out. See [known bugs and limitations](../../../99-known-bugs.md#limitations).

`--recursive` converts a submodule's own submodules too. The upstream
above still has them as submodules, so the next push of the folder above
turns them into splices in that upstream too
([#153](https://github.com/roschaefer/git-splice/issues/153)). If that
upstream's owners keep their submodules, push to a fork of yours instead
([contributing-through-a-fork](../../../04-upstreams/07-contributing-through-a-fork/README.md)).

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  following its `main`, checked out with its own submodules.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `libs/inner/` is a submodule of the inner upstream.
- **Inner upstream** (`$UPSTREAM-inner`, reached as
  `https://git.example.com/inner.git`): one commit, `inner`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git GIT_CONFIG_KEY_1="url.$UPSTREAM-inner.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/inner.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_nested_submodules https://git.example.com/a.git https://git.example.com/inner.git
```

The upstream has `libs/inner` as a submodule:

```scrut
$ git -C "$UPSTREAM" ls-tree --format='%(objectmode) %(objecttype) %(path)' main libs/
160000 commit libs/inner
```

```scrut
$ git splice clone --from-submodule --recursive vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bebc84b from the submodule
===  vendor/a: the submodule's repository stays in */monorepo/.git/modules/vendor/a -- remove it once you don't need it (glob)
===  vendor/a/libs/inner: fetching https://git.example.com/inner.git
ok   vendor/a/libs/inner: cloned 84c4dba from the submodule
===  vendor/a/libs/inner: pinned at 84c4dba, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/libs/inner/.splice --unset upstream.origin.default-pin
===  vendor/a/libs/inner: the submodule's repository stays in */monorepo/.git/modules/vendor/a/modules/libs/inner -- remove it once you don't need it (glob)
===  vendor/a: upstream still has libs/inner as a submodule -- 'git splice push vendor/a' turns it into a splice there too
```

The folder differs from the upstream by the conversion of `libs/inner`:

```scrut
$ git splice status
On branch main

  ahead 1     vendor/a

  up to date  vendor/a/libs/inner -> 84c4dba
```

The push sends it:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 8d99285 to main
```

and the upstream has `libs/inner` as a splice now, no longer as a
submodule:

```scrut
$ git -C "$UPSTREAM" ls-tree -r --format='%(objectmode) %(objecttype) %(path)' main libs/
100644 blob libs/inner/.splice
100644 blob libs/inner/file.txt
```

```scrut
$ git -C "$UPSTREAM" show --stat --format=%s main
splice: clone vendor/a/libs/inner from submodule at 84c4dba

 .gitmodules         | 3 ---
 libs/inner          | 1 -
 libs/inner/.splice  | 6 ++++++
 libs/inner/file.txt | 1 +
 4 files changed, 7 insertions(+), 4 deletions(-)
```
