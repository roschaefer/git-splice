{
  description = "git splice -- keep folders of a monorepo in sync with their own repositories";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-scrut.follows = "nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-scrut, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        git-splice = pkgs.rustPlatform.buildRustPackage {
          pname = "git-splice";
          # release-please bumps it in Cargo.toml; read it from there.
          version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).package.version;

          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./Cargo.toml
              ./Cargo.lock
              ./src
              ./completions
              ./LICENSE
            ];
          };
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = [ pkgs.makeWrapper pkgs.installShellFiles ];
          # The tests need the docs and fixtures, which the package leaves out;
          # CI runs them on the checkout.
          doCheck = false;

          # It runs the git CLI, and a pager through sh.
          postInstall = ''
            wrapProgram $out/bin/git-splice \
              --prefix PATH : ${lib.makeBinPath [ pkgs.git pkgs.bash ]}
            install -Dm644 LICENSE $out/share/licenses/git-splice/LICENSE
            installShellCompletion --cmd git-splice \
              --bash completions/git-splice.bash \
              --zsh completions/git-splice.zsh \
              --fish completions/git-splice.fish
          '';

          meta = {
            description = "Keep folders of a monorepo in sync with their own repositories, in both directions";
            homepage = "https://github.com/roschaefer/git-splice";
            license = lib.licenses.mit;
            mainProgram = "git-splice";
            platforms = lib.platforms.unix;
          };
        };
        # Runs the walkthroughs and scenario READMEs (`just docs-check`). Built
        # from scrut/, our fork spliced in, so changes there are used without a
        # release. CI caches the build, see .github/actions/scrut-cache.
        scrut =
          let
            pkgs-scrut = nixpkgs-scrut.legacyPackages.${system};
          in
          pkgs-scrut.rustPlatform.buildRustPackage {
            pname = "scrut";
            version = (lib.importTOML ./scrut/Cargo.toml).package.version;
            src = ./scrut;
            # Upstream doesn't commit a Cargo.lock. Ours lives outside scrut/,
            # so `git splice push` doesn't send it to the fork; `just
            # scrut-lock` updates it.
            cargoLock.lockFile = ./nix/scrut.Cargo.lock;
            postPatch = "ln -s ${./nix/scrut.Cargo.lock} Cargo.lock";
            # The sandbox has no /bin/bash, scrut's default shell.
            preCheck = "export SCRUT_DEFAULT_SHELL=${pkgs-scrut.bash}/bin/bash";
          };
        # Runs in the Sapling comparison, test/comparisons/vcs/. nixpkgs
        # has 0.2.20250521, which can't merge from an external repository
        # (`sl subtree merge --url`); the release binary can. Linux only.
        sapling =
          let
            version = "0.2.20260929-102736+288e0c2d";
            arch = { x86_64-linux = "x64"; aarch64-linux = "arm64"; }.${system};
          in
          pkgs.stdenv.mkDerivation {
            pname = "sapling";
            inherit version;
            src = pkgs.fetchurl {
              url = "https://github.com/facebook/sapling/releases/download/${lib.escapeURL version}/sapling-${version}-linux-${arch}.tar.xz";
              hash = {
                x64 = "sha256-8pa0t9WY3AmdQADp8u9lbjZrY5httpyJEP5thectBzw=";
                arm64 = "sha256-Qo0jFPfRPDFiqZQT5zSt9IGnBZIjqOgAPRJNDbLa2uA=";
              }.${arch};
            };
            sourceRoot = ".";
            nativeBuildInputs = [ pkgs.autoPatchelfHook ];
            # The bundled Python's extension modules link these.
            buildInputs = with pkgs; [
              stdenv.cc.cc.lib
              zlib
              libffi
              ncurses
              sqlite
              bzip2
              readline
              openssl
              xz
            ];
            # For tkinter, crypt and dbm, which Sapling doesn't import.
            autoPatchelfIgnoreMissingDeps = [
              "libtk8.6.so"
              "libtcl8.6.so"
              "libcrypt.so.2"
              "libgdbm.so.6"
              "libgdbm_compat.so.4"
            ];
            installPhase = ''
              mkdir -p $out/libexec/sapling $out/bin
              cp -r sl lib $out/libexec/sapling/
              ln -s $out/libexec/sapling/sl $out/bin/sl
            '';
          };
        # Runs in the Jujutsu comparison, test/comparisons/vcs/. nixos-25.05
        # has 0.29; the release binary is static.
        jujutsu =
          let
            version = "0.46.0";
            target = {
              x86_64-linux = "x86_64-unknown-linux-musl";
              aarch64-linux = "aarch64-unknown-linux-musl";
              x86_64-darwin = "x86_64-apple-darwin";
              aarch64-darwin = "aarch64-apple-darwin";
            }.${system};
          in
          pkgs.stdenvNoCC.mkDerivation {
            pname = "jujutsu";
            inherit version;
            src = pkgs.fetchurl {
              url = "https://github.com/jj-vcs/jj/releases/download/v${version}/jj-v${version}-${target}.tar.gz";
              hash = {
                x86_64-unknown-linux-musl = "sha256-/OAnEVjmZc64LcZsXrlbFyhkkJTpEzB087W67ONF/Ag=";
                aarch64-unknown-linux-musl = "sha256-gOKPdQHBHlDgygbNah+h2YLP+cxZv+RBGp02qlAdhn4=";
                x86_64-apple-darwin = "sha256-ENlB3idsfFB07105UxKBO0V19M6Sy5wLBXOO+5C9O2A=";
                aarch64-apple-darwin = "sha256-Q9qjfOD5cWzfb7ZaKcvK50oxYK7wSM88s9Fm1By0q1g=";
              }.${target};
            };
            sourceRoot = ".";
            installPhase = "install -Dm755 jj $out/bin/jj";
          };
      in
      {
        packages.default = git-splice;
        packages.scrut = scrut;

        # Runs the installed package the way users do, through `git splice`,
        # against a splice whose upstream got a new commit.
        checks.default = pkgs.runCommand "git-splice-smoke"
          { nativeBuildInputs = [ git-splice pkgs.git ]; } ''
          export HOME=$TMPDIR
          git config --global user.name smoke
          git config --global user.email smoke@example.com
          git config --global init.defaultBranch main

          git init -q --bare upstream.git
          git clone -q upstream.git seed
          echo one >seed/file.txt
          git -C seed add file.txt
          git -C seed commit -q -m one
          git -C seed push -q origin main

          git init -q monorepo
          cd monorepo
          git commit -q --allow-empty -m initial
          git splice --version
          git splice clone ../upstream.git vendor/a

          echo two >>../seed/file.txt
          git -C ../seed commit -q -am two
          git -C ../seed push -q origin main

          git splice fetch
          git splice status | tee status.txt
          grep -qxF "  behind 1  vendor/a" status.txt
          git splice pull vendor/a
          grep -q two vendor/a/file.txt
          echo three >>vendor/a/file.txt
          git commit -q -am three
          git splice push vendor/a
          git -C ../upstream.git log -1 --format=%s main | grep -qx three

          # bash: git's completion loads ours on demand through
          # bash-completion, from the package's share/.
          XDG_DATA_DIRS=${git-splice}/share ${pkgs.bashInteractive}/bin/bash --norc -i -c '
            source ${pkgs.bash-completion}/share/bash-completion/bash_completion
            source ${pkgs.git}/share/bash-completion/completions/git
            __git_complete_command splice
            declare -F _git_splice
          '
          touch $out
        '';

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.git
            pkgs.bats
            pkgs.util-linux
            # Build the port from bash, src/.
            pkgs.cargo
            pkgs.rustc
            pkgs.clippy
            pkgs.rustfmt
            # For `bats --jobs`, which runs the tests in parallel.
            pkgs.parallel
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.bashInteractive
            pkgs.just
            pkgs.hyperfine
            # Reads the diagrams embedded in the .drawio.svg drawings, check-drawing/.
            pkgs.xmlstarlet
            # Renders the walkthrough chapters in the walkthrough shell.
            pkgs.glow
            scrut
            # Runs in the git-subrepo comparison, test/comparisons/third-party/.
            pkgs.git-subrepo
            # Runs in the Josh comparison, test/comparisons/third-party/.
            pkgs.josh
            jujutsu
          ] ++ lib.optionals pkgs.stdenv.isLinux [
            sapling
          ] ++ [
            # Builds the documentation site in website/.
            pkgs.nodejs
            pkgs.pnpm
            # Only for test/completions.bats: the zsh and fish completions.
            pkgs.zsh
            pkgs.fish
          ];

          shellHook = ''
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            export PATH="$repo_root:$repo_root/test/walkthrough:$PATH"
          '';
        };

        # draw.io, for `just drawings-check`: a shell of its own, since only
        # that check needs it and it's large. From nixos-26.05, as
        # nixos-25.05's draw.io is unfree; headless, so it runs in CI.
        devShells.drawings = pkgs.mkShell {
          packages = [
            nixpkgs-scrut.legacyPackages.${system}.drawio-headless
            pkgs.git
            # For test/drawing-export.bats.
            pkgs.bats
          ];
          # The fonts draw.io measures labels with, e.g. for a label's
          # background: the drawings' own, then a fallback. Without them
          # draw.io measures with whatever the machine has, and the export
          # differs between machines.
          FONTCONFIG_FILE = pkgs.makeFontsConf {
            fontDirectories = [ pkgs.roboto-mono pkgs.dejavu_fonts ];
          };
        };
      });
}
