# Scenario: a recursive pull, discovered top-down

A splice's upstream decides which splices are inside it. When it
removes one, adds one, or puts another at the same folder, the tree the
monorepo knew before its pull is gone. So a pull has to go top-down:
only after the splice above is pulled is it known what's below it.

Here, `a`'s upstream drops `d/` and splices `e/` in, in one commit,
*a2*. `d`'s own upstream moves on all the same.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=8 GIT_CONFIG_KEY_0="url.$UPSTREAM-a.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git GIT_CONFIG_KEY_1="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/b.git GIT_CONFIG_KEY_2="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/c.git GIT_CONFIG_KEY_3="url.$UPSTREAM-d.git.insteadOf" GIT_CONFIG_VALUE_3=https://git.example.com/d.git GIT_CONFIG_KEY_4="url.$UPSTREAM-e.git.insteadOf" GIT_CONFIG_VALUE_4=https://git.example.com/e.git GIT_CONFIG_KEY_5=user.name GIT_CONFIG_VALUE_5=Test GIT_CONFIG_KEY_6=user.email GIT_CONFIG_VALUE_6=test@example.com GIT_CONFIG_KEY_7=core.editor GIT_CONFIG_VALUE_7=true
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_recursive_pull
```

![The tree: the monorepo at s; vendor/a/ at a1; in it, b/ at b1, with c/ at c1 in it, and d/ at d1](removed-before.drawio.svg)

<!--
```scrut
$ check_drawing "$TESTDIR/removed-before.drawio.svg" s=HEAD
ok   removed-before.drawio.svg: a tree of 5 rows
```
-->

```scrut
$ git clone -q https://git.example.com/d.git ../d-work &&
>   echo "d upstream" >>../d-work/file.txt &&
>   git -C ../d-work commit -q -am "d2: d upstream" &&
>   git -C ../d-work push -q origin main
```

```scrut
$ git clone -q https://git.example.com/a.git ../a-work &&
>   cd ../a-work &&
>   git rm -q -r d &&
>   git commit -q -m "drop d" &&
>   git splice clone https://git.example.com/e.git e >/dev/null &&
>   git reset -q --soft HEAD~2 &&
>   git commit -q -m "a2: d dropped, e spliced in" &&
>   git push -q origin main &&
>   cd ../monorepo
```

## Naming a splice and one inside it

`pull vendor/a vendor/a/d` names `vendor/a/d` as the monorepo knows it
now. By the time it gets there, `a`'s pull has dropped it, and the
command succeeds without pulling it
([#438](https://github.com/roschaefer/git-splice/issues/438)). On a
branch, to keep `main` as it is:

```scrut
$ git switch -q -c both &&
>   git splice pull --branch main vendor/a vendor/a/d
ok   vendor/a fetched (main moved 764d9c4..04072ca)
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
ok   vendor/a/d fetched (main moved 2c64d15..36c850e)
ok   vendor/a: pulled 04072ca
ok   vendor/a/d: not a splice any more -- nothing to pull
```

Had `a`'s upstream put another splice at `d/`, the second half would
have reported on that one instead. Naming a splice and one inside it
can't mean anything definite, so `git-splice` should refuse it.

## A recursive pull

`pull --recursive` names only `vendor/a`, and reads what's inside it
from the result of its pull: `e/` is pulled, and `d/`, selected when it
was still there, was removed by the pull of `vendor/a`.

```scrut
$ git switch -q main &&
>   git splice pull --recursive vendor/a
ok   vendor/a fetched
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
ok   vendor/a/d fetched
ok   vendor/a: pulled 04072ca
ok   vendor/a/e fetched
ok   vendor/a/e: nothing to pull
ok   vendor/a/b: nothing to pull
ok   vendor/a/b/c: nothing to pull
ok   vendor/a/d: removed by the pull of vendor/a
```

![The tree: the monorepo at p, outlined blue; vendor/a/ at a2, outlined blue; in it, b/ at b1, with c/ at c1 in it, and the new e/ at e1, outlined blue; no d/](removed-after.drawio.svg)

<!--
```scrut
$ check_drawing "$TESTDIR/removed-after.drawio.svg" p=HEAD
ok   removed-after.drawio.svg: a tree of 5 rows
```
-->
