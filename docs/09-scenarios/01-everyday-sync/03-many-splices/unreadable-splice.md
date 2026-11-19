# One `.splice` can't be read

`git-splice` reads each splice's `.splice` with `git config`. A typo, a
committed conflict marker or a `.splice` that `git-crypt` encrypted
([#56](https://github.com/roschaefer/git-splice/issues/56)) leave one it
can't read. Today that stops every command, also the ones for the other
splices
([#57](https://github.com/roschaefer/git-splice/issues/57)).

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

<div align="center">

![Monorepo commits a to g, and one lane per splice: cli up to date, http behind by m and n, parser ahead by f prime, store diverged with o and g prime, theme up to date](many-splices.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/many-splices.drawio.svg" \
>   a=HEAD~6 b=HEAD~5 c=HEAD~4 d=HEAD~3 e=HEAD~2 f=HEAD~1 g=HEAD \
>   m=refs/splices/upstream-http/heads/main~1 n=refs/splices/upstream-http/heads/main \
>   o=refs/splices/upstream-store/heads/main
ok   many-splices.drawio.svg: 17 commits, 20 arrows, 9 boxes, 5 lanes
```
-->

A hand edit of `libs/http/.splice` gives a key a space, which `git config`
doesn't allow:

```scrut
$ echo "  default branch = main" >>libs/http/.splice &&
>   git commit -q -am "h: set the default branch by hand"
```

<div align="center">

![Monorepo commits a to h, and one lane per splice: cli up to date, http empty, as its .splice can't be read, parser ahead by f prime, store diverged with o and g prime, theme up to date](unreadable-splice.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/unreadable-splice.drawio.svg" \
>   a=HEAD~7 b=HEAD~6 c=HEAD~5 d=HEAD~4 e=HEAD~3 f=HEAD~2 g=HEAD~1 \
>   o=refs/splices/upstream-store/heads/main
!!   f': no such commit
!!   g': no such commit
!!   o is in the lane libs/store/, but isn't in that splice's upstream history or R
!!   seed is solid, but no upstream branch has it: dash it
!!   seed is solid, but no upstream branch has it: dash it
!!   seed is solid, but no upstream branch has it: dash it
!!   o is solid, but no upstream branch has it: dash it
!!   seed is solid, but no upstream branch has it: dash it
!!   f is outlined in color, but the rebuild doesn't carry it across: outline it black
!!   g is outlined in color, but the rebuild doesn't carry it across: outline it black
!!   T points at seed, but there's no T
!!   R points at seed, but there's no R
!!   T points at seed, but there's no T
!!   R points at f', but there's no R
!!   seed -> o is solid, but no upstream branch has o: dash it
!!   T points at o, but there's no T
!!   R points at g', but there's no R
!!   T points at seed, but there's no T
!!   R points at seed, but there's no R
[1]
```
-->

```scrut
$ git splice status
!!   libs/http/.splice can't be read (bad config line 6 in blob HEAD:libs/http/.splice) -- fix it and commit it
[1]
```

```scrut
$ git splice fetch
!!   libs/http/.splice can't be read (bad config line 6 in blob HEAD:libs/http/.splice) -- fix it and commit it
[1]
```

```scrut
$ git splice diff libs/parser
!!   libs/http/.splice can't be read (bad config line 6 in blob HEAD:libs/http/.splice) -- fix it and commit it
[1]
```

```scrut
$ git splice push libs/http
!!   libs/http/.splice can't be read (bad config line 6 in blob HEAD:libs/http/.splice) -- fix it and commit it
[1]
```
