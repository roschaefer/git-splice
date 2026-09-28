{
  description = "git subtrees -- manage multiple git subtree prefixes with zero config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        git-subtrees = pkgs.stdenvNoCC.mkDerivation {
          pname = "git-subtrees";
          # release-please bumps VERSION in the entrypoint; read it from there.
          version = builtins.head
            (builtins.match ".*\nVERSION=([^ ]+) .*" (builtins.readFile ./git-subtrees));

          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./git-subtrees
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
          # and bin/ gets a wrapper that puts a git with `git subtree` on
          # PATH.
          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/git-subtrees
            cp -R git-subtrees lib $out/share/git-subtrees/
            makeWrapper $out/share/git-subtrees/git-subtrees $out/bin/git-subtrees \
              --prefix PATH : ${lib.makeBinPath [ pkgs.git pkgs.coreutils pkgs.gnused pkgs.gnugrep ]}
            install -Dm644 LICENSE $out/share/licenses/git-subtrees/LICENSE
            installShellCompletion --cmd git-subtrees \
              --bash completions/git-subtrees.bash \
              --zsh completions/git-subtrees.zsh \
              --fish completions/git-subtrees.fish
            runHook postInstall
          '';

          meta = {
            description = "Keep the git subtree folders of a monorepo in sync, with zero config";
            homepage = "https://github.com/roschaefer/git-subtrees";
            license = lib.licenses.mit;
            mainProgram = "git-subtrees";
            platforms = lib.platforms.unix;
          };
        };
      in
      {
        packages.default = git-subtrees;

        # Runs the installed package the way users do, through `git subtrees`,
        # against a subtree whose remote got a new commit.
        checks.default = pkgs.runCommand "git-subtrees-smoke"
          { nativeBuildInputs = [ git-subtrees pkgs.git ]; } ''
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
          git subtrees --version
          git subtrees init vendor/a ../upstream.git

          echo two >>../seed/file.txt
          git -C ../seed commit -q -am two
          git -C ../seed push -q origin main

          git subtrees fetch
          git subtrees status | tee status.txt
          grep -qF "(pull)" status.txt
          git subtrees pull
          grep -q two vendor/a/file.txt

          # bash: git's completion loads ours on demand through
          # bash-completion, from the package's share/.
          XDG_DATA_DIRS=${git-subtrees}/share ${pkgs.bashInteractive}/bin/bash --norc -i -c '
            source ${pkgs.bash-completion}/share/bash-completion/bash_completion
            source ${pkgs.git}/share/bash-completion/completions/git
            __git_complete_command subtrees
            declare -F _git_subtrees
          '
          touch $out
        '';

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.git
            pkgs.bats
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.bashInteractive
            pkgs.just
            pkgs.hyperfine
            # Only for test/completions.bats: the zsh and fish completions.
            pkgs.zsh
            pkgs.fish
          ];

          shellHook = ''
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            export PATH="$repo_root:$repo_root/playground:$PATH"
          '';
        };
      });
}
