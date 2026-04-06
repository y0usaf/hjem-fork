{lib}: {
  pkgs,
  modules,
  specialArgs ? {},
  class ? "bayt-standalone",
  outputPath ? ["bayt"],
  requiredOutputs ? [
    "manifest"
    "activationPackage"
  ],
  errorMessage ? "bayt.lib.mkConfiguration requires a module graph exposing `${lib.concatStringsSep "." outputPath}` outputs `${lib.concatStringsSep ", " requiredOutputs}`.",
}: let
  eval = lib.evalModules {
    inherit class modules;
    specialArgs = specialArgs // {inherit pkgs;};
  };

  outputRoot = lib.attrByPath outputPath null eval.config;
  missingOutputs =
    if outputRoot == null
    then requiredOutputs
    else builtins.filter (name: !(builtins.hasAttr name outputRoot)) requiredOutputs;
in
  if missingOutputs != []
  then throw errorMessage
  else
    {
      inherit (eval) config options;
    }
    // builtins.listToAttrs (map (name: {
        inherit name;
        value = outputRoot.${name};
      })
      requiredOutputs)
