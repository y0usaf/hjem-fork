{
  pkgs,
  self,
  smfh,
}: let
  baytLib = self.lib;
  homeDir =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/private/tmp/bayt-home"
    else "/build/home";
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

  cfgA = mkCfg {
    bayt.files.".config/foo".text = "v1";
  };

  cfgB = mkCfg {
    bayt.files.".config/foo" = {
      text = "v2";
      clobber = true;
    };
  };

  cfgC = mkCfg {};
in
  pkgs.runCommandLocal "bayt-standalone-activation" {
    nativeBuildInputs = with pkgs; [
      jq
    ];
  } ''
    export HOME=${homeDir}
    mkdir -p "$HOME"

    ${cfgA.activationPackage}/bin/bayt-activate
    test -L "$HOME/.config/foo"
    grep -q 'v1' "$HOME/.config/foo"
    test -f "${stateManifest}"

    ${cfgA.activationPackage}/bin/bayt-activate
    grep -q 'v1' "$HOME/.config/foo"

    ${cfgB.activationPackage}/bin/bayt-activate
    grep -q 'v2' "$HOME/.config/foo"

    ${cfgC.activationPackage}/bin/bayt-activate
    ! test -e "$HOME/.config/foo"
    jq -e '.files | any(.target == "${homeDir}/.config/foo") | not' "${stateManifest}" >/dev/null

    touch "$out"
  ''
