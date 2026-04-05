{
  pkgs,
  self,
  smfh,
}: let
  outputs = self.lib.mkStandaloneConfigurations {
    system = pkgs.stdenv.hostPlatform.system;
    configurations = {
      alice = {
        inherit pkgs;
        modules = [
          {
            home.username = "alice";
            home.homeDirectory = "/build/alice";

            bayt = {
              linker = smfh;
              files.".test".text = "hello";
            };
          }
        ];
      };

      bob = {
        inherit pkgs;
        modules = [
          {
            home.username = "bob";
            home.homeDirectory = "/build/bob";

            bayt = {
              linker = smfh;
              files.".test".text = "world";
            };
          }
        ];
      };
    };
  };
in
  pkgs.runCommandLocal "bayt-standalone-configuration-outputs" {
    nativeBuildInputs = [pkgs.jq];
  } ''
    test -f ${outputs.alice.manifest}/manifest.json
    test -x ${outputs.alice.activationPackage}/bin/bayt-activate
    test -f ${outputs.bob.manifest}/manifest.json
    test -x ${outputs.bob.activationPackage}/bin/bayt-activate

    jq -e '.files | any(.target == "/build/alice/.test")' ${outputs.alice.manifest}/manifest.json >/dev/null
    jq -e '.files | any(.target == "/build/bob/.test")' ${outputs.bob.manifest}/manifest.json >/dev/null

    touch "$out"
  ''
