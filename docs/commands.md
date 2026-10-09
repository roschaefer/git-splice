# Commands

`merge`, `pull` and `push` change the monorepo or an upstream, so they name
their splices, or take `--all`. `clone` and `init` start one splice each.
Commands that only look cover every splice unless you name some. Run `git splice <command> --help` for options.

## Commands named after Git's

Each does to a splice what its Git namesake does to a repository.

| Command | What it does |
| --- | --- |
| `clone <url> [<path>]` | Splices an existing repository into a new folder, as one commit. Use `--merge` if the folder already exists and differs. |
| `init <path> <url>` | Makes a folder a splice of a new, empty repository. The first `push` starts the upstream at the init commit; the folder's earlier history stays in the monorepo. |
| `merge [--bump] <path>…` | Splices already-fetched upstream changes in, as one ordinary commit per splice. Works like `git merge --squash`, done internally with a cherry-pick: on a conflict, `git status` shows a cherry-pick in progress. `--bump` also records the upstream branch in `.splice` when there's nothing to merge, e.g. right after a push ([walkthrough](../test/walkthrough/bump.md)). |
| `pull [--bump] <path>…` | `fetch` + `merge`, with `--bump` as for `merge`. Also fetches the splices nested in each, whose synced commits a pull can move. |
| `push <path>…` | Rebuilds the commits that changed each splice since the last sync and pushes them upstream. Writes nothing to the monorepo. |
| `status [path…]` | Shows each splice's [sync state](sync-states.md), with how many commits `push` would publish and `pull` would bring in. |
| `diff [--stat] [path…]` | Shows the file changes `push` would send; `--stat` summarizes them per file. |
| `log [--graph] [path…]` | Shows the commits `push` would publish and `pull` would bring in, with their authors; `--graph` draws both sides as a graph. |
| `rebuild <path>` | Prints the commit `push` would send, without pushing it: to push it to another upstream branch, e.g. `git push <url> "$(git splice rebuild <path>)":refs/heads/release`, or to check it out in a separate worktree. Writes nothing. |
| `fetch [path…]` | Fetches every branch of each upstream into `refs/splices/<key>/`, under the upstream's key in this repository, e.g. `lib` for `https://github.com/x/lib.git`. |

A splice can have several upstreams, e.g. a company fork and the
original it follows
([several-upstreams](../test/scenarios/several-upstreams/README.md)).
`--upstream <name>` picks one for `fetch`, `merge`, `pull`, `push`,
`status`, `diff`, `log` and `key`. Without it, commands use the splice's
`default-upstream`, which `.splice` needs once it names several; `fetch`
fetches all of them. A splice that lacks the named upstream stops the
command before it starts
([missing upstream names](../test/scenarios/several-upstreams/missing-upstream-names.md)).

`status`, `diff`, `log` and `merge` only use what was last fetched. Run
`git splice fetch` first if you need the latest upstream state. Fetched
upstreams can be read with any Git command, e.g.
`git log splices/lib/main`.

Upstreams are fetched and pushed by URL, with no Git remote, so a plain
`git push` can't send the whole monorepo to one by mistake
([more](design/README.md#refs-instead-of-remotes)). A `push` creates a
new upstream branch only if the splice changed on your branch
([more](design/README.md#splicing-out-push-and-the-rebuild)).

## Commands new to git splice

Their names come from splicing; Git has no command of that name.

| Command | What it does |
| --- | --- |
| `boundary <path>` | Prints the splice boundary: the monorepo commit where a splice last synced, the last commit that changed its `.splice`, e.g. the last `pull`. It answers "when was the library last spliced in?" Like a boundary commit of `git log --boundary`, it starts the range of the folder's commits since then: `git log B..HEAD -- <path>`. |
| `key [--upstream <name>] <path> [<new-key>]` | Prints the key of a splice's upstream, or renames it, refs included. |

A nested splice has two boundaries. In the monorepo, `boundary` prints
where the monorepo last synced it, often a pull of the splice above.
Where the upstream above last synced it is a commit of that upstream:
check out a fetched commit of it in a worktree, and run `boundary` there
with the path in that upstream, e.g. `b` for `vendor/a/b`:

    git worktree add --detach ../a refs/splices/a/main
    git -C ../a splice boundary b
