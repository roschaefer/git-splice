#!/bin/sh
# A hook for 'git splice pull --exec': prints at each checkpoint how many
# splices the pull is done with, from the JSON on its stdin.
jq -r '([.event.name, .event.path // empty] | join(" "))
  + ": \([.tasks.splices[] | select(.task == "done")] | length)"
  + " of \(.tasks.splices | length) done"'
