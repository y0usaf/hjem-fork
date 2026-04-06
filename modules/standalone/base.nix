{
  bayt-lib,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.modules) mkDefault;
  inherit (lib.options) literalExpression mkOption mkPackageOption;
  inherit (lib.types) attrs either listOf singleLineStr str package submoduleWith;

  baytSubmodule = submoduleWith {
    description = "Standalone Bayt configuration";
    class = "bayt";
    specialArgs = {
      inherit bayt-lib pkgs;
      homeConfig = config.home;
    };
    modules = [
      ../common/user.nix
      ({
        config,
        homeConfig,
        ...
      }: {
        options = {
          linker =
            mkPackageOption pkgs "smfh" {nullable = false;}
            // {
              description = ''
                Package to use when activating this standalone Bayt configuration.
              '';
            };

          linkerOptions = mkOption {
            default = [];
            description = ''
              Additional arguments to pass to the linker.
            '';
            type = either (listOf singleLineStr) attrs;
          };

          stateDir = mkOption {
            type = str;
            default = bayt-lib.standaloneStateDir {
              homeDirectory = homeConfig.homeDirectory;
            };
            defaultText = literalExpression ''
              if pkgs.stdenv.hostPlatform.isDarwin
              then "$HOME/Library/Application Support/Bayt"
              else "$HOME/.local/state/bayt"
            '';
            description = ''
              Directory used by Bayt to persist the last successfully applied manifest.
            '';
          };

          stateManifest = mkOption {
            type = str;
            internal = true;
            readOnly = true;
            description = "Path to the persisted manifest file.";
          };

          manifest = mkOption {
            type = package;
            internal = true;
            readOnly = true;
            description = "Buildable manifest output for this standalone configuration.";
          };

          manifestFile = mkOption {
            type = str;
            internal = true;
            readOnly = true;
            description = "Path to the rendered standalone manifest JSON file.";
          };

          activationPackage = mkOption {
            type = package;
            internal = true;
            readOnly = true;
            description = "Buildable activation package for this standalone configuration.";
          };
        };

        config = let
          outputs = bayt-lib.mkUserOutputs {
            user = config;
            linker = config.linker;
            linkerOptions = config.linkerOptions;
            stateManifest = "${config.stateDir}/manifest.json";
            manifestName = "manifest.json";
          };
        in {
          name = mkDefault homeConfig.username;
          user = mkDefault homeConfig.username;
          directory = mkDefault homeConfig.homeDirectory;
          clobberFiles = mkDefault false;

          inherit
            (outputs)
            stateManifest
            manifest
            manifestFile
            activationPackage
            ;

          assertions = [
            {
              assertion = config.linker != null;
              message = "Standalone Bayt requires a manifest linker package, such as pkgs.smfh.";
            }
          ];
        };
      })
    ];
  };
in {
  _class = "bayt-standalone";

  options = {
    home = {
      username = mkOption {
        type = str;
        description = "The standalone user's account name.";
      };

      homeDirectory = mkOption {
        type = str;
        description = "The standalone user's home directory.";
      };
    };

    bayt = mkOption {
      default = {};
      type = baytSubmodule;
      description = ''
        Standalone Bayt configuration.
      '';
    };
  };
}
