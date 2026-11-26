#!/usr/bin/env bash
# Usage: bats-shard.sh SHARD SHARDS
#
# Prints the bats files of shard SHARD (1-based) out of SHARDS. Each file goes
# to the shard with the fewest tests so far, the biggest files first, so the
# shards get about the same number of tests. The test count stands in for the
# time: on the suite of 2026-11-26 it gave three shards within 5% of each
# other's time, and it can't go stale like a list of measured times.
set -euo pipefail

shard="$1"
shards="$2"

grep -c '^@test' docs/tests/*.bats check-drawing/tests/*.bats |
  sort -t: -k2,2nr -k1,1 |
  awk -F: -v shard="$shard" -v shards="$shards" '
    {
      least = 1
      for (i = 2; i <= shards; i++) if (tests[i] < tests[least]) least = i
      tests[least] += $2
      if (least == shard) print $1
    }
  '
