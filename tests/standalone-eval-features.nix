{
  pkgs,
  self,
  smfh,
}: let
  baytLib = self.lib;
  homeDir =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "/private/tmp/bayt-eval"
    else "/build/bayt-eval";
  stateDir = "${homeDir}/.bayt-state";
  cfg = baytLib.mkConfiguration {
    inherit pkgs;
    specialArgs = {
      greeting = "hello from specialArgs";
    };
    modules = [
      self.modules.standalone
      ({
        greeting,
        lib,
        ...
      }: {
        home.username = "alice";
        home.homeDirectory = homeDir;

        bayt = {
          linker = smfh;
          linkerOptions = {
            mode = "json";
          };
          stateDir = stateDir;
          packages = [pkgs.hello];
          environment.sessionVariables = {
            EDITOR = "nvim";
          };
          files.".special".text = greeting;
          xdg.config.directory = "${homeDir}/.config-custom";
          xdg.config.files."generated.json" = {
            generator = lib.generators.toJSON {};
            value = {
              answer = 42;
            };
          };
        };
      })
    ];
  };
  missingOutputsEval = builtins.tryEval (
    baytLib.mkConfiguration {
      inherit pkgs;
      modules = [
        {
          options.bayt = pkgs.lib.mkOption {
            type = pkgs.lib.types.submodule {};
          };

          config.bayt.manifest = pkgs.writeText "manifest.json" "{}";
        }
      ];
    }
  );
in
  assert !missingOutputsEval.success;
    pkgs.runCommandLocal "bayt-standalone-eval-features" {
      nativeBuildInputs = with pkgs; [
        jq
      ];
    } ''
      manifest=${cfg.manifest}/manifest.json
      load_env=${cfg.config.bayt.environment.loadEnv}
      activate=${cfg.activationPackage}/bin/bayt-activate

      test -f "$manifest"
      test -f "$load_env"
      test -x "$activate"

      grep -q 'export EDITOR="nvim"' "$load_env"
      grep -q 'export XDG_CONFIG_HOME="${homeDir}/.config-custom"' "$load_env"

      jq -e '.files | any(.target == "${homeDir}/.special")' "$manifest" >/dev/null
      jq -e '.files | any(.target == "${homeDir}/.config-custom/generated.json")' "$manifest" >/dev/null

      grep -q -- '--linker-opts' "$activate"
      grep -q '${stateDir}/manifest.json' "$activate"
      grep -q '${cfg.manifest}/manifest.json' "$activate"

      test ${toString (builtins.length cfg.config.bayt.packages)} -eq 1

      manifest_path='${cfg.config.bayt.manifestFile}'
      state_manifest_path='${cfg.config.bayt.stateManifest}'

      test "$manifest_path" = "${cfg.manifest}/manifest.json"
      test "$state_manifest_path" = "${stateDir}/manifest.json"
      grep -q "$manifest_path" "$activate"
      grep -q "$state_manifest_path" "$activate"

      touch "$out"
    ''
