{
  fileToJson,
  lib,
  pkgs,
}: let
  inherit (builtins) attrValues concatMap filter map toJSON;
  inherit (lib.meta) getExe;
in rec {
  userFileSets = user: [
    user.files
    user.xdg.cache.files
    user.xdg.config.files
    user.xdg.data.files
    user.xdg.state.files
  ];

  manifestDataForUser = user: {
    version = 3;
    files =
      concatMap (files:
        map fileToJson (filter (file: file.enable) (attrValues files))) (userFileSets user);
  };

  writeManifest = {
    user,
    name ? "manifest-${user.name}.json",
    destination ? "/${name}",
  }:
    pkgs.writeTextFile {
      inherit name destination;
      text = toJSON (manifestDataForUser user);
      checkPhase = ''
        set -e
        CUE_CACHE_DIR=$(pwd)/.cache
        CUE_CONFIG_DIR=$(pwd)/.config

        ${getExe pkgs.cue} vet -c ${../manifest/v3.cue} $target
      '';
    };

  mkManifestDirectory = users:
    pkgs.symlinkJoin {
      name = "bayt-manifests";
      paths = map (user: writeManifest {inherit user;}) (attrValues users);
    };
}
