{
  pkgs,
  self,
  smfh,
}: let
  baytLib = self.lib;
  homeDir =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/private/tmp/alice"
    else "/build/alice";
  cfg = baytLib.mkConfiguration {
    inherit pkgs;
    modules = [
      self.modules.standalone
      {
        home.username = "alice";
        home.homeDirectory = homeDir;

        bayt = {
          linker = smfh;
          files.".config/foo".text = "hello";
          xdg.config.files."app/settings.json".text = "{}";
        };
      }
    ];
  };
in
  pkgs.runCommandLocal "bayt-standalone-mkconfiguration" {
    nativeBuildInputs = with pkgs; [
      cue
      jq
    ];
  } ''
    manifest=${cfg.manifest}/manifest.json

    test -f "$manifest"
    test -x ${cfg.activationPackage}/bin/bayt-activate
    jq -e '.files | any(.target == "${homeDir}/.config/foo")' "$manifest" >/dev/null
    jq -e '.files | any(.target == "${homeDir}/.config/app/settings.json")' "$manifest" >/dev/null
    cue vet -c ${../manifest/v3.cue} "$manifest"

    touch "$out"
  ''
