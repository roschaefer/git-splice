# check-help

`check-help` keeps each command's terminal help and command-reference page
in the same shape. A help section ends with the page section that expands it:

```text
DESCRIPTION
    Short explanation for the terminal.

    See also: https://roschaefer.github.io/git-splice/test/walkthrough/push/#description
```

The page heading replaces the help heading and supplies the anchor. Below it,
the page prints the help section's body without repeating the final link, then
continues it with examples, drawings and links:

````markdown
## Description

```text
$ git splice push -h | check-help section description
    Short explanation for the terminal.
```
````

The page's hidden final block passes the whole document to `check-help
document`. It fails when the help links and level-two headings differ, their
order differs, a link points to another command's page, or a section has no
visible extraction command. Scrut checks the extracted text itself against
the real `--help` output.

An option with its own `###` expansion puts an indented `See also` link at
the end of that option and uses `check-help option <anchor>`. `check-help
section options` leaves linked options out, so their help text appears only
beside the additional documentation; options without an expansion remain in
the general `Options` section.

`check-help preamble` prints `NAME` and `SYNOPSIS`, before the first linked
section. The section and option extractors omit the heading and terminal-only
link because the page heading replaces both. `cargo build` puts the tool in
`target/debug/`, alongside `git-splice`, for `just docs-check`.
