{
  lib,
  nix-darwin,
  pkgs,
  self,
}: let
  baytLib = self.lib.forSystem "aarch64-darwin";
  eval = nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      self.darwinModules.default
      {
        system.stateVersion = 6;

        users.users.alice = {
          name = "alice";
          home = "/Users/alice";
        };

        bayt.users.alice = {
          enable = true;
          files.".zshrc".text = "export EDITOR=nvim";
          xdg.config.files."nvim/init.lua".text = "print(\"hello\")";
        };
      }
    ];
  };

  agent = eval.config.launchd.user.agents.bayt-activate;
  kick = eval.config.system.activationScripts.bayt-activate-kick.text;
  manifest = baytLib.manifestDataForUser eval.config.bayt.users.alice;
  failures = [
    {
      name = "sharedActivationAgentPresent";
      condition = agent.serviceConfig.Label == "org.bayt.activate";
    }
    {
      name = "sharedActivationUsesGeneratedProgram";
      condition = lib.hasPrefix "/nix/store/" agent.serviceConfig.Program;
    }
    {
      name = "sharedActivationUsesPackagedActivatorEntryPoint";
      condition = lib.hasInfix "/bin/bayt-activate" agent.serviceConfig.Program;
    }
    {
      name = "sharedActivationLinksRegularFile";
      condition = builtins.any (file: file.target == "/Users/alice/.zshrc") manifest.files;
    }
    {
      name = "sharedActivationLinksXdgFile";
      condition = builtins.any (file: file.target == "/Users/alice/.config/nvim/init.lua") manifest.files;
    }
    {
      name = "sharedActivationKickTargetsAgentLabel";
      condition = lib.hasInfix agent.serviceConfig.Label kick;
    }
    {
      name = "sharedActivationKickTargetsConfiguredUser";
      condition = lib.hasInfix "alice" kick;
    }
  ];
  failedNames = map (check: check.name) (lib.filter (check: !check.condition) failures);
in
  assert failedNames == [];
    pkgs.runCommandLocal "bayt-darwin-adapter-eval" {} ''
      touch "$out"
    ''
