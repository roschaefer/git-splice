# Writing the docs

Run `just docs-check` to test every page. After an intended change, run
`just docs-check --write` to update their output.

Markup in running text tells a reader what kind of thing a word names:
the commit *a*, not the English word "a". Each kind gets one markup,
everywhere.

| What | Markup | Examples |
| --- | --- | --- |
| Anything you can type or `git-splice` prints: commands, options, paths, files, branches, refs (`HEAD` too), config keys, variables, hashes, commit subjects, status output, the tool's name | `monospace` | `git splice push`, `--force`, `.splice`, `main`, `HEAD`, `refs/splices/<key>/`, `$UPSTREAM`, `e849115`, `add vendor/a`, `ahead 1`, `git-splice` |
| A commit, named as a drawing names it, or a variable for one | *italic* | *a*, *d'*, *X* |
| A role: our name for whichever commit plays a part, as `HEAD` names the checked-out one | plain capitals | H, B, T, R |
| Git's name for a part in a three-way merge, which the README uses for a role | *italic*, lowercase | *boundary*, *base*, *ours*, *theirs* |
| A formula | plain, nothing inside marked up | U(H), U(X^), U(e), tracked(feature) |
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
- Page titles, image alt text, labels in a drawing and code blocks get
  no markup.

## Words Git uses too

Git uses "upstream" and "tracking" for several things. Here each word
means one:

- **Upstream** is the repository a splice comes from, and an *upstream
  branch* is one of its branches. Git's upstream branch, the one
  `@{upstream}` names, is a *tracked branch* here.
- **Tracked branch** is the upstream branch that `--track` set for a
  monorepo branch, in `branch.<branch>.splice`; tracked(X) in a formula.
  Never "tracking branch": Git says that for the local branch, and it's
  easily mistaken for a remote-tracking branch. A tracked branch is no
  ref, only a name.
- **Remote-tracking branch** keeps Git's meaning only, a ref like
  `refs/remotes/origin/main`. The refs `git splice fetch` writes,
  `refs/splices/<key>/heads/*`, work like them, but are *splice refs*.

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
- A config file, `.splice` or `.gitmodules`, is shown whole with `cat`,
  as a reader would see it, not picked apart with `git config --list`.
  Its upstream is reached as an `https://git.example.com/…` URL that
  `url.<path>.insteadOf` maps to `$UPSTREAM`, so the URL and the splice
  id stay the same on every run. `scrut update` writes the file's tabs
  as `\t… (escaped)`: turn them back into tabs.
- A drawing's [`check_drawing`](../check-drawing/) goes in a hidden
  block (`<!--` … `-->`): it keeps the drawing true, but a reader
  learns nothing from it. Only a page that explains the check itself,
  like its `--alias`, shows it.
- A drawing with a legend says what the next rebuild does with a
  commit: an orange outline (`#E07000`) for a change it carries across,
  on both ends, a commit R copies and its copy, and, where the number
  of commits it walks matters, a grey fill (`#E0E0E0`) for the monorepo
  commits on the first-parent history since B. The legend, a shape
  styled `legend=1` below the drawing, shows a sample commit for each
  mark the drawing's commits use, orange, grey, dashed or a `'`, with
  what it means. Without a legend, every commit is black and white.
  `check_drawing` checks the marks against the legend, as it checks the
  dashes. A drawing of another tool uses them the same way, for the
  commits that tool walks and the ones it carries over, e.g.
  `git subtree split`, with a legend in its words; there
  `check_drawing` can't check them.
- A drawn commit the page makes starts its subject with its label,
  `b: an option in pkg-a`, and a pull or bump gets one with `-m`. The
  output then shows the labels, so the prose doesn't need to name each
  commit's subject. `<label>=<rev>` is for the rest: a rebased or copied
  commit, which keeps another one's message, a commit the shared setup
  makes, and a commit on a branch other than `HEAD`.
