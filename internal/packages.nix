{
  pkgs,
  smfh,
  ...
}: {
  # Expose the 'smfh' instance used by Bayt as a package.
  # This allows consuming the exact copy of smfh used by Bayt.
  inherit smfh;
}
