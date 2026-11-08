# Scenario: a user-defined update report

An external script can choose its own work at a checkpoint. Here it appends
the path and upstream commit of each updated splice to a report outside the
repository. The report could feed a release checklist; git-splice only sends
the context and checks the script's exit status.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export REPORT_SCRIPT="$TESTDIR/report-updates.sh"
```
-->

[`setup.bash`](setup.bash) builds a monorepo whose splice is behind upstream:

```scrut
$ build_scenario scenario_exec_report
```

The script, [report-updates.sh](report-updates.sh), reads the JSON payload
from stdin. It selects only `after-merge` events, ignoring fetches and folding, and chooses which fields to report:

```scrut
$ cat "$REPORT_SCRIPT"
#!/bin/sh
jq -r 'select(.event.checkpoint == "after-merge") |
  "\(.event.path): \(.event.new[0:7])"' >>../updated-splices.txt
```

`--exec` interprets its command through `sh`, regardless of the interactive
shell. This script uses `jq` to read JSON. It returns zero when there is no
matching event, so the operation continues.

A standalone fetch calls the script with `operation: "fetch"` and an
`after-fetch` event. It updates refs, without merging or changing files:

```scrut
$ git splice fetch --exec 'sh "$REPORT_SCRIPT"' vendor/a
ok   vendor/a fetched
```

There is nothing to report yet:

```scrut
$ test ! -s ../updated-splices.txt
```

Pull calls the same script after fetching and after applying the update.
Only the merge appends a line:

```scrut
$ git splice pull --exec 'sh "$REPORT_SCRIPT"' vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 6045a98
```

```scrut
$ cat ../updated-splices.txt
vendor/a: 6045a98
```

Running it again changes nothing, so it adds no duplicate report entry:

```scrut
$ git splice pull --exec 'sh "$REPORT_SCRIPT"' vendor/a
ok   vendor/a fetched
ok   vendor/a: nothing to pull
```

```scrut
$ wc -l <../updated-splices.txt
1
```

The report is the script's own logic. To replace it with a build, notification
or another local action, keep reading the payload and select the events that
matter to that action. A nonzero exit stops the operation; a script that wants
to save a continuation must write the complete payload before exiting.
