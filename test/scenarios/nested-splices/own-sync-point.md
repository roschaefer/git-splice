# Scenario: nested-splices, spliced elsewhere, with its own sync point

What [spliced-elsewhere](spliced-elsewhere.md) would look like if the
other monorepo recorded its own sync point for b, instead of using the
one that came along in b's `.splice`. Here it's recorded by hand. A
`clone` that did it itself would fix
[#74](https://github.com/roschaefer/git-splice/issues/74).

The steps up to the clone are the same as in spliced-elsewhere. The
monorepo pushes a change in b, then another monorepo splices a in. b's
files there already have the change, but b's `.splice` names the synced
commit from before it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Other GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=other@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
a with b spliced in at `b/`, cloned into the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local" && git splice push vendor/a/b vendor/a
ok   vendor/a/b: pushed f47c373 to main
ok   vendor/a: pushed 3c57040 to main
```

## Another monorepo splices a in

```scrut
$ git init -q -b main ../other && cd ../other && git commit -q --allow-empty -m "other monorepo"
```

```scrut
$ git splice clone "$UPSTREAM" vendor/a && git splice fetch
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned 3c57040 from main
ok   vendor/a fetched
ok   vendor/a/b fetched
```

b's `.splice` names `b seed`, but b's files are those of b's upstream
`main`, `b local`:

```scrut
$ git log -1 --format=%s "$(git config --file vendor/a/b/.splice splice.commit)"
b seed
```

```scrut
$ git -C "$UPSTREAM-b.git" log -1 --format='%h %s' main
f47c373 b local
```

## Record b's own sync point

Set b's synced commit to the upstream commit that has exactly b's files:

```scrut
$ git config --file vendor/a/b/.splice splice.commit "$(git ls-remote https://git.example.com/b.git main | cut -f1)" && git commit -q -am "record b's sync point"
```

b is up to date. But a is now ahead: b's `.splice` is a's content, so
a's next push would publish this monorepo's sync point for b to a's
upstream, where it may be stale for the next monorepo again. Keeping the
sync point out of the `.splice` that travels would avoid that.

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 1)
ok   vendor/a/b -> main (up to date)
```

## The first change to b

```scrut
$ echo "b other" >>vendor/a/b/file.txt && git commit -q -a -m "b other"
```

Unlike in spliced-elsewhere, b isn't diverged: the rebuild starts at the
commit the upstream has, and only `b other` is new.

```scrut
$ git splice status vendor/a/b
ok   vendor/a/b -> main (push: ahead 1)
```

```scrut
$ git splice log vendor/a/b
===  vendor/a/b (main)
< f123e09 b other  (Other <other@example.com>)
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed f123e09 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" log --format=%s main
b other
b local
b seed
```
