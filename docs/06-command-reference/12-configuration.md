# .spliceconfig

Commit a `.spliceconfig` to share command defaults and checkpoint handlers.
It uses Git's configuration syntax:

```ini
[splice]
    messageTemplate = "chore(deps): {command} {path}"

[splice "pull"]
    recursive = true
    exec = ./scripts/check-update
```

`[splice]` provides defaults for commands that support the option.
`[splice "pull"]`, `[splice "fetch"]` and other command sections limit a
setting to that command. For ordinary options at one directory, command-specific settings take
precedence over shared settings, regardless of their order in the file.

Keys correspond to command-line options, using camelCase for multiword names:
`messageTemplate`, `noForkPoint`, `fromSubmodule`, `noTrack`. Value options such
as `branch`, `upstream` and `messageTemplate` take strings. Flags such as
`recursive`, `bump`, `force` and `track` take Git-style boolean values.
A command consumes only the options its CLI supports. Unknown keys and
settings for other commands are ignored. Positional paths, `continueFrom` and
`rebuiltCommit` are invocation inputs, not configuration defaults.

The same argument validation applies to configured options. For example,
tracking still requires a branch, and bump and rebase cannot be combined.
Explicit CLI options take precedence over defaults; `-m` overrides a configured
message template. Explicit paths override a configured `all` default.

Use Git to edit the file, then commit it:

```fish
git config --file .spliceconfig splice.pull.recursive true
git config --file .spliceconfig splice.messageTemplate 'chore(deps): {command} {path}'
git add .spliceconfig
git commit -m 'chore(config): share splice defaults'
```

## Recursive scope

Configuration is read from committed files, not the index or worktree.
For `vendor/a/b`, the tool reads the files at the repository root, `vendor/`,
`vendor/a/` and `vendor/a/b/`, in that order. A nearer setting overrides an
inherited setting; an explicit CLI option overrides both.

A nested `.spliceconfig` applies to that splice and the splices inside it.
For example, `vendor/a/.spliceconfig` can set a message template or an upstream
branch for `vendor/a` and its children without changing siblings. A nested
`recursive = false` stops configured descent there; an explicit CLI
`--recursive` takes precedence.

A parent pull can change its children's configuration without changing their
`.splice` files. The tool rereads their effective settings and fetches again
when needed before proceeding with the children.

## Configured hooks

`exec` uses the same JSON checkpoint interface as
[`--exec`](13-shared-options/01-exec/README.md). It is supported by fetch, pull and push.
Configured hooks run automatically; no CLI `--exec` is needed.

- Inherited handlers run outermost first, then handlers from inner directories.
- Repeated `exec` entries add handlers. An empty `exec` clears inherited handlers
  for that scope; subsequent entries add new ones.
- An explicit CLI `--exec` replaces the configured chain for that invocation.
- Each configured handler runs in the directory containing its `.spliceconfig`.
  CLI handlers run at the repository root.
- `hook_scope` identifies that directory, relative to the repository root.
  For a fetch checkpoint, each handler receives only the fetched entries that
  inherit it. A shared handler runs once for the batch, not once per entry.

For example, `scripts/check-update` can run a build only after a merge:

```sh
#!/bin/sh
payload=$(cat)
checkpoint=$(printf '%s\n' "$payload" | jq -r .event.checkpoint)
if [ "$checkpoint" = after-merge ] && ! make >&2; then
    printf '%s\n' "$payload"
    exit 1
fi
```

A root LFS downloader and a nested build handler can coexist: the root handler
can act on `after-fetch`, while the nested handler acts on `after-merge`.
The [LFS prototype](../09-scenarios/04-upstreams/08-lfs-upstream/01-cloned-by-hand/01-retrained-upstream/with-exec.md)
commits the downloader and its `exec` configuration, then uses plain pull,
fetch and push commands.

For `after-fetch`, applicable incoming configuration is also read directly
from fetched commits, before checkout. The nearest fetched splice's file takes
precedence, followed by its fetched ancestors and the committed local file.
This lets an incoming LFS handler download objects before files are checked
out. Configuration introduced by a parent pull governs subsequent child work.

Committed `exec` values are executable project policy. Running fetch, pull or
push can execute commands from nested upstream configuration, including before
that configuration is checked out. Git configuration `include` directives are
not followed; recursive scope comes from `.spliceconfig` files themselves.

## Continuation

A stopped handler can emit its payload as usual. For configured handlers,
continue without specifying a script again:

```fish
git splice pull --continue-from ../checkpoint.json
```

Continuation consumes the stopped handler and then runs the remaining handlers
at that checkpoint before proceeding. It remembers their committed source
revisions and the unfiltered event, so a stop in one subtree does not lose work
for another. Verify or repair a failed check before continuing: the stopped
handler itself is not retried.

If the invocation used CLI `--exec`, supply it again. Scripts are not restored
from command strings in the payload; configured handlers are resolved from their
saved committed sources. Changes to committed `.spliceconfig` files invalidate
continuation, as changes to `.splice` files do. Push still requires unchanged
HEAD. The existing restriction on execution checkpoints with `--rebase` also
applies to configured hooks; scoped rebase cannot be mixed into a checkpoint
operation.
