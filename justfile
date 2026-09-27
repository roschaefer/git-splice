set shell := ["bash", "-c"]

# Run shellcheck
lint:
    shellcheck -x git-subtrees
    shellcheck -x docs/last-synced-commit/walkthrough.sh
    shellcheck playground/setup.sh playground/simulate-remote-change
    shellcheck completions/git-subtrees.bash
    shellcheck bench/setup.sh bench/run.sh

# Format with shfmt
fmt:
    shfmt -w -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh playground/setup.sh playground/simulate-remote-change completions/git-subtrees.bash bench/setup.sh bench/run.sh

# Check formatting with shfmt
fmt-check:
    shfmt -d -i 2 -ci git-subtrees lib/*.sh docs/last-synced-commit/walkthrough.sh playground/setup.sh playground/simulate-remote-change completions/git-subtrees.bash bench/setup.sh bench/run.sh

# Run the bats tests
test:
    bats --recursive test

# Time commands on a synthetic monorepo; see `just bench --help`
[positional-arguments]
bench *args:
    @bench/run.sh "$@"

# Open a shell in a throwaway monorepo to try commands by hand; see `just playground --help`
[positional-arguments]
playground *args:
    @playground/setup.sh "$@"

# Everything CI runs: lint, fmt-check and test
ci: lint fmt-check test
