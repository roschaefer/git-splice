# mirrors: mirrors that swap paths

> **Known bug, [#193](https://github.com/roschaefer/git-splice/issues/193).** This page shows what `git-splice` does today, bug included. See [known bugs and limitations](../../99-known-bugs.md#known-bugs).

Mirrors are one splice, so the rebuild can't tell them apart. Unlike
[independent splices](../02-swapped-splices/README.md),
each path keeps its own history, whichever mirror's files it has now.
After a swap, a push can publish what a mirror removed.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_mirrors
```

`vendor/a/` and its mirror `vendor/a-copy/`, a plain copy with the same
`.splice`:

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ cp -r vendor/a vendor/a-copy &&
>   git add vendor/a-copy &&
>   git commit -q -m "copy vendor/a"
```

A commit in each mirror, not pushed yet:

```scrut
$ echo "not for upstream" >vendor/a/secret.txt &&
>   git add vendor/a &&
>   git commit -q -m "a secret"
```

```scrut
$ echo "copy change" >>vendor/a-copy/file.txt && git commit -q -am "copy change"
```

Then they swap paths:

```scrut
$ git mv vendor/a tmp &&
>   git mv vendor/a-copy vendor/a &&
>   git mv tmp vendor/a-copy &&
>   git commit -q -m "swap the mirrors"
```

`vendor/a/` no longer has the secret, but a push still sends `a secret`,
then the swap that removes it:

```scrut
$ git splice log vendor/a
===  vendor/a (main)
< b480cac swap the mirrors  (Test <test@example.com>)
< aa4a177 a secret  (Test <test@example.com>)
```

Nothing in the monorepo tells this swap apart from edits that make one
splice look like the other. To avoid it, keep mirrors alike: push one,
and pull the others right away
([mirrors](../../../07-design/07-going-forward/01-mirrors.md#meanwhile-discipline)).
