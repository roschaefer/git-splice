# Scenario: nested-splices

One splice inside another. Every command refuses this.

- **Monorepo**: `vendor/pkg` and `vendor/pkg/extra`, each with a
  `.splice`.

The outer splice's content includes the inner one, so pushing `vendor/pkg`
would publish `vendor/pkg/extra` too.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_nested_splices
```

```scrut
$ git splice status
!!   nested splices are not supported: 'vendor/pkg' and 'vendor/pkg/extra' overlap -- remove one of their .splice files
[1]
```

Removing one `.splice` fixes it:

```scrut
$ git rm -q vendor/pkg/extra/.splice && git commit -q -m "vendor/pkg/extra is part of vendor/pkg"
```

```scrut
$ git splice status
ok   vendor/pkg -> main (push: ahead 2)
```
