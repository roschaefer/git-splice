#!/usr/bin/env bash
set -euo pipefail

payload=$(cat)
if [[ $(jq -r .event.checkpoint <<<"$payload") != after-fetch ]]; then
  exit 0
fi

if ! jq -r '.event.fetched[] | select(.failed == false) | . as $entry |
  [.new, .synced] | unique[] | select(. != null and . != "") |
  [$entry.path, $entry.url, .] | @tsv' <<<"$payload" |
  while IFS=$'\t' read -r path url commit; do
    printf 'LFS: fetching %s at %s\n' "$path" "${commit:0:7}" >&2
    git lfs fetch --include= --exclude= -- "$url" "$commit" >&2 || exit 1
  done; then
  printf '%s\n' "$payload"
  exit 1
fi
