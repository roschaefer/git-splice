# Concepts

What `git-splice` keeps, and how it decides what to pull and push. The
[advanced workflows](../04-advanced-workflows/README.md) build on these.

- [The `.splice` file](01-splice-file/README.md): what makes a folder a
  splice. It names the upstream and the commit the folder last synced
  with.
- [Upstreams](02-upstreams/README.md): the repositories a splice fetches
  from and pushes to.
- [Sync model](03-sync-model/README.md): the folder's two histories, the
  monorepo's and the upstream's, and how changes cross between them.
- [Splice identity](04-splice-identity/README.md): the id in each
  `.splice`, for when a path can't identify a splice.
- [Nesting](05-nesting/README.md): an upstream that uses `git-splice`
  itself brings its splices along.
