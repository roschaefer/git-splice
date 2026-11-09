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
