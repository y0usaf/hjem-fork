{
  lib,
  writeManifest,
  mkActivationPackage,
  standaloneStateManifestPath,
}: let
  mkConfigurationOutputs = {
    configurations,
    attrPath ? ["bayt"],
    requiredOutputs ? [
      "manifest"
      "activationPackage"
    ],
  }:
    lib.mapAttrs (_: configuration: let
      outputRoot = lib.attrByPath attrPath null configuration.config;
      missingOutputs =
        if outputRoot == null
        then requiredOutputs
        else builtins.filter (name: !(builtins.hasAttr name outputRoot)) requiredOutputs;
    in
      if missingOutputs != []
      then throw "bayt.lib.mkConfigurationOutputs expected `${lib.concatStringsSep "." attrPath}` to expose outputs `${lib.concatStringsSep ", " requiredOutputs}`."
      else outputRoot)
    configurations;

  mkUserOutputs = {
    user,
    linker,
    linkerOptions ? [],
    stateManifest,
    manifestName ? "manifest-${user.name}.json",
  }: let
    manifest = writeManifest {
      inherit user;
      name = manifestName;
    };
  in {
    inherit manifest stateManifest;
    manifestFile = "${manifest}/${manifestName}";
    activationPackage = mkActivationPackage {
      inherit linker linkerOptions stateManifest;
      manifest = "${manifest}/${manifestName}";
    };
  };

  mkPerUserOutputs = {
    users,
    linker,
    linkerOptions ? [],
    isDarwin,
    manifestName ? "manifest.json",
  }:
    lib.mapAttrs (_: user:
      mkUserOutputs {
        inherit user linker linkerOptions manifestName;
        stateManifest = standaloneStateManifestPath {
          homeDirectory = user.directory;
          inherit isDarwin;
        };
      })
    users;
in {
  inherit mkConfigurationOutputs mkUserOutputs mkPerUserOutputs;
}
