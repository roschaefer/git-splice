# Scenario: pushing LFS files to their splice upstreams

Two splices store `model.bin` in Git LFS, each on its own upstream's LFS
server. The checkpoint script downloads both updates. Local changes to those
models then travel back to their respective upstream repositories with
`git splice push --all`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_GLOBAL="$PWD/.gitconfig" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$PWD/monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git LFS_SCRIPT="$TESTDIR/../lfs-fetch.sh" && git lfs install --skip-repo >/dev/null
```
-->

[`setup.bash`](setup.bash) builds two splices, initially checked out as LFS
pointers. Both upstreams have a newer model; the monorepo has its own remote:

```scrut
$ build_scenario scenario_push_to_upstreams
```

The [checkpoint script](../lfs-fetch.sh) fetches each model from the URL in
that splice's payload entry before the merge checks it out:

```scrut
$ git splice pull --all --exec 'bash "$LFS_SCRIPT"'
ok   vendor/a fetched (main moved 18f6ff7..5552501)
ok   vendor/b fetched (main moved 9d56a01..5a7a4a2)
LFS: fetching vendor/a at 18f6ff7
Fetching reference 18f6ff741703f6844f109ec36d34b161ce5a7367
LFS: fetching vendor/a at 5552501
Fetching reference 55525014b6c5eb225bffbd792c75628d83fa799f
LFS: fetching vendor/b at 5a7a4a2
Fetching reference 5a7a4a2a082d626b0cd0558c7f475bb52910fd3b
LFS: fetching vendor/b at 9d56a01
Fetching reference 9d56a0105d0e5ef28fc3cbb9fab420832bd52beb
ok   vendor/a: pulled 5552501
ok   vendor/b: pulled 5a7a4a2
```

```scrut
$ cat vendor/a/model.bin vendor/b/model.bin
weights, version 2
b weights, version 2
```

Change both models locally and commit them. Git LFS's clean filter stores
new objects in the local cache and records pointers in the commit:

```scrut
$ printf 'a weights, trained locally\n' >vendor/a/model.bin && printf 'b weights, trained locally\n' >vendor/b/model.bin && git add vendor/a/model.bin vendor/b/model.bin && git commit -qm 'train both models locally'
```

`push --all` sends each splice's rebuilt history to its own upstream. Git
LFS's existing `pre-push` hook uploads the new content to the corresponding
LFS server. The checkpoint script is needed for downloading before merge;
uploads use that ordinary hook:

```scrut
$ git splice push --all
ok   vendor/a: pushed 28493f7 to main
ok   vendor/b: pushed 27024cd to main
```

Fresh upstream clones prove that both the Git pointers and their LFS content
arrived at the right repositories. They contain neither the monorepo prefix
nor the other splice's model:

```scrut
$ git clone -q "file://$UPSTREAM" ../a-clone && cat ../a-clone/model.bin
a weights, trained locally
```

```scrut
$ git clone -q "file://$UPSTREAM-b.git" ../b-clone && cat ../b-clone/model.bin
b weights, trained locally
```

The monorepo can also publish both files to its own LFS server. A colleague's
plain clone gets both local changes without running the checkpoint script:

```scrut
$ git push -q origin main && git clone -q https://git.example.com/monorepo.git ../colleague && cat ../colleague/vendor/a/model.bin ../colleague/vendor/b/model.bin
a weights, trained locally
b weights, trained locally
```
