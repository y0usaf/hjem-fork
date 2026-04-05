{
  pkgs,
  self,
  smfh,
}: let
  baytLib = self.lib;
  homeDir =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/private/tmp/bayt-home-fail"
    else "/build/home-fail";
  stateManifest =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "${homeDir}/Library/Application Support/Bayt/manifest.json"
    else "${homeDir}/.local/state/bayt/manifest.json";

  failingLinker = pkgs.writeShellApplication {
    name = "failing-linker";
    text = ''
      echo "intentional failure" >&2
      exit 1
    '';
  };

  cfgOk = baytLib.mkConfiguration {
    inherit pkgs;
    modules = [
      self.modules.standalone
      {
        home.username = "alice";
        home.homeDirectory = homeDir;
        bayt.linker = smfh;
        bayt.files.".config/foo".text = "v1";
      }
    ];
  };

  cfgFail = baytLib.mkConfiguration {
    inherit pkgs;
    modules = [
      self.modules.standalone
      {
        home.username = "alice";
        home.homeDirectory = homeDir;
        bayt.linker = failingLinker;
        bayt.files.".config/foo" = {
          text = "v2";
          clobber = true;
        };
      }
    ];
  };
in
  pkgs.runCommandLocal "bayt-standalone-failed-activation" {} ''
    export HOME=${homeDir}
    mkdir -p "$HOME"

    ${cfgOk.activationPackage}/bin/bayt-activate
    cp "${stateManifest}" state-before.json
    grep -q 'v1' "$HOME/.config/foo"

    if ${cfgFail.activationPackage}/bin/bayt-activate; then
      echo "expected activation failure" >&2
      exit 1
    fi

    cmp state-before.json "${stateManifest}"
    grep -q 'v1' "$HOME/.config/foo"

    touch "$out"
  ''
