set shell := ["bash", "-c"]

# Run shellcheck
lint:
    shellcheck -x git-splice docs/design/pull-prototype.sh docs/design/rebuild-prototype.sh
    shellcheck test/walkthrough/setup.sh
    shellcheck completions/git-splice.bash
    shellcheck bench/setup.sh bench/run.sh
    shellcheck -x check-drawing/check-drawing
    shellcheck -x test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh

# Format with shfmt
fmt:
    shfmt -w -i 2 -ci git-splice lib/*.sh docs/design/*.sh test/walkthrough/setup.sh completions/git-splice.bash bench/setup.sh bench/run.sh test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh check-drawing/check-drawing

# Check formatting with shfmt
fmt-check:
    shfmt -d -i 2 -ci git-splice lib/*.sh docs/design/*.sh test/walkthrough/setup.sh completions/git-splice.bash bench/setup.sh bench/run.sh test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh check-drawing/check-drawing

# Run the bats tests, one job per CPU
test:
    bats --recursive --jobs "$(nproc)" test

# Time commands on a synthetic monorepo; see `just bench --help`
[positional-arguments]
bench *args:
    @bench/run.sh "$@"

# Open a shell in a throwaway monorepo to try commands by hand; see `just walkthrough --help`
[positional-arguments]
walkthrough *args:
    @test/walkthrough/setup.sh "$@"

# Check the README, walkthroughs, concepts, scenario READMEs and comparisons against real output; --write updates them
docs-check flag="":
    @if [[ "{{flag}}" == --write ]]; then \
      scrut update --jobs "$(nproc)" --replace --assume-yes README.md test/walkthrough test/concepts test/scenarios test/comparisons; \
    elif [[ -n "{{flag}}" ]]; then \
      echo "usage: just docs-check [--write]" >&2; exit 1; \
    elif ! scrut test --jobs "$(nproc)" README.md test/walkthrough test/concepts test/scenarios test/comparisons; then \
      echo "The README, walkthroughs, concepts, scenario READMEs or comparisons don't match real output. If only the output changed, run 'just docs-check --write'." >&2; exit 1; \
    fi

# Build the documentation site into website/build; fails on broken links
site-build:
    cd website && pnpm install --frozen-lockfile && pnpm build

# Serve the documentation site locally, reloading on changes
site-serve:
    cd website && pnpm install --frozen-lockfile && pnpm start

# Everything CI runs: lint, fmt-check, test, docs-check and site-build
ci: lint fmt-check test docs-check site-build

# Update nix/scrut.Cargo.lock after scrut/Cargo.toml changed, e.g. after a pull; scrut upstream commits no Cargo.lock
scrut-lock:
    cp nix/scrut.Cargo.lock scrut/Cargo.lock
    cd scrut && nix shell --inputs-from .. nixpkgs-scrut#cargo --command cargo fetch --quiet
    mv scrut/Cargo.lock nix/scrut.Cargo.lock
