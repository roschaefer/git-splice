# Execution Model

A Scrut [test document](/docs/reference/fundamentals/test-document/) can contain arbitrary amounts of [test cases](/docs/reference/fundamentals/test-case/). Scrut provides a shared execution environment for all executions from a single document, which results in certain behaviors and side-effects that should be known:

## Shared Shell Environment

Each subsequent [test case](/docs/reference/fundamentals/test-case/) in the same document inherits the shell environment of the previous [test case](/docs/reference/fundamentals/test-case/). This means: All environment variables, shell variables, aliases, functions, etc that have been set in one [test case](/docs/reference/fundamentals/test-case/) are available to the immediate following [test case](/docs/reference/fundamentals/test-case/).
- E.g. `export FOO=bar` in one [test case](/docs/reference/fundamentals/test-case/) will still be set in the following [test case](/docs/reference/fundamentals/test-case/).
- *Exception*: Environments set in [`detached`](/docs/reference/fundamentals/inline-configuration/) [test cases](/docs/reference/fundamentals/test-case/) are not inherited.

## Shared Ephemeral Directories

Each [test cases](/docs/reference/fundamentals/test-case/) in the same document executes in the the same [working directory](/docs/reference/behavior/working-directory/) and is provided with the same temporary directory ([`$TEMPDIR`](/docs/reference/fundamentals/environment-variables/)). Both directories will be removed (cleaned up) after test execution - independent of whether the test execution succeeds or fails.

- *Exception*: If the `--work-directory` command-line parameter is provided, then this directory will not be cleaned up (deleted) after execution. A temporary directory, that still will be removed after execution, will be created within the working directory.

## Process Isolation

Scrut starts individual `bash` processes for executing each [shell expression](/docs/reference/fundamentals/shell-expression/) of each [test case](/docs/reference/fundamentals/test-case/) in the same document. The environment of the previous execution is pulled in through a shared `state` file, that contains all environment variables, shell variables, aliases, functions and settings as they were set when the the previous [test case](/docs/reference/fundamentals/test-case/) execution ended.

:::warning Markdown vs Cram

[Markdown](/docs/reference/formats/markdown-format/) is the default Scrut [test document](/docs/reference/fundamentals/test-document/) format. [Cram](/docs/reference/formats/cram-format/) is supported for legacy reasons. Hence it's legacy mode of execution is also respected. The main difference in Cram from the above is:

> Each execution from the same [test document](/docs/reference/fundamentals/test-document/) is executed *in the same shell process*.

This is less flexible (e.g. Scrut cannot constraint max execution time per [test case](/docs/reference/fundamentals/test-case/)) and more prone to unintended side-effects (e.g. `set -e` terminating all test executions, not only a single test case or detached processes interfering with output association to specific tests). **We recommend to use Markdown**.

:::

## Parallel Documents

By default Scrut executes one [test document](/docs/reference/fundamentals/test-document/) after another. With `--jobs N`, the `test` and `update` commands execute up to `N` documents at the same time:

```bash title="Terminal"
$ scrut test --jobs 4 tests/
```

This is safe for documents that only use what Scrut provides per document: the shared shell environment, [working directory](/docs/reference/behavior/working-directory/) and temporary directory described above. Documents that share anything else, such as a file outside these directories, a network port or a database, may interfere with each other.

- The results are still reported in the order of the documents, whatever order they finish in.
- If a document can't be executed at all, for example because its shell can't be started, Scrut starts no further documents, waits for the ones already running, and fails. As without `--jobs`, `scrut update` has written the documents before it by then, and none after it.
- `scrut update` shows, confirms and writes changes one document after another, in the order of the documents, so prompts never interleave. It replaces a document in one step, so another document that reads it at the same time sees either the old or the new content.
- `--jobs` greater than 1 can't be combined with `--work-directory`, because all documents would share that one directory.
- Log messages (`--log-level`) of documents that run at the same time are printed as they happen, mixed with each other. To follow one document's log, run it without `--jobs`. The output of `--debug` stays together per document, in the order the documents finish.
