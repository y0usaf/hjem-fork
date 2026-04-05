# Bayt standalone switch plan

## Goal

Preserve Bayt's current functionality while refactoring it around a shared core that can also support standalone switching outside a full system rebuild.

### Preserve

- NixOS multi-user support
- nix-darwin support
- current `bayt.users.<name>` interface
- XDG file support
- manifest-based linking
- `smfh` as the default linker backend
- system activation integration

### Add

- a shared standalone-first core
- a standalone configuration entrypoint
- eventually a `bayt switch` command

## Design principles

### 1. Minimalist but not reduced

Bayt should stay focused on three jobs:

1. evaluate home-file configuration
2. build a manifest
3. apply that manifest safely

We do **not** want Bayt to turn into a second Home Manager or grow a large app/module ecosystem in core.

### 2. Preserve capability, simplify architecture

The target is not fewer features. The target is:

- less duplicated logic
- fewer platform-specific implementations owning core behavior
- one shared manifest builder
- one shared activation engine
- thin NixOS and nix-darwin adapters

### 3. Keep SMFH

`smfh` is a good linker backend and should remain the default. The refactor should focus on Bayt's evaluation, manifest, activation, and state handling around `smfh`, not on replacing the linker.

## High-level architecture

Bayt should be split into:

- **Core**: evaluate config, normalize files, build manifests, build activation package, switch safely
- **Adapters**: NixOS and nix-darwin wrappers that translate system config into per-user Bayt configurations and hook the shared activation package into system activation

### Proposed direction

```text
lib/
  types.nix
  manifest.nix
  activation.nix
  configuration.nix

modules/
  standalone/default.nix
  common/file.nix
  common/xdg.nix
  nixos/default.nix
  nix-darwin/default.nix

bin/
  bayt
```

This should stay intentionally small.

## Public model

### Existing system-backed model remains

Keep supporting:

- `bayt.users.<name>`
- all current file/XDG/environment options
- `bayt.linker`
- `bayt.linkerOptions`

### New standalone model

Add a standalone single-user config model such as:

```nix
{
  home.username = "yousaf";
  home.homeDirectory = "/home/yousaf";

  bayt.files.".zshrc".text = ''
    export EDITOR=nvim
  '';

  bayt.xdg.config.files."nvim/init.lua".text = ''
    print("hello")
  '';
}
```

Standalone mode should be **single-user only**. Multi-user orchestration belongs in the NixOS/nix-darwin adapters.

## Core API target

Expose a public library entrypoint like:

```nix
bayt.lib.mkConfiguration {
  system = "x86_64-linux";
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  modules = [
    bayt.modules.standalone
    ./home/bayt.nix
  ];
  specialArgs = { };
}
```

Return something like:

```nix
{
  config = ...;
  options = ...;
  manifest = ...;
  activationPackage = ...;
}
```

This shared entrypoint should become the heart of Bayt.

## Activation model

The shared activation package should:

1. locate the new manifest
2. locate the prior saved manifest
3. run `smfh activate` on first activation
4. run `smfh diff` on subsequent activations
5. update Bayt state only after successful activation

### Minimal state model

Start simple:

- Linux: `~/.local/state/bayt/manifest.json`
- Darwin: `~/Library/Application Support/Bayt/manifest.json`

Do **not** start with generations/rollback unless needed later.

## Migration strategy

### Phase 0: guardrails

Define invariants before refactoring.

#### Compatibility promises

- existing NixOS configs keep working
- existing Darwin configs keep working
- manifest format remains unchanged unless absolutely necessary
- `smfh` remains the default linker backend
- current file features are preserved

#### Core invariants

- same config => same manifest semantics
- repeated activation is safe
- removed entries are removed correctly
- unmanaged files are only replaced when `clobber = true`
- saved state is updated only after a successful activation

### Phase 1: extract shared internals

Add shared helpers such as:

- `lib/types.nix`
- `lib/manifest.nix`
- `lib/activation.nix` or `lib/linker.nix`

Move into shared code:

- manifest generation
- linker option normalization
- activation script generation

Use them from both:

- `modules/nixos/base.nix`
- `modules/nix-darwin/base.nix`

#### Outcome

No user-facing changes yet. Current behavior should remain the same.

### Phase 2: introduce standalone evaluation

Add:

- `modules/standalone/default.nix`
- `lib/configuration.nix`

Support standalone evaluation and buildable outputs:

- manifest
- activation package

This is additive only.

### Phase 3: refactor adapters

Refactor NixOS and nix-darwin so they:

1. translate existing per-user config into the shared standalone-style core
2. call `bayt.lib.mkConfiguration`
3. wire the resulting activation package into systemd/launchd

After this phase, platform modules become wrappers, not owners of core logic.

### Phase 4: add standalone activation package

Expose a buildable activation output for standalone configs.

Target shape:

```bash
nix build .#baytConfigurations.yousaf.activationPackage
```

### Phase 5: add `bayt switch`

Only after the shared core is tested.

Minimal first version:

- current user only
- flake input
- one state dir
- `smfh`

Example target UX:

```bash
nix run .#bayt -- switch --flake .#yousaf
```

### Phase 6: optional later work

Only if still desirable:

- generations
- rollback
- history/listing
- dry-run niceties

These are not required for the standalone-switch goal.

## What not to do

To keep the project minimalist and safe, avoid:

- dropping current features
- redesigning all public options at once
- introducing full Home Manager-style complexity
- adding lots of CLI subcommands early
- mixing architectural refactor with many unrelated features
- making standalone mode multi-user

## Testing strategy

Testing should be first-class and should focus on Bayt's invariants around `smfh`, not on replacing `smfh`.

### Layer 1: evaluation tests

Validate:

- `text` -> store path generation
- `generator + value`
- target path resolution
- XDG placement
- `enable = false`
- file type handling
- environment/session script generation

### Layer 2: manifest tests

Validate:

- manifest structure
- CUE validation
- omitted null fields
- file type encoding
- disabled entries omitted

### Layer 3: activation integration tests

Validate:

- first activation
- activation with no changes
- activation after content changes
- removal of deleted managed files
- `clobber = false`
- `clobber = true`
- state update behavior
- idempotency

### Layer 4: CLI/UX tests

Validate:

- flake resolution
- helpful failures
- missing home metadata
- build/switch flow

## Initial acceptance tests

The initial standalone-capable design should at minimum prove:

1. basic file appears after switch
2. changing file content updates target
3. removing a file from config removes the managed target
4. unmanaged file is preserved when `clobber = false`
5. unmanaged file is replaced when `clobber = true`
6. XDG config path lands in the correct location
7. running switch twice is idempotent
8. state manifest is updated after successful switch
9. failed switch does not corrupt current state
10. manifest validates against CUE

## First PR recommendation

Start with a small, compatibility-preserving refactor.

### PR 1

Add:

- shared manifest builder
- shared linker/activation helpers

Change:

- `modules/nixos/base.nix` to use the shared manifest builder
- `modules/nix-darwin/base.nix` to use the shared manifest builder

Do **not** add a new CLI or standalone UX yet.

### PR 2

Add:

- standalone module
- `mkConfiguration`
- buildable standalone manifest and activation package

### PR 3

Add:

- `bin/bayt`
- flake app/package
- minimal `bayt switch`

## Summary

The plan is to:

- keep Bayt's current feature set
- refactor Bayt around one shared core
- keep `smfh`
- make NixOS and nix-darwin thin wrappers over that core
- add standalone switching only after the shared internals are tested and stable

This should preserve Bayt's minimalist spirit while making it more flexible, more maintainable, and likely more efficient for home-only updates.
