# Scenario: clone-from-submodule

A submodule, turned into a splice with `git splice clone --from-submodule`.

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out at `seed`.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `seed`, then `newer` on `main`: it moved on since the
  submodule's commit.

The splice keeps the submodule's URL and the commit it points to. What
it follows from then on depends on the submodule's `branch` in
`.gitmodules`, the branch `git submodule update --remote` follows:

| `branch` in `.gitmodules` | The submodule | `.splice` records | The splice on `main` |
| --- | --- | --- | --- |
| none, as here | stays at its commit | `default-pin <commit>` | stays at it ([submodule-without-branch](01-submodule-without-branch/README.md)) |
| `stable` | follows `stable` | `default-branch stable` | follows `stable` ([submodule-with-branch](02-submodule-with-branch/README.md)) |
| `.` | follows the branch named like the monorepo's | neither | follows `main` ([submodule-with-branch-dot](03-submodule-with-branch-dot/README.md)) |

Line ending attributes above the submodule never applied to its files,
and the conversion keeps it that way: those of the monorepo
([monorepo-line-endings](04-monorepo-line-endings/README.md)), or of a
splice above it ([line-endings-in-splice-above](05-line-endings-in-splice-above/README.md)).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_clone_from_submodule https://git.example.com/a.git
```

```scrut
$ cat .gitmodules
[submodule "vendor/a"]
	path = vendor/a
	url = https://git.example.com/a.git
```

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from the submodule
===  vendor/a: pinned at bde4164, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

One commit replaces the submodule with its files and a `.splice`, and
removes it from `.gitmodules`, here the whole file:

```scrut
$ git show --stat --format=%s
splice: clone vendor/a from submodule at bde4164

 .gitmodules       | 3 ---
 vendor/a          | 1 -
 vendor/a/.splice  | 6 ++++++
 vendor/a/file.txt | 1 +
 4 files changed, 7 insertions(+), 4 deletions(-)
```
