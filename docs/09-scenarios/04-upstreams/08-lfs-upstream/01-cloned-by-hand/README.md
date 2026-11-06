# Scenario: cloned-by-hand

`push` of a splice that stores files in Git LFS works: Git LFS's own
`pre-push` hook runs on the `git push` that `git splice push` runs, and
uploads the content to the upstream's LFS server.

- **Monorepo (`vendor/a/`)**: [cloned by hand](../clone-by-hand.md)
  from an upstream that stores `model.bin` in Git LFS, and pushed to its
  own remote.
- **Upstream** (`file://$UPSTREAM`): as cloned.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_GLOBAL="$PWD/.gitconfig" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$PWD/monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git && git lfs install --skip-repo >/dev/null
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_cloned_by_hand
```

A new `.bin` file in the splice is stored in Git LFS, as the upstream's
`.gitattributes` says. The commit has a pointer to its content:

```scrut
$ echo "rules, version 1" >vendor/a/rules.bin && git add vendor/a/rules.bin && git commit -q -m "add the rules"
```

```scrut
$ git show HEAD:vendor/a/rules.bin
version https://git-lfs.github.com/spec/v1
oid sha256:a3f7781bfe7ed96e5c83f8e43b302f7a1721dd5873ae08837248f16f34b7f463
size 17
```

`push` uploads the content along with the commit:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 59a22e3 to main
```

and a clone of the upstream gets the file:

```scrut
$ git clone -q "file://$UPSTREAM" ../upstream-clone && cat ../upstream-clone/rules.bin
rules, version 1
```
