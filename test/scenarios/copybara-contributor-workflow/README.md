# Scenario: test an external contribution without taking over its merge

[Copybara requires one repository to be authoritative](https://github.com/google/copybara#readme).
In the common workflow where that source of truth is an internal monorepo,
a public pull request is imported and submitted there. For example, XLA's
[Copybara notes](https://github.com/openxla/xla/blob/main/docs/copybara.md#pr-merge-status-and-diff-inconsistencies)
explain that the original PR is closed rather than marked as merged, while a
separate commit is applied publicly.

With `git splice`, the monorepo can pull the contributor's branch for its
own tests without publishing anything. The maintainers can then merge the
pull request in the public upstream repository and pull the resulting
`main` branch back into the monorepo.

## Output

`scenario_copybara_contributor_workflow` in [`setup.bash`](setup.bash)
creates a published library, an external `contribution` branch, and a
matching monorepo branch. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_copybara_contributor_workflow
```
-->

Pull the proposed branch into the monorepo and test its content there:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled c4d8fc9
```

```scrut
$ cat vendor/a/file.txt
published library
external contribution
```

The public `main` branch is still unchanged:

```scrut
$ git -C "$UPSTREAM" log --format=%s main
published library
```

Simulate merging the public pull request in its upstream repository:

```scrut
$ git -C "$UPSTREAM" branch main-before-pr main && merge_contribution_upstream "$UPSTREAM"
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s --all | sed 's/ *$//'
*   Merge external contribution
|\
| * external contribution
|/
* published library
```

Now return to the monorepo's `main` and pull the public merge result:

```scrut
$ git checkout -q main && git splice pull vendor/a
ok   vendor/a fetched (main moved d4e2b0d..e5031ee)
ok   vendor/a: pulled e5031ee
```

```scrut
$ git log -1 --format=%s && tail -n 1 vendor/a/file.txt
splice: pull vendor/a from main at e5031ee
external contribution
```
