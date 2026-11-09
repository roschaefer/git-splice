# Scenario: LFS downloads through a committed hook

A proof of concept for LFS support through a committed `.spliceconfig` hook:
fetch the large-file objects from each splice's upstream before Git tries to check out the update.
The monorepo and upstream have separate LFS servers. The new model exists
only on the upstream's server.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh" && export GIT_CONFIG_GLOBAL="$PWD/.gitconfig" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$PWD/monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git LFS_SCRIPT="$TESTDIR/../../lfs-fetch.sh" && git lfs install --skip-repo >/dev/null
```
-->

[`setup.bash`](setup.bash) builds the same state as the
[failing pull](README.md): the monorepo has version 1 of `model.bin`, and
upstream has version 2.

```scrut
$ build_scenario scenario_retrained_upstream
```

```scrut
$ cat vendor/a/model.bin
weights, version 1
```

## Before configuring the hook

A plain pull fetches the Git commits but fails to obtain the model's content
from the monorepo's LFS server. Save the full diagnostics and show the cause:

```scrut
$ git splice pull vendor/a >../without-exec.log 2>&1
[1]
```

```scrut
$ grep 'smudge filter lfs failed' ../without-exec.log
fatal: vendor/a/model.bin: smudge filter lfs failed
```

Restore the files left by the failed checkout before trying the script:

```scrut
$ git checkout -q -- vendor/a
```

## Commit the hook

The [proof-of-concept script](../../lfs-fetch.sh) reads `event.fetched`, using
the upstream URLs and commit IDs that git-splice supplies. It downloads the
new and synced versions so a later push also has the old content referenced
by the monorepo's history. It ignores the other checkpoints.

```scrut
$ cat "$LFS_SCRIPT"
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
```

`git lfs fetch` writes its progress to stderr here, leaving stdout available
for the complete continuation payload if a download fails. In that case the
script exits nonzero, stopping before the merge. The caller must complete
the download before continuing, since continuation skips the stopped script.

Copy the handler into the monorepo and commit it with its configuration.
The command is relative to the root `.spliceconfig`, so it also works in a
fresh clone without the scenario's `LFS_SCRIPT` environment variable:

```scrut
$ mkdir -p .splice-hooks && cp "$LFS_SCRIPT" .splice-hooks/lfs-fetch.sh &&
>   git config --file .spliceconfig splice.exec 'bash .splice-hooks/lfs-fetch.sh' &&
>   git add .spliceconfig .splice-hooks/lfs-fetch.sh &&
>   git commit -qm 'chore(lfs): configure splice downloads'
```

```scrut
$ git config --blob HEAD:.spliceconfig splice.exec
bash .splice-hooks/lfs-fetch.sh
```

No `--exec` flag is needed on subsequent commands:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
LFS: fetching vendor/a at 18f6ff7
Fetching reference 18f6ff741703f6844f109ec36d34b161ce5a7367
LFS: fetching vendor/a at 3752e56
Fetching reference 3752e56315abb62859005b6a3386891625e43cac
ok   vendor/a: pulled 3752e56
```

The LFS downloads happen between the Git fetch and the merge. Git's normal
smudge filter then finds the new content in its local cache:

```scrut
$ cat vendor/a/model.bin
weights, version 2
```

The working tree is clean:

```scrut
$ git status --short
```

A normal push uploads the content to the monorepo's own LFS server. A colleague
can then clone it without git-splice or the checkpoint script:

```scrut
$ git push -q origin main
```

```scrut
$ git clone -q https://git.example.com/monorepo.git ../colleague && cat ../colleague/vendor/a/model.bin
weights, version 2
```

The handler and its default are committed too:

```scrut
$ test -f ../colleague/.splice-hooks/lfs-fetch.sh && git -C ../colleague config --blob HEAD:.spliceconfig splice.exec
bash .splice-hooks/lfs-fetch.sh
```

## Push a local model back upstream

Train the model locally and commit it. This new content does not exist on
upstream yet:

```scrut
$ printf 'weights, version 3, trained locally\n' >vendor/a/model.bin && git add vendor/a/model.bin && git commit -qm 'train the model locally'
```

`git splice push` uploads the new LFS content through Git LFS's ordinary
`pre-push` hook, together with the splice's rebuilt history. The configured
handler ignores `after-rebuild` and `after-push`; uploads use the native hook:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed d940207 to main
```

A fresh clone of the splice repository receives the actual model, not just
its pointer:

```scrut
$ git clone -q "file://$UPSTREAM" ../upstream-colleague && cat ../upstream-colleague/model.bin
weights, version 3, trained locally
```

[Two splices with separate upstreams](../../02-push-to-upstreams/README.md)
show the same round trip for both models using `git splice push --all`.

## Fetch and merge separately

The committed hook also handles plain `git splice fetch`. Publish another
model from the upstream clone:

```scrut
$ printf 'weights, version 4, trained upstream\n' >../upstream-colleague/model.bin &&
>   git -C ../upstream-colleague add model.bin &&
>   git -C ../upstream-colleague -c user.name=Test -c user.email=test@example.com commit -qm 'train upstream again' &&
>   git -C ../upstream-colleague push -q origin main
```

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched (main moved d940207..f91d607)
LFS: fetching vendor/a at 3752e56
Fetching reference 3752e56315abb62859005b6a3386891625e43cac
LFS: fetching vendor/a at f91d607
Fetching reference f91d60778bacdf2238f8c30352b975bbadd5e104
```

Fetch downloads the new content without changing the checked-out model:

```scrut
$ cat vendor/a/model.bin
weights, version 3, trained locally
```

```scrut
$ git splice merge vendor/a
ok   vendor/a: merged f91d607
```

```scrut
$ cat vendor/a/model.bin
weights, version 4, trained upstream
```

This is a configured prototype for ordinary upstream URLs. It does not add LFS
support to clone or configure custom upstream `.lfsconfig` endpoints, and
fetching these two commits is not a complete historical-object migration.
