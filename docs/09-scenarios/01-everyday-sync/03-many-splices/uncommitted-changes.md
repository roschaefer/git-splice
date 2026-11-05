# Status with uncommitted changes

`status`, like every command, reads the splices from the last commit, and
`push` only sends what is committed. So uncommitted changes in a splice's
folder need attention even where the splice itself has nothing
to do: such a splice moves up, out of the quiet group, with a note.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_many_splices
```

```scrut
$ echo "work in progress" >> libs/cli/file.txt
```

```scrut
$ echo "more work" >> libs/parser/file.txt
```

```scrut
$ git splice status
On branch main

  ahead 1, behind 1  libs/store
  behind 2           libs/http
  ahead 1            libs/parser  uncommitted changes
  up to date         libs/cli     uncommitted changes

  up to date         libs/theme -> master
```
