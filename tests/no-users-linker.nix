{
  baytModule,
  baytTest,
  smfh,
}: let
  user = "alice";
  userHome = "/home/${user}";
in
  baytTest {
    name = "bayt-no-users-linker";
    nodes = {
      node1 = {
        imports = [baytModule];

        # ensure nixless deployments work
        nix.enable = false;

        users.groups.${user} = {};
        users.users.${user} = {
          isNormalUser = true;
          home = userHome;
          password = "";
        };

        bayt = {
          linker = smfh;
          users = {
            ${user} = {
              enable = false;
              files.".config/foo".text = "Hello world!";
            };
          };
        };
      };
    };

    testScript = _: ''
      node1.succeed("loginctl enable-linger ${user}")
    '';
  }
