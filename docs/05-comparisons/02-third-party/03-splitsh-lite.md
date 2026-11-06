# splitsh-lite compared

[`splitsh-lite`](https://github.com/splitsh/lite) is a faster
[`git subtree split`](../01-git/02-git-subtree.md#problem-2-with---squash-split-walks-everything):
its README says it "replaces the `subtree split` Git built-in command",
gives the same commits, and keeps a cache of the commits it has split.

It publishes a monorepo's folders as "read-only standalone
repositories". Changes only go out: a fix made in a published repository
has to be made again in the monorepo. So it can't keep a library in sync
both ways, which is what `git-splice` is for.
