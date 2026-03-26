pkgs:
pkgs.mkShell {
  name = "bayt-devshell";
  packages = builtins.attrValues {
    inherit
      (pkgs)
      # formatter
      alejandra
      # cue validator
      cue
      go
      ;
  };
}
