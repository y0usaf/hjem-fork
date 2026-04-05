{
  baytSubmodule,
  _class,
}: {
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (builtins) concatLists;
  inherit (lib.attrsets) filterAttrs mapAttrsToList;
  inherit (lib.lists) optional;
  inherit (lib.options) literalExpression mkOption mkPackageOption;
  inherit (lib.types) attrs attrsWith bool deferredModule either listOf singleLineStr;

  cfg = config.bayt;

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;
in {
  inherit _class;

  options.bayt = {
    clobberByDefault = mkOption {
      type = bool;
      default = false;
      description = ''
        The default override behaviour for files managed by Bayt.

        While `true`, existing files will be overriden with new files on rebuild.
        The behaviour may be modified per-user by setting {option}`bayt.users.<username>.clobberFiles`
        to the desired value.
      '';
    };

    users = mkOption {
      default = {};
      type = attrsWith {
        elemType = baytSubmodule;
        placeholder = "username";
      };
      description = "Bayt-managed user configurations.";
    };

    extraModules = mkOption {
      type = listOf deferredModule;
      default = [];
      description = ''
        Additional modules to be evaluated as a part of the users module
        inside {option}`config.bayt.users.<username>`. This can be used to
        extend each user configuration with additional options.
      '';
    };

    specialArgs = mkOption {
      type = attrs;
      default = {};
      example = literalExpression "{ inherit inputs; }";
      description = ''
        Additional `specialArgs` are passed to Bayt, allowing extra arguments
        to be passed down to to all imported modules.
      '';
    };

    linker =
      mkPackageOption pkgs "smfh" {nullable = true;}
      // {
        description = ''
          Package to use to link files.

          By default, we use `smfh`, our own file linker.

          Setting this to `null` will use `systemd-tmpfiles`,
          which is only supported on Linux.

          `systemd-tmpfiles` is more mature, but it has the downside of
          leaving behind symlinks that may not get invalidated until the next GC,
          if an entry is removed from {option}`bayt.<user>.files`.

          Specifying a package will use a custom file linker that uses an
          internally-generated manifest. The custom file linker must use this
          manifest to create or remove links as needed, by comparing the manifest
          of the currently activated system with that of the new system.
          This prevents dangling symlinks when an entry is removed from
          {option}`bayt.<user>.files`.
        '';
      };

    linkerOptions = mkOption {
      default = [];
      description = ''
        Additional arguments to pass to the linker.

        This is for external linker modules to set, to allow extending the default set of bayt behaviours.
        It accepts either a list of strings, which will be passed directly as arguments, or an attribute set, which will be
        serialized to JSON and passed as `--linker-opts options.json`.
      '';
      type = either (listOf singleLineStr) attrs;
    };
  };

  config = {
    assertions =
      concatLists
      (mapAttrsToList (user: userConfig:
        map ({
          assertion,
          message,
          ...
        }: {
          inherit assertion;
          message = "${user} profile: ${message}";
        })
        userConfig.assertions)
      enabledUsers)
      ++ [
        {
          assertion = cfg.linker == null -> pkgs.stdenv.hostPlatform.isLinux;
          message = "The systemd-tmpfiles linker is only supported on Linux; on other platforms, use the manifest linker.";
        }
      ];

    warnings =
      concatLists
      (mapAttrsToList (
          user: userConfig:
            map (warning: "${user} profile: ${warning}") userConfig.warnings
        )
        enabledUsers)
      ++ optional
      (enabledUsers == {}) ''
        You have imported bayt, but you have not enabled bayt for any users.
      '';
  };
}
