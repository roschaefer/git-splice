# First fetch failed

In the [same state](README.md), a fresh clone after `init`, the first
fetch fails, e.g. without network. `merge` never fetches, so it can only
tell a fetched upstream from one never fetched here. A failed fetch
leaves the upstream as unknown as before, and `merge` still says so,
rather than that the upstream has no branch and there is nothing to
merge.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" &&
>   export GIT_CONFIG_COUNT=1 \
>     GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" \
>     GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_init_then_cloned https://git.example.com/a.git
```

`GIT_ALLOW_PROTOCOL=none` lets Git use no protocol at all, so the fetch
fails as it would without network:

```scrut
$ GIT_ALLOW_PROTOCOL=none git splice fetch lib/a
fatal: transport 'file' not allowed
!!   lib/a fetch failed
!!   Failed: lib/a
[1]
```

```scrut
$ git splice merge lib/a
??   lib/a: not fetched yet -- run 'git splice fetch lib/a' first
!!   Failed: lib/a
[1]
```

Once a fetch succeeds, `merge` knows the upstream, and that it has
just the two commits the folder has already:

```scrut
$ git splice fetch lib/a
ok   lib/a fetched
```

```scrut
$ git splice merge lib/a
ok   lib/a: nothing to merge
```
