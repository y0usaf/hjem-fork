{
  config,
  bayt-lib,
  lib,
  options,
  pkgs,
  ...
}: let
  inherit (builtins) attrValues concatLists getAttr head mapAttrs;
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.meta) getExe getExe';
  inherit (lib.modules) importApply mkAfter mkDefault mkIf;
  inherit (lib.strings) concatMapAttrsStringSep escapeShellArg;
  inherit (lib.types) submoduleWith;

  cfg = config.bayt;
  _class = "darwin";

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  perUserOutputs = bayt-lib.mkPerUserOutputs {
    users = enabledUsers;
    linker = cfg.linker;
    linkerOptions = cfg.linkerOptions;
    isDarwin = true;
    manifestName = "manifest.json";
  };

  baytSubmodule = submoduleWith {
    description = "Bayt submodule for nix-darwin";
    class = "bayt";
    specialArgs =
      cfg.specialArgs
      // {
        inherit bayt-lib pkgs;
        osConfig = config;
        osOptions = options;
      };
    modules = concatLists [
      [
        ../common/user.nix
        ({name, ...}: let
          user = getAttr name config.users.users;
        in {
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
  imports = [
    (importApply ../common/top-level.nix {inherit baytSubmodule _class;})
  ];

  config = {
    users.users = mapAttrs (_: v: {inherit (v) packages;}) enabledUsers;

    # Temporary requirement: choose a primary user, pick the first enabled user.
    # This option will be deprecated in the future.
    system.primaryUser = mkIf (enabledUsers != {}) (mkDefault (head (attrValues enabledUsers)).name);

    # launchd agent to apply the per-user shared activation package
    # https://github.com/nix-darwin/nix-darwin/issues/871#issuecomment-2340443820
    launchd.user.agents = mkIf (enabledUsers != {}) {
      bayt-activate = {
        serviceConfig = {
          Program = getExe (pkgs.writeShellApplication {
            name = "bayt-activate";
            runtimeInputs = with pkgs; [coreutils-full bash];
            text = ''
              set -euo pipefail

              USER="$(id -un)"

              case "$USER" in
              ${concatMapAttrsStringSep "\n" (name: _: ''
                  ${escapeShellArg name})
                    exec ${escapeShellArg "${perUserOutputs.${name}.activationPackage}/bin/bayt-activate"}
                    ;;
                '')
                enabledUsers}
                *) exit 0 ;;
              esac
            '';
          });
          Label = "org.bayt.activate";
          RunAtLoad = true;
          StandardOutPath = "/var/tmp/bayt-activate.out";
          StandardErrorPath = "/var/tmp/bayt-activate.err";
        };
      };

      # Currently forced upon users, perhaps we should make an option for enabling this behavior?
      # Leaving it be for now.
      link-nix-apps = {
        serviceConfig = {
          Program = getExe (pkgs.writeShellApplication {
            name = "link-nix-apps";
            runtimeInputs = with pkgs; [coreutils-full findutils gnugrep nix];
            text = ''
              set -euo pipefail

              USER="$(id -un)"
              GROUP="$(id -gn)"
              DEST="$HOME/Applications/Nix User Apps"
              PROFILE="/etc/profiles/per-user/$USER"

              install -d -m 0755 -o "$USER" -g "$GROUP" "$DEST"

              desired="$(mktemp -t desired-apps.XXXXXX)"
              trap 'rm -f "$desired"' EXIT

              nix-store -qR "$PROFILE" | while IFS= read -r p; do
                apps="$p/Applications"
                if [ -d "$apps" ]; then
                  find "$apps" -maxdepth 1 -type d -name "*.app" -print0 \
                  | while IFS= read -r -d "" app; do
                      bname="$(basename "$app")"
                      echo "$bname" >> "$desired"
                      ln -sfn "$app" "$DEST/$bname"
                    done
                fi
              done

              sort -u "$desired" -o "$desired"

              find "$DEST" -maxdepth 1 -type l -name "*.app" -print0 \
              | while IFS= read -r -d "" link; do
                  name="$(basename "$link")"
                  if ! grep -Fxq "$name" "$desired"; then
                    rm -f "$link"
                  fi
                done

              # Remove broken links
              find "$DEST" -maxdepth 1 -type l -name "*.app" -print0 \
                | xargs -0 -I {} bash -c '[[ -e "{}" ]] || rm -f "{}"'
            '';
          });
          Label = "org.nix.link-nix-apps";
          RunAtLoad = true;
          StandardOutPath = "/var/tmp/link-nix-apps.out";
          StandardErrorPath = "/var/tmp/link-nix-apps.err";
        };
      };
    };

    system.activationScripts = mkIf (enabledUsers != {}) {
      bayt-activate-kick.text = mkAfter (
        concatMapAttrsStringSep "\n"
        (u: _: ''
          if uid="$(${getExe' pkgs.coreutils-full "id"} -u ${escapeShellArg u} 2>/dev/null)"; then
            /bin/launchctl kickstart -k "gui/''${uid}/${config.launchd.user.agents.bayt-activate.serviceConfig.Label}" 2>/dev/null || true
          fi
        '')
        enabledUsers
      );

      # Kick the user agent for every configured user at activation.
      applications.text = mkAfter (
        concatMapAttrsStringSep "\n"
        (u: _: ''
          if uid="$(${getExe' pkgs.coreutils-full "id"} -u ${escapeShellArg u} 2>/dev/null)"; then
            /bin/launchctl kickstart -k "gui/''${uid}/${config.launchd.user.agents.link-nix-apps.serviceConfig.Label}" 2>/dev/null || true
          fi
        '')
        enabledUsers
      );
    };
  };
}
