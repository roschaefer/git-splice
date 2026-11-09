# --recursive

Pulling nested splices and converting nested submodules both proceed top-down,
because the operation above determines what exists below. The same flag has
command-specific effects:

| Command | Work below the named path | Result |
|---|---|---|
| `pull --recursive` | Pulls the nested splices, including ones introduced by a parent pull. | One resulting commit per named root when the run finishes successfully. |
| `clone --from-submodule --recursive` | Converts the submodule's nested submodules too. | One commit per conversion. |

## Pull

The parent is pulled before its children. Their `.splice` files, upstreams and
configuration are reread from that result. Children added during the pull are
fetched before their updates are applied; removed children are not pulled.
A failed fetch or merge blocks dependent work.

Successful recursive updates are folded by named root. The root's own pull
message is followed by the child pull messages. If a conflict interrupts the
run, resolve it, commit and run pull again; already-applied updates are skipped.
`pull --all` uses this recursive behavior for every top-level splice.
If intervening commits are not pull commits, the tool explains why it leaves
the commits separate instead of folding them.

See the [command-specific reference](../05-pull.md#--recursive),
[recursive pull scenario](../../09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/README.md),
and [top-down discovery](../../09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/discovered-top-down.md).

With [`--exec`](01-exec/README.md), the repository is observable between these
steps. The [pause/diagram/resume walkthrough](../../09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/discovered-top-down.md#a-recursive-pull)
checks a real intermediate tree before continuing, rather than replaying a
previous run's refs. Handler stops use [continuation](01-exec/02-continue-from.md);
Git conflicts use the normal conflict workflow.

## Clone from submodules

With `--from-submodule`, recursively convert the submodule's own submodules
into splices. URLs and settings come from the parent `.gitmodules`; relative
URLs are relative to that parent's upstream. Earlier conversions remain if
a child is refused, and the diagnostic names the child command to retry.

The upstream parent still contains gitlinks. The next push publishes the
conversion there too; if its owners intend to retain submodules, convert in a
fork. Read [clone's reference](../01-clone.md#--recursive) before converting.
This operation does not expose `--exec` checkpoints.

Committed [configuration](../12-configuration.md#recursive-scope) can supply
recursive defaults for supported commands. Explicit CLI `--recursive` wins over
configured defaults.
