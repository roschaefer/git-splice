#!/bin/sh
# A hook for 'git splice pull --exec': after pull fetches the upstreams'
# commits and before it merges them, download the Git LFS content of the
# branches it fetched, from each upstream's own LFS server.
set -e
test "$GIT_SPLICE_EVENT" = after-fetch || exit 0

git ls-files -- '*/.splice' | while read -r file; do
  path="${file%/.splice}"
  git config --file "$file" --get-regexp '^upstream\..*\.url$' |
    while read -r name url; do
      upstream="${name#upstream.}"
      upstream="${upstream%.url}"
      key="$(git splice key --upstream "$upstream" "$path")"
      git for-each-ref --format='%(refname)' "refs/splices/$key/heads/" |
        xargs -r git lfs fetch "$url"
    done
done
