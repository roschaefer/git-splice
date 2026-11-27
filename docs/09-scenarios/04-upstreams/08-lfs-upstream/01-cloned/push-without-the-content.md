# cloned: push without the content here

A colleague adds a file stored in Git LFS to the splice, and pushes the
monorepo. `git splice push` uploads the content from the local LFS store,
so it needs the content here. A checkout normally downloads it from the
monorepo's LFS server; one with `GIT_LFS_SKIP_SMUDGE=1` doesn't, and the
push fails until plain Git LFS downloads it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_GLOBAL="$PWD/.gitconfig" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$PWD/monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git && git lfs install --skip-repo >/dev/null
```
-->

[`setup.bash`](setup.bash) builds the state of [`README.md`](README.md):

```scrut
$ build_scenario scenario_cloned
```

The colleague's clone of the monorepo adds `rules.bin` to the splice,
and its push uploads the content to the monorepo's LFS server:

```scrut
$ git clone -q https://git.example.com/monorepo.git ../colleague
```

```scrut
$ cd ../colleague && echo "rules, version 1" >vendor/a/rules.bin && git add vendor/a/rules.bin && git -c user.name=Colleague -c user.email=colleague@example.com commit -q -m "add the rules" && git push -q origin main && cd - >/dev/null
```

This monorepo pulls the commit without the content:

```scrut
$ GIT_LFS_SKIP_SMUDGE=1 git pull -q origin main
```

```scrut
$ git splice push vendor/a
Git LFS upload failed:
  (missing) rules.bin (a3f7781bfe7ed96e5c83f8e43b302f7a1721dd5873ae08837248f16f34b7f463)
hint: Your push was rejected due to missing or corrupt local objects.
hint: You can disable this check with: `git config lfs.allowincompletepush true`
error: failed to push some refs to 'file://$UPSTREAM'
!!   vendor/a: push failed
!!   Failed: vendor/a
[1]
```

Plain Git LFS downloads the content from the monorepo's LFS server:

```scrut
$ git lfs fetch origin main
Fetching reference refs/heads/main
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 7836dc5 to main
```

and a clone of the upstream gets the file:

```scrut
$ git clone -q "file://$UPSTREAM" ../upstream-clone && cat ../upstream-clone/rules.bin
rules, version 1
```
