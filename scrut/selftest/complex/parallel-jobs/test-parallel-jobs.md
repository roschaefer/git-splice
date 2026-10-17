# Run documents at the same time with --jobs

Tests in this file validate that `--jobs` runs documents at the same time and
still reports them in the order they are given. `first.mdtest` waits for a
file that `second.mdtest` writes, so it can only see that file if both run at
the same time, and it finishes last.

```scrut
$ export SIGNAL_FILE="$TMPDIR/signal"
```

## Without --jobs, documents run one after another

The first document waits in vain, because the second one starts only after it.

```scrut
$ "$SCRUT_BIN" test --match-markdown "*.mdtest" "$TESTDIR/first.mdtest" "$TESTDIR/second.mdtest"
// =============================================================================
// @ *first.mdtest:4 (glob)
// -----------------------------------------------------------------------------
// # Waits up to two seconds for the second document
// -----------------------------------------------------------------------------
// $ for i in $(seq 20); do [ -e "$SIGNAL_FILE" ] && break; sleep 0.1; done; echo "signal: $(cat "$SIGNAL_FILE" 2>/dev/null || echo none)"
// =============================================================================

1     | - signal: expected otherwise
   1  | + signal: none


// =============================================================================
// @ *second.mdtest:4 (glob)
// -----------------------------------------------------------------------------
// # Sends the signal the first document waits for
// -----------------------------------------------------------------------------
// $ echo "from the second document" > "$SIGNAL_FILE" && echo sent
// =============================================================================

1     | - expected otherwise
   1  | + sent


Result: 2 document(s) with 2 testcase(s): 0 succeeded, 2 failed and 0 skipped
[50]
```

## With --jobs, documents run at the same time, reported in their order

```scrut
$ rm -f "$SIGNAL_FILE"; "$SCRUT_BIN" test --jobs 2 --match-markdown "*.mdtest" "$TESTDIR/first.mdtest" "$TESTDIR/second.mdtest"
// =============================================================================
// @ *first.mdtest:4 (glob)
// -----------------------------------------------------------------------------
// # Waits up to two seconds for the second document
// -----------------------------------------------------------------------------
// $ for i in $(seq 20); do [ -e "$SIGNAL_FILE" ] && break; sleep 0.1; done; echo "signal: $(cat "$SIGNAL_FILE" 2>/dev/null || echo none)"
// =============================================================================

1     | - signal: expected otherwise
   1  | + signal: from the second document


// =============================================================================
// @ *second.mdtest:4 (glob)
// -----------------------------------------------------------------------------
// # Sends the signal the first document waits for
// -----------------------------------------------------------------------------
// $ echo "from the second document" > "$SIGNAL_FILE" && echo sent
// =============================================================================

1     | - expected otherwise
   1  | + sent


Result: 2 document(s) with 2 testcase(s): 0 succeeded, 2 failed and 0 skipped
[50]
```

## Documents can't share a user provided work directory

```scrut
$ "$SCRUT_BIN" test --jobs 2 --work-directory "$TMPDIR" --match-markdown "*.mdtest" "$TESTDIR/first.mdtest" 2>&1
* ERROR scrut: Error: --jobs greater than 1 can't be combined with --work-directory (glob)
[1]
```

## update with --jobs writes every document

```scrut
$ cp "$TESTDIR/first.mdtest" "$TESTDIR/second.mdtest" .
```

```scrut
$ rm -f "$SIGNAL_FILE"; "$SCRUT_BIN" update --jobs 2 --replace --assume-yes --match-markdown "*.mdtest" first.mdtest second.mdtest
Result: 2 document(s) of which 2 updated, 0 skipped and 0 unchanged
```

````scrut
$ cat first.mdtest second.mdtest
# Waits up to two seconds for the second document

```scrut
$ for i in $(seq 20); do [ -e "$SIGNAL_FILE" ] && break; sleep 0.1; done; echo "signal: $(cat "$SIGNAL_FILE" 2>/dev/null || echo none)"
signal: from the second document
```
# Sends the signal the first document waits for

```scrut
$ echo "from the second document" > "$SIGNAL_FILE" && echo sent
sent
```
````

## update can't share a user provided work directory either

```scrut
$ "$SCRUT_BIN" update --jobs 2 --work-directory "$TMPDIR" --match-markdown "*.mdtest" first.mdtest 2>&1
* ERROR scrut: Error: --jobs greater than 1 can't be combined with --work-directory (glob)
[1]
```
