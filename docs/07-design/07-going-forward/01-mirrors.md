# Mirrors

Mirrors are folders with the same splice
[id](../../03-concepts/03-splice-identity.md), meant to have the same
files. `git-splice` syncs each path independently.

`git splice status` and `git splice push` report when mirrors' files or
`.splice` differ in `HEAD`, naming the other mirrors; push still pushes.
Git can't keep the copies alike, and nesting limits what `git-splice`
could enforce, so it states the fact and refuses nothing. A different
upstream URL shows as a different `.splice`, though it can mean the
repository moved.

## Nested mirrors can lag behind

Mirrors arise from copying a folder, or from two upstreams bringing in
the same nested `.splice`. Separate clones get separate ids, even when
they use the same URL.

![Two apps contain the same library at separate paths; each copy belongs to its app's upstream](nested-copies.svg)

If the apps inherited the library's id, those copies are mirrors. One
app may still use an older library. Updating its nested copy changes the
app too; the monorepo cannot make that decision for the app's upstream.

A pull could update copies owned directly by the monorepo together.
It cannot promise that every nested mirror will match.

## Shared storage does not mean a shared folder

Git already stores identical files and trees once. Its checkout writes
every copy. A filesystem with copy-on-write can share disk blocks while
keeping separate files.

A symlink would change the meaning: the app's repository would contain
a link outside itself instead of the library's files. It would also stop
copies from differing while work is in progress.

## Meanwhile: discipline

Edit one copy, push it, then pull the others, and record the push in
the copy that made it with `git splice pull --bump`; `status` then
reports no difference. Clone a copy that should have its own history. The
[mirrors scenario](../../09-scenarios/07-moved-folders/03-mirrors/README.md)
shows how to compare copies and resolve drift, and why
[swapping their paths](../../09-scenarios/07-moved-folders/03-mirrors/swapped-paths.md)
can send unexpected history upstream: the push warns, and still sends it.
