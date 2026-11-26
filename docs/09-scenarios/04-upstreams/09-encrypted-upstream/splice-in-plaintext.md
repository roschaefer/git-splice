# encrypted-upstream: the `.splice` in plaintext

> **Limitation.** This page shows behaviour `git-splice` keeps on purpose, and the way out. See [known bugs and limitations](../../99-known-bugs.md#limitations).

`git-splice` reads a splice's `.splice` without git-crypt's key, so the
`.splice` stays out of the filter that encrypts the upstream's files
([encrypted-upstream](README.md#keeping-the-splice-in-plaintext)).
Whoever can read the monorepo, key or not, reads the `.splice`, and the
upstream's URL in it. Keep nothing secret in that URL.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_encrypted_upstream
```

The monorepo splices in the encrypted upstream and leaves the `.splice`
out of the filter:

```scrut
$ git splice clone -m "b: clone vendor/a" https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned df2d9fc from main
```

```scrut
$ echo '.splice !filter !diff' >>vendor/a/.gitattributes &&
>   git commit -q -a -m "c: keep .splice in plaintext"
```

A clone of the monorepo without the key:

```scrut
$ git clone -q --no-local . ../no-key
```

has the secret encrypted: it has no line of plaintext.

```scrut
$ grep "secret, version" ../no-key/vendor/a/secret.txt
[1]
```

The `.splice` is plaintext, the upstream's URL included:

```scrut
$ cat ../no-key/vendor/a/.splice
[splice]
	id = c18fbadcfc2f7536
	commit = df2d9fc121601502d647bc53724fe260cd12ddcc
[upstream "origin"]
	url = https://git.example.com/a.git
```
