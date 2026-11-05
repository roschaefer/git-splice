# Command reference

One page per command. Each page has the sections of the command's
`git splice <command> -h`, with examples that run.

- [`status`](01-status.md): show each splice's sync state.
- [`clone`](02-clone.md): splice an existing repository into the
  monorepo.
- [`fetch`](03-fetch.md): fetch splice upstreams.
- [`log`](04-log.md): show commits push and pull would move.
- [`merge`](05-merge.md): splice in fetched upstream changes.
- [`pull`](06-pull.md): fetch and splice in upstream changes.
- [`diff`](07-diff.md): show the changes push would send.
- [`push`](08-push.md): publish local splice changes upstream.
- [`init`](09-init.md): make an existing folder a splice of an empty
  repository.
- [`boundary`](10-boundary.md): print where a splice's rebuild starts.
- [`rebuild`](11-rebuild.md): print the commit push would send.
- [`key`](12-key.md): print or rename an upstream's key.
