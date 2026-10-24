# init

`git splice init <path> <url>`

Makes a folder of the monorepo a splice of a new, empty repository. The
first `push` starts the upstream at the init commit; the folder's
earlier history stays in the monorepo.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

In the [walkthrough's repositories](README.md), `libs/c/` grew inside the monorepo, and
`lib-c.git` is empty:

```scrut
$ git splice init libs/c https://git.example.com/lib-c.git
ok   libs/c: initialized -- 'git splice push libs/c' publishes it
```

```scrut
$ git splice push libs/c
??   libs/c: upstream has no 'main' branch yet -- this push creates it
ok   libs/c: pushed 9dc1e6a to main
```

```scrut
$ git -C "$WALKTHROUGH/upstream/lib-c.git" log --format=%s main
splice: init libs/c
```

## More

- Why the folder's history before `init` stays in the monorepo:
  [init-new-upstream](../scenarios/02-starting-a-splice/04-init-new-upstream/README.md).
- In a fresh clone of the monorepo, commands treat the upstream as empty
  until the first `fetch`, a known bug
  ([init-then-cloned](../scenarios/02-starting-a-splice/05-init-then-cloned/README.md)).
