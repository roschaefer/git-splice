# Missing upstream names

What commands do when no upstream is named, or the one named isn't
there ([#107](https://github.com/roschaefer/git-splice/issues/107)). In
both cases they refuse before doing anything:

| question | refused, because the alternative would … |
|---|---|
| several upstreams, no `default-upstream` | let the order of the sections, or a conventional name like `origin`, decide where a pull comes from and a push goes |
| `--upstream fork`, a selected splice has no `fork` | push some splices to their default upstream without saying so, or leave half of `--all` done |

[`setup.bash`](setup.bash) builds the state of
[several-upstreams](README.md): `vendor/a` from the original, and its
company fork.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/lib.git GIT_CONFIG_KEY_1="url.$UPSTREAM-fork.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/company/lib.git
```
-->

```scrut
$ build_scenario scenario_several_upstreams https://git.example.com/lib.git
```

### No default

The fork is added, but no `default-upstream`:

```scrut
$ git config --file vendor/a/.splice upstream.fork.url https://git.example.com/company/lib.git && git commit -q -m "vendor/a: add the company fork" -- vendor/a/.splice
```

Commands that need one upstream refuse, and say how to choose:

```scrut
$ git splice status
!!   vendor/a names upstreams 'origin' and 'fork', but no default -- pass --upstream <name>, or commit one: git config --file vendor/a/.splice splice.default-upstream <name>
[1]
```

`--upstream` chooses for one command:

```scrut
$ git splice fetch --upstream fork && git splice status --upstream fork
ok   vendor/a fetched from fork
ok   vendor/a -> fork/main (pull: behind 1)
```

`fetch` without it fetches every upstream, so it needs no default:

```scrut
$ git splice fetch
ok   vendor/a fetched from origin
ok   vendor/a fetched from fork
```

```scrut
$ git config --file vendor/a/.splice splice.default-upstream fork && git commit -q -m "vendor/a: work with the company fork" -- vendor/a/.splice
```

```scrut
$ git splice status
ok   vendor/a -> fork/main (pull: behind 1)
```

### A name the splice doesn't have

```scrut
$ git splice status --upstream mirror
!!   vendor/a has no upstream 'mirror' -- its upstreams are 'origin' and 'fork'
[1]
```

### A name only some splices have

A second splice of the original, without a fork:

```scrut
$ git splice clone https://git.example.com/lib.git vendor/b
===  vendor/b: fetching https://git.example.com/lib.git
ok   vendor/b: cloned bde4164 from main
```

Names are unique only within one `.splice`. `--upstream fork` with every
splice would leave `vendor/b` without an upstream to use, so it's
refused, naming the splices that have one:

```scrut
$ git splice pull --upstream fork --all
!!   no upstream 'fork' in vendor/b -- name only the splices that have one: vendor/a
[1]
```

```scrut
$ git splice status --upstream fork
!!   no upstream 'fork' in vendor/b -- name only the splices that have one: vendor/a
[1]
```

```scrut
$ git splice status --upstream fork vendor/a
ok   vendor/a -> fork/main (pull: behind 1)
```
