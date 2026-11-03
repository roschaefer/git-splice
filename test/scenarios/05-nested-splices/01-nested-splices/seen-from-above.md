# Scenario: nested-splices, seen from the splice above

A nested splice syncs with the splice directly above it, never with the
monorepo directly. `vendor/a/b/` sees only what a clone of the outer
upstream would see: the history of `vendor/a/`.

That history is the rebuild of `vendor/a/`, the commits the outer
upstream would get from a push of `vendor/a/`. It's the monorepo as the
splice above sees it: its **view**. The rebuild of `vendor/a/b/` is made
from the view, the way a clone of the outer upstream would rebuild its
`b/`. Each layer only needs to get one level of nesting right, and the
next level down works the same way from the view of the one above.

This page shows the view after a pull of `vendor/a/` that brings a
change to `b/`, and the rebuild of `vendor/a/b/` made from it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Test GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
the outer upstream with the inner one spliced in at `b/`, cloned into
the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

In a clone of the outer upstream, a maintainer changes `b/`:

```scrut
$ git clone -q "$UPSTREAM" ../a-work &&
>   cd ../a-work &&
>   echo "b in a's upstream" >>b/file.txt &&
>   git -c user.name=Maintainer -c user.email=maintainer@example.com \
>     commit -q -am "b in a's upstream" &&
>   git push -q origin HEAD:main &&
>   cd ../monorepo
```

The monorepo pulls `vendor/a/`:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved * (glob)
ok   vendor/a/b fetched
ok   vendor/a: pulled * (glob)
```

## The view: the rebuild of `vendor/a/`

The monorepo has no changes of its own in `vendor/a/`, so the view is
the outer upstream's `main`:

```scrut
$ git log --graph --format='%s (%an)' "$(git splice rebuild vendor/a)"
* b in a's upstream (Maintainer)
* add b (Test)
* a seed (Test)
```

## The rebuild of `vendor/a/b/`, made from the view

Each commit of the view that changes `b/` becomes a commit of the inner
splice, with its author, on top of the inner upstream's commit the outer
upstream had at `b/`:

```scrut
$ git log --graph --format='%s (%an)' "$(git splice rebuild vendor/a/b)"
* b in a's upstream (Maintainer)
* b seed (Test)
```

The view has the commits the monorepo knows of, also where a push of
`vendor/a/` alone wouldn't send them: a change pushed to the inner
upstream that the outer upstream then got from someone else stays in the
view ([pushed and made above](pushed-and-made-above.md)). A merge in the
view becomes one commit of the inner splice, as any merge does
([changed above, in a merge](changed-above-in-a-merge.md)).
