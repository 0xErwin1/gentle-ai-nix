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

       providers = {
         opencode.enable = true;
         claude-code.enable = true;
       };

       components = {
         skills.enable = true;
         persona.enable = true;
         permissions.enable = true;
         sdd.enable = true;
         engram.enable = true;
       };

       persona = "neutral";
       sdd.mode = "single";
     };
   }
   ```

3. Switch, then restart your clients. They read agents, commands, skills and settings only at startup.

A document Gentle AI rejects fails the build with its diagnostics, so an invalid declaration never reaches your home directory.

## What you declare

Options are grouped the way you think about the installation. Names inside the groups are Gentle AI's own ids and are deliberately not enumerated here: Gentle AI rejects one it does not know rather than ignoring it, so anything it gains works the day it ships.

| Group | Purpose |
|-------|---------|
| `providers.<name>` | A client, with `skills`, `settings` and `models` for it alone. |
| `components.<name>` | What Gentle AI configures — skills, persona, permissions, sdd, theme, engram, gga. |
| `skills.<name>` | Naming none installs every skill Gentle AI ships. Entries only narrow that: `false` drops one, `true` restricts to the ones named. |
| `communityTools.<name>`, `openCodePlugins.<name>` | The optional extras, same shape. |
| `roles.<id>` | Logical agent roles. `references` name ids, so renaming one is a single edit. |
| `sdd`, `review`, `install`, `backgroundSubagents` | Workflow modes, the review kill switch, scope and channel, background policy. |
| `models` | Assignments the contract keeps outside a provider, plus `codexPreset` — name one of Gentle AI's own model profiles instead of restating the models it resolves to. |
| `permissions`, `mcpServers` | Rules layered over the shipped guardrails, and servers no component configures. |
| `persona`, `preset`, `schemaVersion`, `package` | The rest. |

Engram is a component, not something to wire by hand: `components.engram.enable` is what configures the MCP server, the plugin and the protocol section in every client that takes them. Nix supplies the binary through `engramPackage` so nothing is downloaded at activation.

## Editing the harness

A wrapper you cannot edit is a worse harness than the one you wrote yourself. Three ways in, cheapest first.

| You want to | Use |
|-------------|-----|
| Add a skill, agent or command Gentle AI does not ship | `extraFiles."<path>".source` |
| Replace a file Gentle AI does ship | `extraFiles."<path>".text` — same path, your content wins |
| Keep a section of your own in a file Gentle AI regenerates | `extraFiles.<name> = { target; mode = "append"; text; }` |
| Change a provider's own settings | `providers.<name>.settings` |
| Reach a contract field newer than this module | `settings` — raw `selection`, merged last |
| Anything else | `overrideRendered` — a function over the rendered derivation |

```nix
programs.gentle-ai = {
  extraFiles.".config/opencode/skills/house-style/SKILL.md".source = ./house-style.md;
  extraFiles.".claude/agents/gentle-apply.md".text = "---\nname: gentle-apply\n---\nMy own prompt.\n";

  overrideRendered = rendered: pkgs.runCommandLocal "patched" { } ''
    cp -r --no-preserve=mode,ownership ${rendered} "$out"
    substituteInPlace "$out/tree/.config/opencode/AGENTS.md" --replace-warn "Gentle AI" "Our harness"
  '';
};
```

`extraFiles` is layered onto the rendered tree rather than declared as a second `home.file` entry, which is what makes overriding a generated file possible at all: two Home Manager entries for one path collide instead of layering.

See [`examples/home.nix`](examples/home.nix) for a configuration using all of it.

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

This flake calls `gentle-ai config render`, the declarative configuration contract from [Gentle AI issue #3248](https://github.com/Gentleman-Programming/gentle-ai/issues/3248). It is not in an upstream release yet, so `packages/gentle-ai.nix` is pinned to the branch chain carrying it. Once the contract merges, move `owner`, `rev` and `hash` back to an upstream tag; nothing else changes. Override `programs.gentle-ai.package` to build from somewhere else in the meantime.

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
