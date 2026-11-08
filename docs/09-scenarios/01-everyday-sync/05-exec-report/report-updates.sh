#!/bin/sh
jq -r 'select(.event.checkpoint == "after-merge") |
  "\(.event.path): \(.event.new[0:7])"' >>../updated-splices.txt
