# Scenario: default-branch, misspelled

The state of the [README](README.md), with `default-branch` misspelled
in `.splice`. Git's config format lets a file have any key, so
`git-splice` reads the file without the misspelled key, and each command
names the key it doesn't know.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds the state of the README:

```scrut
$ build_scenario scenario_default_branch https://git.example.com/a.git
```

```scrut
$ sed -i 's/default-branch/defualt-branch/' vendor/a/.splice &&
>   git commit -q -m "misspell default-branch" vendor/a/.splice
```

```scrut
$ cat vendor/a/.splice
[splice]
	id = 224f2c2563d3b6f7
	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
[upstream "origin"]
	url = https://git.example.com/a.git
	defualt-branch = master
```

Without `default-branch`, the splice follows the monorepo's `main`,
which the upstream doesn't have:

```scrut
$ git splice status
??   vendor/a/.splice: unknown key upstream.origin.defualt-branch -- the keys are splice.id, splice.commit, splice.default-upstream, upstream.<name>.url, upstream.<name>.default-branch, upstream.<name>.default-pin
On branch main

  new, ahead 2  vendor/a  push creates the branch
```
