# Fresh clone pulls from both

In the [same state](README.md), the original and its company fork, the
monorepo last pulled from the original, then made the fork its default
upstream. A colleague clones the monorepo and pulls. The synced commit
is a release only the original has, and the clone has fetched nothing
yet, so the pull fetches every upstream to find it, not only the fork it
pulls from.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/lib.git GIT_CONFIG_KEY_1="url.$UPSTREAM-fork.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/company/lib.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_several_upstreams https://git.example.com/lib.git
```

The original moves on, and the monorepo pulls the release:

```scrut
$ seed_bare_repo "$UPSTREAM" "original release" main release.txt
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved bde4164..3fd09f0)
ok   vendor/a: pulled 3fd09f0
```

Then it works with the fork:

```scrut
$ git config --file vendor/a/.splice upstream.fork.url https://git.example.com/company/lib.git
```

```scrut
$ git config --file vendor/a/.splice splice.default-upstream fork
```

```scrut
$ git commit -q -m "vendor/a: work with the company fork" -- vendor/a/.splice
```

### In a fresh clone

```scrut
$ git clone -q --no-local . ../fresh && cd ../fresh && git config user.name Test && git config user.email test@example.com
```

The synced commit is the release, which the fork lacks, and the clone
doesn't have it either:

```scrut
$ git cat-file -e "$(git config --file vendor/a/.splice splice.commit)"
[1]
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched from origin
ok   vendor/a fetched from fork
ok   vendor/a: pulled 9bf41c7
```

The release from the original is the merge base, so the pull joins the
fork's patch with it, as the monorepo would have.
