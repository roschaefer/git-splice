# Scenario: unspliced-then-cloned-again

A folder stops being a splice, and later becomes one again, of the same
upstream. Its second push sends only what happened since it became a
splice again. What the folder went through in between, or before, stays
in the monorepo, even if it was committed while the folder was a splice.

- **Monorepo (`lib/a`)**: made a splice with `init` and pushed.
- **Upstream**: the pushed commit, `splice: init lib/a`.

A splice's history starts at its **mount**: the newest commit whose
parent had no `.splice` at the path, or one naming another upstream URL.
Removing `.splice` ends a mount, and adding it again starts a new one. A
commit made before that, like the password below, was never pushed to
the upstream, and by the time the folder is a splice again, it may hold
what was removed in between. See
[removed-before-init](../removed-before-init/README.md) for the same
reason at `init`, and
[the design notes](../../../../docs/design/README.md#splicing-out-push-and-the-rebuild).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_unspliced_then_cloned_again
```

A password is committed and not pushed. Then `lib/a` stops being a
splice, and the password is removed again:

```scrut
$ echo "password = hunter2" >lib/a/config.txt && git add lib/a/config.txt && git commit -q -m "add the password"
```

```scrut
$ git rm -q lib/a/.splice && git commit -q -m "lib/a is no splice anymore"
```

```scrut
$ git rm -q lib/a/config.txt && git commit -q -m "remove the password again"
```

```scrut
$ echo "notes" >lib/a/notes.txt && git add lib/a/notes.txt && git commit -q -m "add notes"
```

Later, `lib/a` becomes a splice of the same upstream again. The folder
differs from the upstream, so it takes `clone --merge`:

```scrut
$ git splice clone --merge "$UPSTREAM" lib/a
===  lib/a: fetching $UPSTREAM
ok   lib/a: cloned 905f2b9 from main
```

```scrut
$ git splice log lib/a
===  lib/a (main)
< 6153f14 splice: clone lib/a from main at 905f2b9  (Test <test@example.com>)
```

```scrut
$ git splice push lib/a
ok   lib/a: pushed 6153f14 to main
```

The upstream gets one commit on top of what it had: the clone, with the
folder as it is now. None of the commits in between:

```scrut
$ git -C "$UPSTREAM" log --format=%s main
splice: clone lib/a from main at 905f2b9
splice: init lib/a
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main -- config.txt
```
