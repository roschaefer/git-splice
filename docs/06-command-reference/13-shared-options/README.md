# Shared options

These options appear on more than one command. Their shared reference lives
here; command pages retain their help text and command-specific examples.

| Option | Commands | Reference |
|---|---|---|
| `--exec` | fetch, pull, push | [Handlers and checkpoints](01-exec/README.md), [JSON payload](01-exec/01-json-payload.md), [continuation](01-exec/02-continue-from.md). |
| `--rebuilt-commit` | merge, push | [Bring back content changes or publish edited history](02-rebuilt-commit.md). |
| `--recursive` | pull, clone --from-submodule | [Which nested operations run, and how they finish](03-recursive.md). |

Committed [`.spliceconfig`](../12-configuration.md) supplies defaults for
supported options and inherits through nested directories. Explicit command-line
options take precedence. The individual references explain which operations
support each option; sharing a spelling does not make the operations identical.
