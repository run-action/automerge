{
  description = "Lint tooling for the Dependabot automerge composite action";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      # Linters and test tools shared by the dev shell and `nix flake check`.
      tools =
        pkgs: with pkgs; [
          shellcheck
          actionlint
          yamllint
          nixfmt
          bats
          jq
        ];
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = tools pkgs;
            shellHook = ''
              echo "Dev shell ready: shellcheck, actionlint, yamllint, nixfmt, bats, jq"
              echo "Run all checks with: nix flake check -L  (or just: bats tests/)"
            '';
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          src = self;
          run =
            name: deps: script:
            pkgs.runCommand "check-${name}" { nativeBuildInputs = deps; } ''
              cd ${src}
              ${script}
              touch $out
            '';
        in
        {
          shellcheck = run "shellcheck" [ pkgs.shellcheck ] ''
            shellcheck scripts/*.sh
          '';

          # shellcheck must be on PATH so actionlint can lint the shell in
          # `run:` blocks; without it that analysis is silently skipped.
          actionlint = run "actionlint" [ pkgs.actionlint pkgs.shellcheck ] ''
            actionlint examples/*.yml .github/workflows/*.yml
          '';

          yamllint = run "yamllint" [ pkgs.yamllint ] ''
            yamllint .
          '';

          nixfmt = run "nixfmt" [ pkgs.nixfmt ] ''
            nixfmt --check flake.nix
          '';

          tests = run "tests" [ pkgs.bats pkgs.jq ] ''
            bats tests/
          '';
        }
      );
    };
}
