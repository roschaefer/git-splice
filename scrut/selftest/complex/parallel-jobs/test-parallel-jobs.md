# Run documents at the same time with --jobs

Tests in this file validate that `--jobs` runs documents at the same time and
still reports them in the order they are given.

`first.mdtest` waits for a signal that `second.mdtest` sends. Run one after
another, the first document finishes before the second one starts, so it
waits in vain. Only if both run at the same time does the first one get the
signal.

## The signal

The signal is a file. `send_signal` writes it under a temporary name and
renames it into place, so it appears complete or not at all:

```scrut
$ export SIGNAL_FILE="$TMPDIR/signal"
> send_signal() {
>   echo "from the second document" > "$SIGNAL_FILE.tmp"
>   mv "$SIGNAL_FILE.tmp" "$SIGNAL_FILE"
> }
```

`wait_for_signal` looks for the file every 0.1 seconds, for up to
`$WAIT_SECONDS`, and stops as soon as it is there:

```scrut
$ wait_for_signal() {
>   for _ in $(seq "$((WAIT_SECONDS * 10))"); do
>     [ -e "$SIGNAL_FILE" ] && break
>     sleep 0.1
>   done
>   cat "$SIGNAL_FILE" 2>/dev/null || echo "no signal"
> }
```

Both are exported, so that the shells of the two documents have them:

```scrut
$ export -f send_signal wait_for_signal
```

## Without --jobs, documents run one after another

The first document waits in vain, because the second one starts only after
it. A second is enough to show that.

```scrut
$ WAIT_SECONDS=1 "$SCRUT_BIN" test --match-markdown "*.mdtest" \
>   "$TESTDIR/first.mdtest" "$TESTDIR/second.mdtest"
// =============================================================================
// @ *first.mdtest:6 (glob)
// -----------------------------------------------------------------------------
// # Waits for the signal of the second document
// -----------------------------------------------------------------------------
// $ wait_for_signal
// =============================================================================

1     | - from the second document
   1  | + no signal


Result: 2 document(s) with 2 testcase(s): 1 succeeded, 1 failed and 0 skipped
[50]
```

## With --jobs, documents run at the same time, reported in their order

```scrut
$ rm "$SIGNAL_FILE"
```

The first document gets the signal. It finishes last, because it waits for
the second one, but it is still reported first. The limit of 30 seconds only
matters on a slow machine.

```scrut
$ WAIT_SECONDS=30 "$SCRUT_BIN" test --jobs 2 --renderer yaml --match-markdown "*.mdtest" \
>   "$TESTDIR/first.mdtest" "$TESTDIR/second.mdtest"
- location: *first.mdtest (glob)
  title: Waits for the signal of the second document
  result:
    kind: success
- location: *second.mdtest (glob)
  title: Sends the signal the first document waits for
  result:
    kind: success
```

## Documents can't share a user provided work directory

```scrut
$ "$SCRUT_BIN" test --jobs 2 --work-directory "$TMPDIR" --match-markdown "*.mdtest" \
>   "$TESTDIR/first.mdtest" 2>&1
* ERROR scrut: Error: --work-directory can't be combined with running documents in parallel (--jobs 2 or more) (glob)
[1]
```

With `--jobs 1`, the documents run one after another, so they can share it:

```scrut
$ "$SCRUT_BIN" test --jobs 1 --work-directory "$TMPDIR" --match-markdown "*.mdtest" \
>   "$TESTDIR/second.mdtest"
Result: 1 document(s) with 1 testcase(s): 1 succeeded, 0 failed and 0 skipped
```

## update runs one document after another

`update` writes documents, which documents running at the same time could
read half-written, so it has no `--jobs`.

```scrut
$ "$SCRUT_BIN" update --jobs 2 --match-markdown "*.mdtest" "$TESTDIR/first.mdtest" 2>&1
error: unexpected argument '--jobs' found
* (glob+)
[2]
```
