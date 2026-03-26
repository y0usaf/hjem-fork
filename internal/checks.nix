{
  nix-darwin,
  pkgs,
  self ? ../.,
  smfh,
}: let
  baytTest =
    # The first argument to this function is the test module itself
    test:
      (pkgs.testers.runNixOSTest {
        defaults.documentation.enable = pkgs.lib.mkDefault false;
        imports = [test];
      }).config.result;

  inherit (pkgs.lib.filesystem) packagesFromDirectoryRecursive;

  checks =
    packagesFromDirectoryRecursive {
      callPackage = pkgs.newScope (checks
        // {
          inherit baytTest;
          baytModule = (import (self + "/modules/nixos")).default;
        });
      directory = ../tests;
    }
    // {
      darwin-no-users-eval = let
        evalResult = builtins.tryEval (
          let
            system = nix-darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              modules = [
                (import (self + "/modules/nix-darwin")).default
                {
                  system.stateVersion = 6;
                }
              ];
            };
          in
            system.config.system.build.toplevel.drvPath
        );
      in
        assert evalResult.success;
          pkgs.runCommandLocal "bayt-darwin-no-users-eval" {} ''
            touch $out
          '';

      # Build the 'smfh' package as a part of Bayt's test suite.
      # If 'nix flake check' is ran in the CI, this might inflate build times
      # *a lot*.
      inherit smfh;

      # Formatting checks to run as a part of 'nix flake check' or manually
      # via 'nix build .#checks.<system>.formatting'.
      formatting =
        pkgs.runCommandLocal "bayt-formatting-check" {
          nativeBuildInputs = [pkgs.alejandra];
        } ''
          alejandra --check ${self}
          touch $out;
        '';
    };
in
  checks
