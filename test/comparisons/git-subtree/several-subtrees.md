# Several subtrees braid the history

With `--rejoin`, every push of a subtree merges into the monorepo
([`--rejoin`](rejoin.md)). Each subtree rejoins on its own, so with
several of them the merges braid the history, and each keeps a line of
its own in it.

The setup: [the comparisons' monorepo](../README.md), and three
sub-repositories, `x`, `y` and `z`, with a commit each:

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```

```scrut
$ for r in x y z; do
>   command git init -q "../$r-work" &&
>     echo "$r" >"../$r-work/README" &&
>     command git -C "../$r-work" add README &&
>     command git -C "../$r-work" commit -q -m "$r commit 1" &&
>     command git clone -q --bare "../$r-work" "../upstream/$r.git" || break
> done
```
-->

```scrut
$ git branch before-lib &&
>   for r in x y z; do
>     git subtree add -q --squash --prefix="vendor/$r" "https://git.example.com/$r.git" main >/dev/null || break
>   done
```

Two rounds of work, each a commit that fixes all three, then a `split
--rejoin` for each of them, always in the same order:

```scrut
$ for round in 1 2; do
>   for r in x y z; do echo "fix $round" >>"vendor/$r/README"; done &&
>     git commit -q -a -m "fix $round in x, y and z" &&
>     for r in x y z; do
>       git subtree split -q --rejoin --squash --prefix="vendor/$r" >/dev/null || break
>     done
> done
```

```scrut
$ git log --graph --format=%s before-lib..
*   Split 'vendor/z/' into commit 'a23fe6cee22c6fdbc440a11fc2ce954826b2deb1'
|\  
| * Squashed 'vendor/z/' changes from a524acb..a23fe6c
* |   Split 'vendor/y/' into commit '52d3a5cb51b6fa042700f2dba609afc8c255abe9'
|\ \  
| * | Squashed 'vendor/y/' changes from a9a463c..52d3a5c
* | |   Split 'vendor/x/' into commit '938ea9da1c9567fce25d56be0faae7e490e6c8ce'
|\ \ \  
| * | | Squashed 'vendor/x/' changes from 35e1621..938ea9d
* | | | fix 2 in x, y and z
* | | |   Split 'vendor/z/' into commit 'a524acb25444b320bfc62258031115aa4d659ca9'
|\ \ \ \  
| | |_|/  
| |/| |   
| * | | Squashed 'vendor/z/' changes from edb382f..a524acb
* | | |   Split 'vendor/y/' into commit 'a9a463c55f67c27b6b2e94303251381fe5d91686'
|\ \ \ \  
| | |_|/  
| |/| |   
| * | | Squashed 'vendor/y/' changes from 0e92a20..a9a463c
* | | |   Split 'vendor/x/' into commit '35e16213fcec3efdea8588461c9eb3e989c03050'
|\ \ \ \  
| | |_|/  
| |/| |   
| * | | Squashed 'vendor/x/' changes from f12e751..35e1621
* | | | fix 1 in x, y and z
* | | |   Merge commit '23b17e1f3d39bf541f3660542d0c615ab841d018' as 'vendor/z'
|\ \ \ \  
| | |_|/  
| |/| |   
| * | | Squashed 'vendor/z/' content from commit edb382f
|  / /  
* | |   Merge commit 'f854e45c340a9b97ba671c849e70eac63f2186b5' as 'vendor/y'
|\ \ \  
| | |/  
| |/|   
| * | Squashed 'vendor/y/' content from commit 0e92a20
|  /  
* / Merge commit '70c4706aabccfd407af9602c403f367906a9fbb6' as 'vendor/x'
|/  
* Squashed 'vendor/x/' content from commit f12e751
```

Each `Squashed` commit has the one before it, of the same
sub-repository, as its parent, below the other two sub-repositories'
rejoins. So its line crosses theirs, and the same braid, `| |_|/` over
`| |/| |`, repeats for every rejoin, for as long as the order stays the
same. Each sub-repository keeps a line of its own, open for the whole
history:

<div align="center">

![The monorepo's a, sX, sY, sZ, b, jX1, jY1, jZ1, c, jX2, jY2 and jZ2 in a line; below it a row for each sub-repository, with qX, rX1 and rX2, qY, rY1 and rY2, and qZ, rZ1 and rZ2, each the second parent of the monorepo commit above it, and the arrows from y and z cross the rows above them](git-subtree-rejoin-three.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/git-subtree-rejoin-three.drawio.svg" --alias HEAD=H \
>   a=before-lib sX=HEAD~10 sY=HEAD~9 sZ=HEAD~8 b=HEAD~7 \
>   jX1=HEAD~6 jY1=HEAD~5 jZ1=HEAD~4 c=HEAD~3 jX2=HEAD~2 jY2=HEAD~1 jZ2=HEAD \
>   qX=HEAD~10^2 qY=HEAD~9^2 qZ=HEAD~8^2 rX1=HEAD~6^2 rY1=HEAD~5^2 rZ1=HEAD~4^2 \
>   rX2=HEAD~2^2 rY2=HEAD~1^2 rZ2=HEAD^2
ok   git-subtree-rejoin-three.drawio.svg: 21 commits, 27 arrows, 1 boxes
```
-->

None of these merges says anything about the app. They're there so that
`split` stays fast. Splices sync one commit at a time, and the
monorepo's history stays a line, however many there are.
