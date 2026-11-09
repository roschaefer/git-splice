# Scenario: inspect a JSON payload and continue

A handler can save the complete payload and stop. Read its event and repository
state, then pass that same file back to continue. This scenario shows the JSON
from actual fetch and merge checkpoints; it does not construct a sample object.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds a splice behind its upstream:

```scrut
$ build_scenario scenario_exec_report
```

The handler copies stdin to stdout and exits nonzero. Save stdout outside the
worktree, and keep normal diagnostics in a separate file. `command git` bypasses
the documentation helper that otherwise combines the two output streams:

```scrut
$ command git splice pull --exec 'cat; exit 1' vendor/a >../checkpoint.json 2>../checkpoint.log
[1]
```

The saved file has every top-level field, including the opaque continuation:

```scrut
$ jq 'keys' ../checkpoint.json
[
  "continuation",
  "event",
  "hook_scope",
  "operation",
  "repository",
  "result",
  "sequence",
  "version"
]
```

For readability, this view omits the continuation and repository guard strings,
and replaces the fixture's temporary upstream URL and monorepo commit IDs with
labels. The saved file itself is unchanged. This projection is not suitable
for continuation:

```scrut
$ jq '{version, operation, sequence, hook_scope, event: (.event | .fetched |= map(.url = "<upstream>")), repository: (.repository | {head: "<before>", branch}), result}' ../checkpoint.json
{
  "version": 1,
  "operation": "pull",
  "sequence": 1,
  "hook_scope": "",
  "event": {
    "checkpoint": "after-fetch",
    "fetched": [
      {
        "path": "vendor/a",
        "upstream": "origin",
        "url": "<upstream>",
        "reference": "refs/splices/upstream/heads/main",
        "old": "6045a986b5afb475cd0af0caf6bb622db918a25b",
        "new": "6045a986b5afb475cd0af0caf6bb622db918a25b",
        "synced": "bde416459fbcc09c9b585f3b65a94cab3f68bfcd",
        "failed": false
      }
    ]
  },
  "repository": {
    "head": "<before>",
    "branch": "main"
  },
  "result": {
    "rebuilt_commit": null
  }
}
```

The real saved snapshot still matches HEAD:

```scrut
$ git rev-parse HEAD | jq -R --slurpfile payload ../checkpoint.json '$payload[0].repository.head == .'
true
```

The fixture already fetched the upstream, so `old` and `new` are equal here.
A fetch checkpoint still runs. The checked-out file has not changed:

```scrut
$ cat vendor/a/file.txt
seed
```

The event is `after-fetch`, while the saved engine phase is the work that
comes next:

```scrut
$ jq -r '.continuation.phase' ../checkpoint.json
merging
```

Continue using the complete file, saving the next payload to a different file:

```scrut
$ command git splice pull --continue-from ../checkpoint.json --exec 'cat; exit 1' >../after-merge.json 2>../checkpoint.log
[1]
```

The merge has now happened. Show its event with the same display labels for
the temporary URL and monorepo commits:

```scrut
$ jq '{operation, sequence, event: (.event | .url = "<upstream>" | .head_before = "<before>" | .head_after = "<after>"), head: "<after>"}' ../after-merge.json
{
  "operation": "pull",
  "sequence": 2,
  "event": {
    "checkpoint": "after-merge",
    "path": "vendor/a",
    "upstream": "origin",
    "url": "<upstream>",
    "old": "bde416459fbcc09c9b585f3b65a94cab3f68bfcd",
    "new": "6045a986b5afb475cd0af0caf6bb622db918a25b",
    "target": "6045a986b5afb475cd0af0caf6bb622db918a25b",
    "rebuilt_commit": "bde416459fbcc09c9b585f3b65a94cab3f68bfcd",
    "head_before": "<before>",
    "head_after": "<after>"
  },
  "head": "<after>"
}
```

The monorepo HEAD equals the event's `head_after`, and its checked-out content
includes the upstream update:

```scrut
$ jq '.repository.head == .event.head_after and .event.head_before != .event.head_after' ../after-merge.json
true
```

```scrut
$ cat vendor/a/file.txt
seed
upstream change
```

One more continuation consumes that stopped handler and finishes. It does not
repeat the merge or invoke that handler again:

```scrut
$ command git splice pull --continue-from ../after-merge.json --exec 'cat; exit 1' >../finished.json 2>../checkpoint.log
```

```scrut
$ test ! -s ../finished.json && git status --short
```

The [payload reference](../../../06-command-reference/13-shared-options/01-exec/01-json-payload.md)
describes every public field. For a recursive operation with intermediate tree
diagrams, continue with the
[top-down walkthrough](../../05-nested-splices/05-recursion/01-recursive-pull/discovered-top-down.md#a-recursive-pull).
