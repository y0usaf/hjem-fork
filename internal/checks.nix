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
          inherit baytTest nix-darwin self;
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

      darwin-enabled-user-eval = import (self + "/tests/darwin-adapter-eval.nix") {
        inherit self nix-darwin pkgs;
        lib = pkgs.lib;
      };

      # Build the 'smfh' package as a part of Bayt's test suite.
      # If 'nix flake check' is ran in the CI, this might inflate build times
      # *a lot*.
      inherit smfh;

      # Formatting checks to run as a part of 'nix flake check' or manually
      # via 'nix build .#checks.<system>.formatting'.
      standalone-configuration-outputs = import (self + "/tests/standalone-configuration-outputs.nix") {
        inherit self pkgs smfh;
      };

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
