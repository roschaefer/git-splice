# What a release contains

Something broke after a release, and the first question is which commit
of each library went out in it. With one repository per library, that
answer has to be written down somewhere at release time, e.g. in a CI
log or in the release tag's message. In a monorepo, every commit already
has it: each splice's `.splice` names its synced commit, and `.splice` is
part of the commit like any other file. A tag, even a lightweight one, is
enough to find it again later.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_many_splices
```

Tag the release, then keep working: pull `http/` and push `parser/`.

```scrut
$ git tag v1.0
```

```scrut
$ git splice pull libs/http
ok   libs/http fetched
ok   libs/http: pulled 362464c
```

```scrut
$ git splice push libs/parser && git splice pull --bump libs/parser
ok   libs/parser: pushed e859a6b to main
ok   libs/parser fetched
ok   libs/parser: bumped the synced commit to e859a6b
```

The release still names the upstream commits it was built from. The five
upstreams start from the same seed commit, so their hashes match:

```scrut
$ git grep "commit =" v1.0 -- "*.splice"
v1.0:libs/cli/.splice:	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
v1.0:libs/http/.splice:	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
v1.0:libs/parser/.splice:	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
v1.0:libs/store/.splice:	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
v1.0:libs/theme/.splice:	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
```

`main` has moved on, with `http/` and `parser/` at newer upstream commits:

```scrut
$ git grep "commit =" main -- "*.splice"
main:libs/cli/.splice:	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
main:libs/http/.splice:	commit = 362464c1de5805208332c1639ccbe8960c915e7f
main:libs/parser/.splice:	commit = e859a6b3f55b1e873e69f2dc39247c735e67df6a
main:libs/store/.splice:	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
main:libs/theme/.splice:	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
```

The synced commit is where a splice last met its upstream, not always
what shipped: `parser/` had a commit that wasn't pushed yet when the
release was tagged. The release's own history has it:

```scrut
$ git log --format=%s v1.0 -- libs/parser
local change
add libs/parser
```

To get the release's code back, check out the tag. Nothing else needs to
be cloned, and the upstreams don't even need to exist anymore. Delete
them all, then check out the release:

```scrut
$ rm -rf "${UPSTREAM%.git}"-*.git
```

```scrut
$ git switch -q --detach v1.0 && cat libs/parser/file.txt
seed
local change
```
