<!-- markdownlint-disable MD033 MD041 -->

<div id="doc-begin" align="center">
  <h1 id="header">
    <pre>Bayt [بَيْت]</pre>
  </h1>
  <p>
    A streamlined way to manage your <code>$HOME</code> with Nix.
  </p>
  <br/>
  <a href="#what-is-this">Synopsis</a><br/>
  <a href="#features">Features</a> | <a href="#module-interface">Interface</a><br/>
  <a href="#things-to-do">Future Plans</a>
  <br/>
</div>

## What is this?

[systemd-tmpfiles]: https://www.freedesktop.org/software/systemd/man/latest/systemd-tmpfiles-setup.service.html
[smfh]: https://github.com/feel-co/smfh

**Bayt** (بَيْت, "home" in Arabic) is a module system that implements a simple and
streamlined way to manage files in your `$HOME`, such as but not limited to
files in your `~/.config`. Bayt aims to be an alternative,
easy-to-grasp utility for managing your `$HOME` purely and safely.

### Features

1. Powerful `$HOME` management functionality and potential
2. Small and simple codebase with minimal abstraction
3. Robust, safe and _manifest based_ file handling with [smfh]
4. Multi-user by design, works with any number of users
5. Designed for ease of extensibility and integration

### Implementation

Bayt exposes a streamlined interface with multi-tenant capabilities, which you
may use to manage individual users' homes by leveraging the module system.

```nix
{ inputs, lib, pkgs, ... }:
{
  /*
    other NixOS configuration here...
  */

  bayt = {
    users = {
      alice = {
        enable = true;

        files = {
          # Write a text file in `/home/alice/.foo`
          # with the contents bar
          ".foo".text = "bar";

          # Alternatively, create the file source using a writer.
          # This can be used to generate config files with various
          # formats expected by different programs.
          ".bar".source = pkgs.writeText "file-foo" "file contents";

          # You can also use generators to transform Nix values
          ".baz" = {
            # Works with `pkgs.formats` too!
            generator = lib.generators.toJSON { };
            value = {
              some = "contents";
            };
          };
        };

        # this will write into `/home/alice/.config/test/bar.json`
        xdg.config.files."test/bar.json" = {
          generator = lib.generators.toJSON { };
          value = {
            foo = 1;
            bar = "Hello world!";
            baz = false;
          };
          # overwrite existing unmanaged file, if present
          clobber = true;
        };
      };
    };
  };
}
```

> [!NOTE]
> Each attribute under `bayt.users`, e.g., `bayt.users.alice` or
> `bayt.users.jane` represent a user managed via `users.users` in NixOS. If a
> user does not exist, then Bayt will refuse to manage their `$HOME` by
> filtering non-existent users in file creation.

## Module Interface

The interface for the `bayt` module is conceptually very similar to prior art
(e.g., Home Manager), but it does not act as a collection of modules like Home
Manager. Instead, we implement minimal features, and leave
application-specific abstractions to the user to do as they see fit.

```sh
$ nix eval .#nixosConfigurations.test.config.bayt.users.alice.files.'".foo"' --json | jq
{
  "clobber": false,
  "enable": true,
  "executable": false,
  "generator": null,
  "relativeTo": "/home/alice",
  "source": "/nix/store/22yfhzhk0w5mgaq6c943vimsg6qlr1sh-foo",
  "target": "/home/alice/.foo",
  "text": "bar",
  "value": null
}
```

### Standalone outputs

For standalone evaluation, Bayt exposes helpers that return buildable outputs like `manifest` and `activationPackage`.
A minimal downstream flake pattern is:

```nix
{
  outputs = { self, nixpkgs, bayt, ... }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    baytConfigurations = bayt.lib.mkStandaloneConfigurations {
      inherit system;
      configurations.yousaf = {
        inherit pkgs;
        modules = [
          {
            home.username = "yousaf";
            home.homeDirectory = "/home/yousaf";

            bayt = {
              linker = bayt.packages.${system}.smfh;
              files.".zshrc".text = "export EDITOR=nvim";
            };
          }
        ];
      };
    };
  };
}
```

This enables builds such as:

```sh
nix build .#baytConfigurations.yousaf.activationPackage
```

If you only need one standalone config, `bayt.lib.mkStandaloneConfiguration` and `bayt.lib.forSystem system.mkStandaloneConfiguration` are also available. `bayt.lib.mkConfiguration` remains the lower-level primitive when you want to assemble the module graph yourself.

### Linker Implementation

Bayt relies on [smfh], an atomic and reliable file creation tool designed by
[Gerg-l]. We utilize smfh and Systemd services [^1] to correctly link files
into place.

[^1]: Which is preferable to hacky activation scripts that may or may not break.
    Systemd services allow for ordered dependency management across all
    services, and easy monitoring of Bayt-related services from the central
    `systemctl` interface.

### Environment Management

Bayt does **not** manage user environments as one might expect, but it provides
a convenient `environment.sessionVariables` option that you can use to store
your variables. This script will be used to store your environment variables in
a POSIX-compliant script generated by Bayt, which you can source in your shell
configurations. Optionally, set `environment.autoSource = true` to have Bayt
source it automatically on login via `/etc/profile.d/`.

## Usage without flakes

| With flakes | Without flakes |
| --- | --- |
| `nix flake check` | `nix-build -A checks` |
| `nix develop` | `nix-shell -A shell` |
| `nix build .#smfh` | `nix-build -A packages.smfh` |
| `nix fmt` | `nix run -f . formatter` |

You can also `import` the root of the repo and get all of the same attributes as the flake (without `system`).

<details>
<summary>Things to do / upstream notes</summary>

Bayt is _mostly_ feature-complete, in the sense that it is a clean
implementation of `home.files` in Home Manager: it was never a goal to dive into
abstracting files into modules.

[Gerg-l]: https://github.com/gerg-l

Bayt previously utilized [systemd-tmpfiles] before switching to [smfh]
developed by [Gerg-l]. You can set `bayt.linker` to use a custom linker if desired.

</details>

## Attributions

[Nixpkgs]: https://github.com/nixOS/nixpkgs
[Home Manager]: https://github.com/nix-community/home-manager

Special thanks to [Nixpkgs] and [Home Manager]. The interface of the
`bayt.users` module is inspired by Home Manager's `home.file` and Nixpkgs'
`users.users` modules.

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE).

<div align="right">
  <a href="#doc-begin">Back to the Top</a>
  <br/>
</div>
