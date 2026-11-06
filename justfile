set shell := ["bash", "-c"]

# Build git-splice into target/debug, where the tests and docs run it
build:
    cargo build

# Run shellcheck and clippy
lint:
    cargo clippy --workspace --all-targets -- -D warnings
    shellcheck -x docs/07-design/pull-prototype.sh docs/07-design/rebuild-prototype.sh
    shellcheck docs/tests/walkthrough/setup.sh
    shellcheck completions/git-splice.bash
    shellcheck bench/setup.sh bench/run.sh
    shellcheck -x check-drawing/check-drawing check-drawing/check-export
    shellcheck -x docs/tests/walkthrough/scrut-setup.sh docs/09-scenarios/readme-setup.sh docs/readme/scrut-setup.sh docs/readme/both-sides-move-on.sh docs/05-comparisons/scrut-setup.sh docs/01-getting-started/sandbox.sh

# Format with shfmt and rustfmt
fmt:
    cargo fmt --all
    shfmt -w -i 2 -ci docs/07-design/*.sh docs/tests/walkthrough/setup.sh completions/git-splice.bash bench/setup.sh bench/run.sh docs/tests/walkthrough/scrut-setup.sh docs/09-scenarios/readme-setup.sh docs/readme/scrut-setup.sh docs/readme/both-sides-move-on.sh docs/05-comparisons/scrut-setup.sh docs/01-getting-started/sandbox.sh check-drawing/check-drawing check-drawing/check-export

# Check formatting with shfmt and rustfmt
fmt-check:
    cargo fmt --all --check
    shfmt -d -i 2 -ci docs/07-design/*.sh docs/tests/walkthrough/setup.sh completions/git-splice.bash bench/setup.sh bench/run.sh docs/tests/walkthrough/scrut-setup.sh docs/09-scenarios/readme-setup.sh docs/readme/scrut-setup.sh docs/readme/both-sides-move-on.sh docs/05-comparisons/scrut-setup.sh docs/01-getting-started/sandbox.sh check-drawing/check-drawing check-drawing/check-export

# Run the Rust unit tests, then the bats tests, one job per CPU
test: build
    cargo test --workspace --quiet
    bats --jobs "$(nproc)" docs/tests

# Time commands on a synthetic monorepo; see `just bench --help`
[positional-arguments]
bench *args:
    @cargo build --release --quiet
    @bench/run.sh "$@"

# Open a shell in the state a docs page starts from, the walkthrough by default, e.g. `just sandbox 05-comparisons/01-git-submodule`; see `just sandbox --help`
[positional-arguments]
sandbox *args: build
    @docs/01-getting-started/sandbox.sh "$@"

# Check the README, walkthroughs, concepts, scenario READMEs and comparisons against real output; --write updates them
docs-check flag="": build
    target/debug/check-drawing labels README.md $(git ls-files 'docs/*.md' ':!docs/10-contributing/02-writing.md')
    target/debug/check-drawing placement README.md $(git ls-files 'docs/*.md')
    @if [[ "{{flag}}" == --write ]]; then \
      scrut update --replace --assume-yes README.md docs/01-getting-started/02-walkthrough.md docs/02-using-git-splice docs/03-concepts docs/04-advanced-workflows docs/05-comparisons docs/06-command-reference docs/07-design/03-git-trace.md docs/09-scenarios; \
    elif [[ -n "{{flag}}" ]]; then \
      echo "usage: just docs-check [--write]" >&2; exit 1; \
    elif ! scrut test --jobs "$(nproc)" README.md docs/01-getting-started/02-walkthrough.md docs/02-using-git-splice docs/03-concepts docs/04-advanced-workflows docs/05-comparisons docs/06-command-reference docs/07-design/03-git-trace.md docs/09-scenarios; then \
      echo "The README, walkthroughs, concepts, scenario READMEs or comparisons don't match real output. If only the output changed, run 'just docs-check --write'." >&2; exit 1; \
    fi

# Check with draw.io that each drawing's picture is its diagram's export; --write exports the stale ones again
drawings-check flag="":
    @if [[ -n "{{flag}}" && "{{flag}}" != --write ]]; then \
      echo "usage: just drawings-check [--write]" >&2; exit 1; \
    fi
    nix develop .#drawings --command check-drawing/check-export {{flag}}

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
