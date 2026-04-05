{
  pkgs,
  self,
  smfh,
}: let
  baytLib = self.lib;
  homeDir =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/private/tmp/bayt-clobber"
    else "/build/bayt-clobber";
  stateManifest =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "${homeDir}/Library/Application Support/Bayt/manifest.json"
    else "${homeDir}/.local/state/bayt/manifest.json";

  mkCfg = module:
    baytLib.mkConfiguration {
      inherit pkgs;
      modules = [
        self.modules.standalone
        {
          home.username = "alice";
          home.homeDirectory = homeDir;
          bayt.linker = smfh;
        }
        module
      ];
    };

  cfgNoClobber = mkCfg {
    bayt.files.".config/protect".text = "managed";
  };

  cfgClobber = mkCfg {
    bayt.files.".config/replace" = {
      text = "managed";
      clobber = true;
    };
  };
in
  pkgs.runCommandLocal "bayt-standalone-clobber" {} ''
    export HOME=${homeDir}
    mkdir -p "$HOME/.config"

    printf 'unmanaged\n' > "$HOME/.config/protect"
    if ${cfgNoClobber.activationPackage}/bin/bayt-activate; then
      echo "expected clobber=false activation to refuse replacing unmanaged target" >&2
      exit 1
    fi
    grep -q 'unmanaged' "$HOME/.config/protect"
    if [ -e "${stateManifest}" ]; then
      echo "state manifest should not be written after failed activation" >&2
      exit 1
    fi

    printf 'unmanaged\n' > "$HOME/.config/replace"
    ${cfgClobber.activationPackage}/bin/bayt-activate
    grep -q 'managed' "$HOME/.config/replace"
    test -f "${stateManifest}"

    touch "$out"
  ''
