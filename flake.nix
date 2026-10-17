{
  description = "git splice -- keep folders of a monorepo in sync with their own repositories";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    # Only builds scrut/, which needs a newer Rust than nixos-25.05 has.
    nixpkgs-scrut.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-scrut, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        git-splice = pkgs.stdenvNoCC.mkDerivation {
          pname = "git-splice";
          # release-please bumps VERSION in the entrypoint; read it from there.
          version = builtins.head
            (builtins.match ".*\nVERSION=([^ ]+) .*" (builtins.readFile ./git-splice));

          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./git-splice
              ./lib
              ./completions
              ./LICENSE
            ];
          };

          nativeBuildInputs = [ pkgs.makeWrapper pkgs.installShellFiles ];
          # For patchShebangs: the entrypoint's `#!/usr/bin/env bash`.
          buildInputs = [ pkgs.bash ];
          dontBuild = true;

          # The entrypoint finds lib/ next to itself, so both go to share/
          # and bin/ gets a wrapper that puts git and the tools the scripts
          # call on PATH.
          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/git-splice
            cp -R git-splice lib $out/share/git-splice/
            makeWrapper $out/share/git-splice/git-splice $out/bin/git-splice \
              --prefix PATH : ${lib.makeBinPath [ pkgs.git pkgs.coreutils pkgs.gnused pkgs.gnugrep ]}
            install -Dm644 LICENSE $out/share/licenses/git-splice/LICENSE
            installShellCompletion --cmd git-splice \
              --bash completions/git-splice.bash \
              --zsh completions/git-splice.zsh \
              --fish completions/git-splice.fish
            runHook postInstall
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
      });
}
