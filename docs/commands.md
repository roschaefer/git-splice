# Commands

`merge`, `pull` and `push` change the monorepo or an upstream, so they name
their splices, or take `--all`. `clone` and `init` start one splice each.
Commands that only look cover every splice unless you name some. Run `git splice <command> --help` for options.

| Command | What it does |
| --- | --- |
| `clone <url> [<path>]` | Splices an existing repository into a new folder, as one commit. Use `--merge` if the folder already exists and differs. |
| `init <path> <url>` | Makes a folder a splice of a new, empty repository. The first `push` publishes its history. |
| `merge <path>…` | Splices already-fetched upstream changes in, as one ordinary commit per splice. |
| `pull <path>…` | `fetch` + `merge`. |
| `push <path>…` | Rebuilds the commits that changed each splice since the last sync and pushes them upstream. Writes nothing to the monorepo. |
| `status [path…]` | Shows each splice's [sync state](sync-states.md). |
| `diff [path…]` | Shows the file changes `push` would send. |
| `log [path…]` | Shows the commits `push` would publish and `pull` would bring in, with their authors. |
| `fetch [path…]` | Fetches every branch of each upstream into `refs/splices/<path>/`. |

`status`, `diff`, `log` and `merge` only use what was last fetched. Run
`git splice fetch` first if you need the latest upstream state. Fetched
upstreams can be read with any Git command, e.g.
`git log splices/vendor/lib/main`.

Upstreams are fetched and pushed by URL, with no Git remote, so a plain
`git push` can't send the whole monorepo to one by mistake
([more](design/README.md#refs-instead-of-remotes)). A `push` creates a
new upstream branch only if the splice changed on your branch
([more](design/README.md#splicing-out-push-and-the-rebuild)).
