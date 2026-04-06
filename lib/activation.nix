{
  lib,
  pkgs,
}: let
  inherit (builtins) isAttrs toJSON;
  inherit (lib.meta) getExe;
  inherit (lib.strings) escapeShellArgs;
in rec {
  linkerArgs = linkerOptions:
    if linkerOptions == null
    then []
    else if isAttrs linkerOptions
    then let
      optionsFile = pkgs.writeText "bayt-linker-options.json" (toJSON linkerOptions);
    in [
      "--linker-opts"
      optionsFile
    ]
    else linkerOptions;

  linkerArgsString = linkerOptions: escapeShellArgs (linkerArgs linkerOptions);

  mkUnmanagedConflictCheckSnippet = {
    newManifestVar ? "new_manifest",
    oldManifestVar ? "old_manifest",
  }: let
    jq = getExe pkgs.jq;
    newManifestRef = "${"$"}${newManifestVar}";
    oldManifestRef = "${"$"}${oldManifestVar}";
  in ''
    while IFS= read -r target; do
      [ -n "$target" ] || continue

      if [ -e "$target" ] || [ -L "$target" ]; then
        if [ ! -f "${oldManifestRef}" ] || ! ${jq} -e --arg target "$target" '.files | any(.target == $target)' "${oldManifestRef}" >/dev/null; then
          echo "Refusing to replace unmanaged existing target '$target' while clobber = false" >&2
          exit 1
        fi
      fi
    done < <(${jq} -r '.files[]? | select((.clobber // false) | not) | select((.type // "symlink") == "symlink" or .type == "copy" or .type == "directory") | .target' "${newManifestRef}")
  '';

  mkLinkerSwitchSnippet = {
    linker,
    linkerOptions ? [],
    newManifestVar ? "new_manifest",
    oldManifestVar ? "old_manifest",
  }: let
    argsStr = linkerArgsString linkerOptions;
    newManifestRef = "${"$"}${newManifestVar}";
    oldManifestRef = "${"$"}${oldManifestVar}";
  in ''
    ${mkUnmanagedConflictCheckSnippet {
      inherit newManifestVar oldManifestVar;
    }}

    if [ ! -f "${oldManifestRef}" ]; then
      ${getExe linker} ${argsStr} activate "${newManifestRef}"
    else
      ${getExe linker} ${argsStr} diff "${newManifestRef}" "${oldManifestRef}"
    fi
  '';

  standaloneStateDir = {
    homeDirectory,
    isDarwin ? pkgs.stdenv.hostPlatform.isDarwin,
  }:
    if isDarwin
    then "${homeDirectory}/Library/Application Support/Bayt"
    else "${homeDirectory}/.local/state/bayt";

  standaloneStateManifestPath = args: "${standaloneStateDir args}/manifest.json";

  mkActivationPackage = {
    name ? "bayt-activate",
    linker,
    linkerOptions ? [],
    manifest,
    stateManifest,
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        bash
        coreutils-full
      ];
      text = ''
        set -euo pipefail

        new_manifest="${manifest}"
        state_manifest="${stateManifest}"

        mkdir -p "$(dirname "$state_manifest")"

        ${mkLinkerSwitchSnippet {
          inherit linker linkerOptions;
          newManifestVar = "new_manifest";
          oldManifestVar = "state_manifest";
        }}

        cp -f "$new_manifest" "$state_manifest"
      '';
    };
}
