{
  config,
  bayt-lib,
  lib,
  options,
  pkgs,
  utils,
  ...
}: let
  inherit (builtins) attrNames attrValues concatLists concatMap concatStringsSep filter map mapAttrs;
  inherit (lib.attrsets) filterAttrs optionalAttrs;
  inherit (lib.modules) importApply mkDefault mkIf mkMerge;
  inherit (lib.strings) escapeShellArg optionalString;
  inherit (lib.trivial) pipe;
  inherit (lib.types) submoduleWith;

  osConfig = config;

  cfg = config.bayt;
  _class = "nixos";

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;
  disabledUsers = filterAttrs (_: u: !u.enable) cfg.users;

  userFiles = bayt-lib.userFileSets;

  perUserOutputs = bayt-lib.mkPerUserOutputs {
    users = enabledUsers;
    linker = cfg.linker;
    linkerOptions = cfg.linkerOptions;
    isDarwin = false;
    manifestName = "manifest.json";
  };

  baytSubmodule = submoduleWith {
    description = "Bayt submodule for NixOS";
    class = "bayt";
    specialArgs =
      cfg.specialArgs
      // {
        inherit bayt-lib osConfig pkgs utils;
        osOptions = options;
      };
    modules = concatLists [
      [
        ../common/user.nix
        ./systemd.nix
        ({
          config,
          name,
          ...
        }: let
          user = osConfig.users.users.${name};
        in {
          assertions = [
            {
              assertion = config.enable -> user.enable;
              message = "Enabled Bayt user '${name}' must also be configured and enabled in NixOS.";
            }
          ];

          name = mkDefault user.name;
          user = mkDefault user.name;
          directory = mkDefault user.home;
          clobberFiles = mkDefault cfg.clobberByDefault;
        })
      ]
      # Evaluate additional modules under 'bayt.users.<username>' so that
      # module systems built on Bayt are more ergonomic.
      cfg.extraModules
    ];
  };
in {
  inherit _class;

  imports = [
    (importApply ../common/top-level.nix {inherit baytSubmodule _class;})
  ];

  config = mkMerge [
    {
      users.users = mapAttrs (_: v: {inherit (v) packages;}) enabledUsers;
    }

    # Constructed rule string that consists of the type, target, and source
    # of a tmpfile. Files with 'null' sources are filtered before the rule
    # is constructed.
    (mkIf (cfg.linker == null) {
      systemd.user.tmpfiles.users =
        mapAttrs (_: u: {
          rules = pipe (userFiles u) [
            (concatMap attrValues)
            (filter (f: f.enable && f.source != null))
            (map (
              file:
              # L+ will recreate, i.e., clobber existing files.
              "L${optionalString file.clobber "+"} '${file.target}' - - - - ${file.source}"
            ))
          ];
        })
        enabledUsers;
    })

    (mkIf (cfg.linker != null) {
      systemd.targets.bayt = {
        description = "Bayt File Management";
        after = ["local-fs.target"];
        wantedBy = ["sysinit-reactivation.target" "multi-user.target"];
        before = ["sysinit-reactivation.target"];
        requires = let
          requiredUserServices = u: [
            "bayt-copy@${u.name}.service"
          ];
        in
          concatMap requiredUserServices (attrValues enabledUsers)
          ++ ["bayt-cleanup.service"];
      };

      systemd.services = let
        oldManifests = "/var/lib/bayt";
        checkEnabledUsers = ''
          case "$1" in
            ${concatStringsSep "|" (map (u: u.name) (attrValues enabledUsers))}) ;;
            *) echo "User '$1' is not configured for Bayt" >&2; exit 0 ;;
          esac
        '';
        activationDispatcher = concatStringsSep "\n" (map (u: ''
          ${escapeShellArg u.name})
            state_manifest=${escapeShellArg perUserOutputs.${u.name}.stateManifest}
            legacy_manifest=${escapeShellArg "${oldManifests}/manifest-${u.name}.json"}

            if [ ! -f "$state_manifest" ] && [ -f "$legacy_manifest" ]; then
              mkdir -p "$(dirname "$state_manifest")"
              cp "$legacy_manifest" "$state_manifest"
            fi

            exec ${escapeShellArg "${perUserOutputs.${u.name}.activationPackage}/bin/bayt-activate"}
            ;;
        '') (attrValues enabledUsers));
        mirrorDispatcher = concatStringsSep "\n" (map (u: ''
          ${escapeShellArg u.name})
            state_manifest=${escapeShellArg perUserOutputs.${u.name}.stateManifest}
            destination_manifest=${escapeShellArg "${oldManifests}/manifest-${u.name}.json"}
            ;;
        '') (attrValues enabledUsers));
      in
        optionalAttrs (enabledUsers != {}) {
          bayt-prepare = {
            description = "Prepare Bayt manifests directory";
            enableStrictShellChecks = true;
            script = "mkdir -p ${oldManifests}";
            serviceConfig.Type = "oneshot";
            unitConfig.RefuseManualStart = true;
          };

          "bayt-activate@" = {
            description = "Link files for %i from their manifest";
            enableStrictShellChecks = true;
            serviceConfig = {
              User = "%i";
              Type = "oneshot";
            };
            requires = [
              "bayt-prepare.service"
            ];
            after = ["bayt-prepare.service"];
            scriptArgs = "%i";
            script = ''
              ${checkEnabledUsers}

              case "$1" in
              ${activationDispatcher}
              esac
            '';
          };

          "bayt-copy@" = {
            description = "Copy the manifest into Bayt's state directory for %i";
            enableStrictShellChecks = true;
            serviceConfig.Type = "oneshot";
            requires = [
              "bayt-prepare.service"
              "bayt-activate@%i.service"
            ];
            after = [
              "bayt-prepare.service"
              "bayt-activate@%i.service"
            ];
            scriptArgs = "%i";
            /*
            TODO: remove the if condition in a while, this is in place because the first iteration of the
            manifest used to simply point /var/lib/bayt to the aggregate symlinkJoin directory. Since
            per-user manifest services have now been implemented, trying to copy singular files into
            /var/lib/bayt will fail if the user was using the previous manifest handling.
            */
            script = ''
              ${checkEnabledUsers}

              case "$1" in
              ${mirrorDispatcher}
              esac

              if ! cp "$state_manifest" "$destination_manifest"; then
                echo "Copying the manifest for $1 failed. This is likely due to using the previous\
                version of the manifest handling. The manifest directory has been recreated and repopulated with\
                $1's manifest. Please re-run the activation services for your other users, if you have ran this one manually."

                rm -rf ${oldManifests}
                mkdir -p ${oldManifests}

                cp "$state_manifest" "$destination_manifest"
              fi
            '';
          };

          bayt-cleanup = {
            description = "Cleanup disabled users' manifests";
            enableStrictShellChecks = true;
            serviceConfig.Type = "oneshot";
            after = ["bayt.target"];
            unitConfig.RefuseManualStart = false;
            script = let
              manifestsToDelete =
                map
                (user: "${oldManifests}/manifest-${user}.json")
                (attrNames disabledUsers);
            in
              if disabledUsers != {}
              then "rm -f ${concatStringsSep " " manifestsToDelete}"
              else "true";
          };
        };
    })
  ];
}
