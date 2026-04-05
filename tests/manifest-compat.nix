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
          inherit linker;
          files = {
            ".config/foo".text = "hello";
            ".config/disabled" = {
              enable = false;
              text = "nope";
            };
            copy-me = {
              type = "copy";
              text = "copy";
            };
            delete-me.type = "delete";
            dir-me.type = "directory";
            modify-me = {
              type = "modify";
              permissions = "703";
            };
          };

          xdg.config.files."app/settings.json".text = "{}";
        };
      }
    ];
  };
  linker = smfh;
in
  pkgs.runCommandLocal "bayt-manifest-compat" {
    nativeBuildInputs = with pkgs; [
      cue
      jq
    ];
  } ''
    manifest=${cfg.manifest}/manifest.json

    test -f "$manifest"
    jq -e '.version == 3' "$manifest" >/dev/null
    jq -e '.files | any(.target == "${homeDir}/.config/foo")' "$manifest" >/dev/null
    jq -e '.files | any(.target == "${homeDir}/.config/app/settings.json")' "$manifest" >/dev/null
    jq -e '.files | any(.target == "${homeDir}/.config/disabled") | not' "$manifest" >/dev/null
    jq -e '.files | any(.target == "${homeDir}/copy-me" and .type == "copy")' "$manifest" >/dev/null
    jq -e '.files | any(.target == "${homeDir}/delete-me" and .type == "delete")' "$manifest" >/dev/null
    jq -e '.files | any(.target == "${homeDir}/dir-me" and .type == "directory")' "$manifest" >/dev/null
    jq -e '.files | any(.target == "${homeDir}/modify-me" and .type == "modify" and .permissions == "703")' "$manifest" >/dev/null
    jq -e 'all(.files[]; (.enable? // null) == null and (.text? // null) == null)' "$manifest" >/dev/null
    cue vet -c ${../manifest/v3.cue} "$manifest"

    touch "$out"
  ''
