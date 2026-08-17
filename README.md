# Gentle AI for Home Manager

Declare a Gentle AI installation in your Home Manager configuration and let Gentle AI decide what that means on disk. This flake carries no knowledge of agents, skills, commands or provider file layouts: it hands your declaration to `gentle-ai config render` and projects the result. A change to how Gentle AI renders its own assets arrives with the package, not with a matching change here.

## Quick path

1. Add the input to your flake:

   ```nix
   inputs.gentle-ai-nix.url = "github:0xErwin1/gentle-ai-nix";
   inputs.gentle-ai-nix.inputs.nixpkgs.follows = "nixpkgs";
   ```

2. Import the module and declare what you want:

   ```nix
   {
     imports = [ inputs.gentle-ai-nix.homeManagerModules.default ];

     programs.gentle-ai = {
       enable = true;
       settings = {
         agents = [ "opencode" "claude-code" ];
         components = [ "skills" "persona" "permissions" "sdd" "theme" ];
         persona = "neutral";
         sddMode = "single";
       };
     };
   }
   ```

3. Switch, then restart your clients. They read agents, commands, skills and settings only at startup.

A document Gentle AI rejects fails the build with its diagnostics, so an invalid declaration never reaches your home directory.

## What you declare

`settings` is the `selection` block of the Gentle AI desired-state document, passed through verbatim. Any field the contract accepts works here without this flake knowing it exists — and Gentle AI rejects an unknown field rather than ignoring it, so a typo is a build failure.

| Option | Purpose |
|--------|---------|
| `settings` | Clients, components, skills, persona, preset, SDD mode, MCP servers, permissions, model assignments. |
| `roles` | Logical agent roles. `references` name role ids, so renaming a role is one edit and every generated reference follows. |
| `extensions` | Provider-specific configuration the neutral contract does not model, keyed by adapter. |
| `schemaVersion` | The contract version this document is written against. Pinning it turns an incompatible upgrade into a build failure instead of a silent reinterpretation. |
| `package` | The Gentle AI package. It both renders the configuration and is installed, so what runs matches what was rendered. |

See [`examples/home.nix`](examples/home.nix) for a configuration using all of them.

## How it works

```
programs.gentle-ai.settings ─┐
programs.gentle-ai.roles ────┼─► gentle-ai.json ─► gentle-ai config render ─► store tree ─► home.file
programs.gentle-ai.extensions┘
```

| Decision | Why |
|----------|-----|
| Rendering happens in a derivation | The result is a store path: reproducible, cacheable, and inspectable through `programs.gentle-ai.rendered` before it is linked. |
| The document carries your home directory | Rendered content records absolute paths to its own files, so it is built for the directory it will live in rather than for the build sandbox. |
| The tree is linked recursively | Every file is its own symlink, so unrelated files in the same directories are left alone and a genuine collision is reported instead of one module shadowing another's directory. |
| Nothing is rewritten at activation | Activation only links what was already rendered and verified at build time. |

## Requirements

This flake calls `gentle-ai config render`, which is the declarative configuration contract from [Gentle AI issue #3248](https://github.com/Gentleman-Programming/gentle-ai/issues/3248). Pin `packages/gentle-ai.nix` — or `programs.gentle-ai.package` — to a Gentle AI revision that provides it. A package without it fails the build when the renderer runs, naming the missing command.

## Checklist

- [ ] `nix flake check` passes against your pinned Gentle AI package.
- [ ] `nix build .#homeConfigurations.<name>.activationPackage` succeeds before switching.
- [ ] Every adapter named in `roles`, `settings.skillAssignments` or `extensions` also appears in `settings.agents`.
- [ ] Clients were restarted after the switch.

## Next step

Inspect what your declaration produces without switching:

```console
nix eval --raw .#homeConfigurations.<name>.config.programs.gentle-ai.rendered
```
