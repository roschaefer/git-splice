# Writing the docs

Markup in running text tells a reader what kind of thing a word names:
the commit *a*, not the English word "a". Each kind gets one markup,
everywhere.

| What | Markup | Examples |
| --- | --- | --- |
| Anything you can type or `git-splice` prints: commands, options, paths, files, branches, refs (`HEAD` too), config keys, variables, hashes, commit subjects, status output, the tool's name | `monospace` | `git splice push`, `--force`, `.splice`, `main`, `HEAD`, `refs/splices/<key>/`, `$UPSTREAM`, `e849115`, `add vendor/a`, `ahead 1`, `git-splice` |
| A commit: a node in a drawing, or a variable for one | *italic* | *a*, *d'*, *X* |
| A role: our name for whichever commit plays a part, as `HEAD` names the checked-out one | plain capitals | BOUNDARY, BASE, OURS, THEIRS; H, B, T, R |
| A formula | plain, nothing inside marked up | U(H), U(X^), U(e) |
| A splice | its folder, with a trailing slash | `vendor/a/` |
| A repository | words, never a letter | the monorepo, the upstream of `vendor/a/` |
| A term, where it's defined | *italic*, only there | a splice's history starts at its *mount* |
| Emphasis, and the label that starts a list item or table row | **bold** | **Not prevented yet.** |

A few details:

- A command keeps its spelling, `git splice push`; the tool is
  `git-splice`. A path given as an argument stays as typed:
  `git splice push vendor/a`.
- A commit's subject goes next to its name: *a* (`add vendor/a`).
- Roles need no markup: no English word is written in capitals, so they
  already stand out. A role you type, like `BOUNDARY` for
  `check_drawing --alias`, is literal there.
- An upstream can also go by its variable or URL in a scenario:
  `$UPSTREAM-b`, `https://git.example.com/b.git`. With one splice inside
  another, they're the outer and the inner upstream; an app and the
  library it splices in are the app's upstream and the library's.
- Page titles, image alt text and code blocks get no markup.

## Commands in scrut blocks

Each step a reader would type gets its own line. A scrut command goes on
from its `$ ` line to the `> ` lines below it:

```text
$ git clone -q https://git.example.com/lib.git ../lib-dev &&
>   echo "fix" >>../lib-dev/src/parse.txt &&
>   git -C ../lib-dev commit -q -a -m "fix parse()"
```

- A chain ends each step with `&&` and indents the next one by two
  spaces. Commands that don't depend on each other go on `> ` lines
  without the indent, instead of after a `;`. Within a step, what a
  `|` pipes into is indented by two more than the step.
- A block shows the output of one step: its last. A reader can't tell
  where one step's output ends and the next one's begins, so a step
  that prints something ends its block, and the next step starts a new
  one.
- A command with many arguments breaks with `\`, and keeps an option
  next to its value.
- A `$(…)` inside another command gets a name first, one from the page
  where there is one: `k="$(…)" && git diff --quiet "$k" …`.
- A script, for `sh -c` or a file, is a heredoc, one command per line.
- A loop over a few fixed steps is written out step by step.
- A drawing's [`check_drawing`](../check-drawing/) goes in a hidden
  block (`<!--` … `-->`): it keeps the drawing true, but a reader
  learns nothing from it. Only a page that explains the check itself,
  like its `--alias`, shows it.
