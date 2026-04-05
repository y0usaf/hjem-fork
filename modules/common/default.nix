{baseModule}: rec {
  bayt = {
    imports = [
      bayt-lib
      baseModule
    ];
  };

  bayt-lib = {
    lib,
    pkgs,
    ...
  }: {
    _module.args.bayt-lib = import ../../lib.nix {inherit lib pkgs;};
  };

  default = bayt;
}
