# Status in a fresh clone

A clone of the monorepo, like one from a server, has every splice, but none of their upstreams'
branches: `git splice fetch` brings them in. Until then, `status` marks
every splice with `??`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_many_splices
```

```scrut
$ git clone -q --no-local "$PWD" ../fresh && cd ../fresh
```

```scrut
$ git splice status
On branch main

  ?? never fetched  libs/cli              run 'git splice fetch libs/cli'
  ?? never fetched  libs/http             run 'git splice fetch libs/http'
  ?? never fetched  libs/parser           run 'git splice fetch libs/parser'
  ?? never fetched  libs/store            run 'git splice fetch libs/store'
  ?? never fetched  libs/theme -> master  run 'git splice fetch libs/theme'
```

```scrut
$ git splice fetch
ok   libs/cli fetched
ok   libs/http fetched
ok   libs/parser fetched
ok   libs/store fetched
ok   libs/theme fetched
```

```scrut
$ git splice status
On branch main

  ahead 1, behind 1  libs/store
  behind 2           libs/http
  ahead 1            libs/parser

  up to date         libs/cli
  up to date         libs/theme -> master
```
