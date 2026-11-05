# Nested splices

Upstreams that use `git-splice` themselves, see
[nesting](../../03-concepts/05-nesting/README.md).

- [nested-splices](01-nested-splices/README.md): one splice inside
  another, brought along by cloning the outer one.
- [nested-default-branch](02-nested-default-branch/README.md): a nested
  `.splice` without `default-branch`.
- [diamond](03-diamond/README.md): two apps splice in the same library,
  and the monorepo has it a third time.
- [cycle](04-cycle/README.md): an upstream that splices in the monorepo
  itself.
