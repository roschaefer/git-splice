set shell := ["bash", "-c"]

# Run shellcheck
lint:
    shellcheck -x git-splice docs/design/pull-prototype.sh docs/design/rebuild-prototype.sh
    shellcheck test/walkthrough/setup.sh test/walkthrough/simulate-remote-change
    shellcheck completions/git-splice.bash
    shellcheck bench/setup.sh bench/run.sh
    shellcheck -x test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh

# Format with shfmt
fmt:
    shfmt -w -i 2 -ci git-splice lib/*.sh docs/design/*.sh test/walkthrough/setup.sh test/walkthrough/simulate-remote-change completions/git-splice.bash bench/setup.sh bench/run.sh test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh

# Check formatting with shfmt
fmt-check:
    shfmt -d -i 2 -ci git-splice lib/*.sh docs/design/*.sh test/walkthrough/setup.sh test/walkthrough/simulate-remote-change completions/git-splice.bash bench/setup.sh bench/run.sh test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh

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
    @test/walkthrough/setup.sh "$@"

# Check the README, walkthroughs, scenario READMEs and comparisons against real output; --write updates them
docs-check flag="":
    @if [[ "{{flag}}" == --write ]]; then \
      scrut update --replace --assume-yes README.md test/walkthrough test/scenarios test/comparisons; \
    elif [[ -n "{{flag}}" ]]; then \
      echo "usage: just docs-check [--write]" >&2; exit 1; \
    elif ! scrut test README.md test/walkthrough test/scenarios test/comparisons; then \
      echo "The README, walkthroughs, scenario READMEs or comparisons don't match real output. If only the output changed, run 'just docs-check --write'." >&2; exit 1; \
    fi

# Build the documentation site into website/build; fails on broken links
site-build:
    cd website && pnpm install --frozen-lockfile && pnpm build

# Serve the documentation site locally, reloading on changes
site-serve:
    cd website && pnpm install --frozen-lockfile && pnpm start

# Everything CI runs: lint, fmt-check, test, docs-check and site-build
ci: lint fmt-check test docs-check site-build
