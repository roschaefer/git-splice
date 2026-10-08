# Nesting

A splice can be inside another one: its upstream may use git splice
itself. Then the splice below is **nested** in the splice above.

The nested `.splice` is part of the files of the splice above, like any
other file there. So it travels with them: a clone or pull of the splice
above brings it into the monorepo, and a push of the splice above sends
it to that upstream, where it is a splice again
([nested-splices](../../scenarios/nested-splices/README.md)). A splice's
own push leaves its own `.splice` out.

Because the splice below is contained in the files above, not referred
to, some rules follow:

- **Order.** `merge` and `pull` go top-down: pulling the splice above can
  move the synced commit of the one below. `push` goes bottom-up: the
  push above sends the `.splice` below, which must not name content its
  upstream doesn't have
  ([design](../../../docs/design/README.md#splicing-in-merge-and-pull--fetch--merge)).
- **History.** The splice above was squashed into one commit when it was
  cloned or pulled. So the history of the splice below, up to that
  point, is taken from the upstream above, which has it
  ([spliced-elsewhere](../../scenarios/nested-splices/spliced-elsewhere.md)).
- **Default branch.** A nested `.splice` without `default-branch` follows
  the branch of the splice above, so it means the same in the monorepo
  and in the upstream above
  ([nested-default-branch](../../scenarios/nested-default-branch/README.md)).

Two shapes need a closer look, as in a package manager's dependency
graph:

- [**Diamond**](diamond.md): two paths lead to one library. Allowed:
  the monorepo has a copy per path. Copies of one splice are mirrors,
  which can drift apart
  ([mirrors](../../../docs/going-forward/mirrors.md)).
- [**Cycle**](cycle.md): a splice contains itself. Forbidden: the copies
  would never end.
