set shell := ["bash", "-c"]

# Run shellcheck
lint:
    shellcheck -x git-subtrees
    shellcheck -x docs/last-synced-commit/walkthrough.sh
    shellcheck walkthrough/setup.sh walkthrough/simulate-remote-change
    shellcheck completions/git-subtrees.bash
    shellcheck bench/setup.sh bench/run.sh
    shellcheck -x walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh

# Format with shfmt
fmt:
    shfmt -w -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh walkthrough/setup.sh walkthrough/simulate-remote-change completions/git-subtrees.bash bench/setup.sh bench/run.sh walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh

# Check formatting with shfmt
fmt-check:
    shfmt -d -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh walkthrough/setup.sh walkthrough/simulate-remote-change completions/git-subtrees.bash bench/setup.sh bench/run.sh walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh

# Run the bats tests
test:
    bats --recursive test

# Time commands on a synthetic monorepo; see `just bench --help`
[positional-arguments]
bench *args:
    @bench/run.sh "$@"

# Open a shell in a throwaway monorepo to try commands by hand; see `just walkthrough --help`
[positional-arguments]
walkthrough *args:
    @walkthrough/setup.sh "$@"

# Check the walkthroughs and scenario READMEs against real output; --write updates them
docs-check flag="":
    @if [[ "{{flag}}" == --write ]]; then \
      scrut update --replace --assume-yes walkthrough test/scenarios; \
    elif [[ -n "{{flag}}" ]]; then \
      echo "usage: just docs-check [--write]" >&2; exit 1; \
    elif ! scrut test walkthrough test/scenarios; then \
      echo "The walkthroughs or scenario READMEs don't match real output. If only the output changed, run 'just docs-check --write'." >&2; exit 1; \
    fi

# Everything CI runs: lint, fmt-check, test and docs-check
ci: lint fmt-check test docs-check
