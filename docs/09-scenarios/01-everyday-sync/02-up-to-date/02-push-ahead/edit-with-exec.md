# Scenario: editing a rebuilt commit before push

A push checkpoint can hand its rebuilt history to an external script before
publishing it. Here a script rewords the one local commit, returns the new
commit in the payload, and stops. Continuation validates the edited history
and publishes it without changing the monorepo's commit.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export PUSH_SCRIPT="$TESTDIR/reword-push.sh"
```
-->

[`setup.bash`](setup.bash) builds a splice with one local change:

```scrut
$ build_scenario scenario_push_ahead
```

The [script](reword-push.sh) acts only at `after-rebuild`. It keeps the tree
and parent of that commit, writes a new message, and sets the explicit result
field. Other payload fields are preserved:

```scrut
$ cat "$PUSH_SCRIPT"
#!/usr/bin/env bash
set -euo pipefail

payload=$(cat)
if [[ $(jq -r .event.checkpoint <<<"$payload") == after-rebuild ]]; then
  rebuilt=$(jq -r .event.rebuilt_commit <<<"$payload")
  edited=$(printf 'reviewed history\n' |
    git commit-tree "$(git rev-parse "$rebuilt^{tree}")" -p "$(git rev-parse "$rebuilt^1")")
  jq --arg commit "$edited" '.result.rebuilt_commit = $commit' <<<"$payload"
  exit 1
fi
```

Call Git directly here because the documentation's `git` wrapper combines
stdout and stderr. The script's JSON goes to its own file; diagnostics go
to a separate log. A nonzero script status pauses before any upload:

```scrut
$ command git splice push --exec 'bash "$PUSH_SCRIPT"' vendor/a >../push.json 2>../push.log
[1]
```

```scrut
$ jq -r .event.checkpoint ../push.json
after-rebuild
```

The upstream is unchanged:

```scrut
$ git -C "$UPSTREAM" log -1 --format=%s main
seed
```

The payload has both the prepared commit and the script's proposed replacement:

```scrut
$ git show -s --format=%s "$(jq -r .event.rebuilt_commit ../push.json)" && git show -s --format=%s "$(jq -r .result.rebuilt_commit ../push.json)"
local change
reviewed history
```

Resume with the whole payload and the same script. Only history may change:
validation follows `--rebuilt-commit`, requiring the folder's committed files
and the synced ancestor unless the original push specified `--force`.
The consumed `after-rebuild` script is skipped; the next checkpoint is
`after-push`, which this script ignores:

```scrut
$ git splice push --continue-from ../push.json --exec 'bash "$PUSH_SCRIPT"'
ok   vendor/a: pushed f9053ba to main
??   vendor/a: run 'git splice pull --bump vendor/a' before the next change to it -- that records f9053ba as the synced commit
```

```scrut
$ git -C "$UPSTREAM" log -1 --format=%s main
reviewed history
```

The monorepo keeps its original commit message:

```scrut
$ git log -1 --format=%s
local change
```

As with `--rebuilt-commit`, record the edited history as the synced commit
before making the next change. Then another push has nothing to do and calls
no checkpoint script:

```scrut
$ git splice pull --bump vendor/a
ok   vendor/a fetched
ok   vendor/a: recorded f9053ba as the synced commit -- the folder already has its files
```

```scrut
$ git splice push --exec 'exit 99' vendor/a
ok   vendor/a: nothing to push
```

To inspect a successful upload instead, a script can stop at `after-push`.
That upload stays applied; continuation advances to the next splice without
pushing it again. Push continuation requires unchanged monorepo HEAD.
