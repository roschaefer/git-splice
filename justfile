set shell := ["bash", "-c"]

# Build the port from bash into target/debug
build:
    cargo build

# Run the bats tests and the docs against the port, which hands commands it doesn't have yet to bash
test-port: build
    GIT_SPLICE_DIR="$PWD/target/debug" bats --recursive --jobs "$(nproc)" test
    GIT_SPLICE_DIR="$PWD/target/debug" GIT_SPLICE_LIB="$PWD/lib" just docs-check

# Run shellcheck and clippy
lint:
    cargo clippy --all-targets -- -D warnings
    shellcheck -x git-splice docs/design/pull-prototype.sh docs/design/rebuild-prototype.sh
    shellcheck test/walkthrough/setup.sh
    shellcheck completions/git-splice.bash
    shellcheck bench/setup.sh bench/run.sh
    shellcheck -x check-drawing/check-drawing check-drawing/check-export
    shellcheck -x test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh test/sandbox.sh

# Format with shfmt and rustfmt
fmt:
    cargo fmt
    shfmt -w -i 2 -ci git-splice lib/*.sh docs/design/*.sh test/walkthrough/setup.sh completions/git-splice.bash bench/setup.sh bench/run.sh test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh test/sandbox.sh check-drawing/check-drawing check-drawing/check-export

# Check formatting with shfmt and rustfmt
fmt-check:
    cargo fmt --check
    shfmt -d -i 2 -ci git-splice lib/*.sh docs/design/*.sh test/walkthrough/setup.sh completions/git-splice.bash bench/setup.sh bench/run.sh test/walkthrough/scrut-setup.sh test/scenarios/readme-setup.sh test/readme/scrut-setup.sh test/readme/both-sides-move-on.sh test/comparisons/scrut-setup.sh test/sandbox.sh check-drawing/check-drawing check-drawing/check-export

# Run the bats tests, one job per CPU
test:
    bats --recursive --jobs "$(nproc)" test

# Time commands on a synthetic monorepo; see `just bench --help`
[positional-arguments]
bench *args:
    @bench/run.sh "$@"

# Open a shell in the state a docs page starts from, the walkthrough by default, e.g. `just sandbox comparisons/git-submodule`; see `just sandbox --help`
[positional-arguments]
sandbox *args:
    @test/sandbox.sh "$@"

# Check the README, walkthroughs, concepts, scenario READMEs and comparisons against real output; --write updates them
docs-check flag="":
    @if [[ "{{flag}}" == --write ]]; then \
      scrut update --replace --assume-yes README.md test/walkthrough test/concepts test/scenarios test/comparisons; \
    elif [[ -n "{{flag}}" ]]; then \
      echo "usage: just docs-check [--write]" >&2; exit 1; \
    elif ! scrut test --jobs "$(nproc)" README.md test/walkthrough test/concepts test/scenarios test/comparisons; then \
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
