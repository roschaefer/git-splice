# Scenario: nested-splices, pulled after a splice was made around them

A pull of `vendor/a/b` runs one level down, in worktrees of the rebuilds
of the splices above it. Each of those starts where its splice was made.
Here, `vendor/` is made a splice around `vendor/a/` after the monorepo
pushed a change to `vendor/a/b/`, so `vendor/`'s rebuild starts at its
`init`, with that change folded into the one commit. From there, `b/`'s
history would have the pushed change in another commit than its
upstream has, and the merge would take both for different changes.

So the merge one level down takes `b/`'s history from the monorepo,
which walks its own commits for `vendor/a/b/` and has the pushed one. The
worktrees give the files and the `.splice` files the merge sees, the
monorepo gives the history.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Test GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

The monorepo pushes a change to `vendor/a/b/`, then makes `vendor/` a
splice of a new upstream, and changes `vendor/a/b/` again:

```scrut
$ echo "b local" >>vendor/a/b/file.txt &&
>   git commit -q -am "b local" &&
>   git splice push vendor/a/b
ok   vendor/a/b: pushed 701ab17 to main
```

```scrut
$ git init -q --bare -b main "$UPSTREAM-vendor.git" &&
>   git splice init vendor "$UPSTREAM-vendor.git"
ok   vendor: initialized -- 'git splice push vendor' publishes it
```

```scrut
$ echo "b next" >>vendor/a/b/file.txt &&
>   git commit -q -am "b next"
```

The inner upstream gets a file of its own:

```scrut
$ git clone -q https://git.example.com/b.git ../b-work &&
>   echo "b upstream" >../b-work/other.txt &&
>   git -C ../b-work add other.txt &&
>   git -C ../b-work commit -q -m "b upstream" &&
>   git -C ../b-work push -q origin main
```

`vendor/`'s rebuild starts at the `init`:

```scrut
$ git log --format=%s "$(git splice rebuild vendor)"
b next
splice: init vendor
```

## The pull

It goes through `vendor/` and `vendor/a/`, and merges without a conflict:
the pushed change is part of `b/`'s history on both sides.

```scrut
$ git splice pull vendor/a/b
ok   vendor/a/b fetched (main moved 701ab17..beb3239)
ok   vendor/a/b: pulled beb3239
```

```scrut
$ git log --graph --format=%s "$(git splice rebuild vendor/a/b)"
*   splice: pull vendor/a/b from main at beb3239
|\  
| * b upstream
* | b next
|/  
* b local
* b seed
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed 1446354 to main
```
