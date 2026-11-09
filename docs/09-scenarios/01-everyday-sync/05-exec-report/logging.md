# Scenario: logging execution checkpoints

`--exec` can append every checkpoint payload to a JSON-lines log. The command
returns zero, so fetch, pull and push continue normally. Logging happens at
the same boundaries used for inspection and continuation.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds a splice whose upstream has an update:

```scrut
$ build_scenario scenario_exec_report
```

`jq -c .` reads the payload from stdin and writes one complete JSON object
per line. Save it outside the worktree so logging does not create changes in
the repository:

```scrut
$ git splice fetch --exec 'jq -c . >>../splice-events.jsonl' vendor/a
ok   vendor/a fetched
```

Use the same command during pull:

```scrut
$ git splice pull --exec 'jq -c . >>../splice-events.jsonl' vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 6045a98
```

Make a local change, then log its publication too:

```scrut
$ printf 'local change\n' >>vendor/a/file.txt && git add vendor/a/file.txt && git commit -qm 'local change'
```

```scrut
$ git splice push --exec 'jq -c . >>../splice-events.jsonl' vendor/a
ok   vendor/a: pushed eda2ac7 to main
```

The log contains five checkpoints. Sequence numbers start at one for each
invocation:

```scrut
$ jq -r '"\(.operation)#\(.sequence): \(.event.checkpoint)"' ../splice-events.jsonl
fetch#1: after-fetch
pull#1: after-fetch
pull#2: after-merge
push#1: after-rebuild
push#2: after-push
```

Find which splice changed without parsing human-readable diagnostics:

```scrut
$ jq -r 'select(.event.checkpoint == "after-merge") | .event.path' ../splice-events.jsonl
vendor/a
```

Every record keeps the repository snapshot and continuation context, rather
than only the summary above:

```scrut
$ jq -s 'all(.[]; (.repository.head | type) == "string" and (.continuation | type) == "object")' ../splice-events.jsonl
true
```

Logging left the working tree clean:

```scrut
$ git status --short
```

This records completed checkpoints, not every internal Git command. Errors
before a checkpoint are still reported through normal diagnostics. A logger
that fails also stops execution, following the ordinary `--exec` contract.
