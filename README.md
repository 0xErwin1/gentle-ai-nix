# Gentle AI for Home Manager

This flake installs Gentle AI, OpenCode, and Engram, then composes the public Gentle AI OpenCode harness through Home Manager's native `programs.opencode` module. It keeps user settings additive and provides deterministic `AGENTS.md` fragments without activation-time rewriting.

## Quick Start

Add the inputs to your flake:

```nix
{
  inputs = {
    gentle-ai-nix.url = "github:0xErwin1/gentle-ai-nix";
    gentle-ai-nix.inputs.nixpkgs.follows = "nixpkgs";
    gentle-ai-nix.inputs.home-manager.follows = "home-manager";
  };
}
```

Import and enable the module:

```nix
{
  imports = [ inputs.gentle-ai-nix.homeManagerModules.default ];
  programs.gentle-ai.enable = true;
}
```

Apply your normal Home Manager configuration, then restart OpenCode. OpenCode reads settings, agents, commands, skills, and plugins only at process startup.

## What It Manages

The default configuration:

- installs pinned Gentle AI and Engram packages;
- enables `programs.opencode` with the nixpkgs OpenCode package;
- adds the Gentle AI orchestrator and SDD/review agents through `programs.opencode.settings`;
- adds SDD commands and skills through native Home Manager options;
- configures the local Engram MCP server as `engram mcp --tools=agent`;
- projects upstream Gentle AI and Engram local plugins;
- composes the public persona and Engram protocol into OpenCode's `AGENTS.md`.

It does not configure providers, credentials, models, private policy, or unrelated AI clients.

## Options

| Option | Default | Purpose |
|---|---:|---|
| `programs.gentle-ai.enable` | `false` | Enable the integration. |
| `programs.gentle-ai.package` | pinned package | Gentle AI package, or `null` to skip installation. Its `src` supplies harness assets by default. |
| `programs.gentle-ai.source` | `null` | Explicit Gentle AI harness source override. |
| `programs.gentle-ai.sourceVersion` | `null` | Required version for an explicit source; must match a non-null package. |
| `programs.gentle-ai.opencode.enable` | `true` | Enable OpenCode and project the harness. |
| `programs.gentle-ai.opencode.package` | `pkgs.opencode` | OpenCode package, or `null`. |
| `programs.gentle-ai.opencode.context.enablePersona` | `true` | Include the public Gentle AI persona. |
| `programs.gentle-ai.opencode.context.fragments` | `[ ]` | Ordered user-owned `AGENTS.md` fragments. |
| `programs.gentle-ai.engram.enable` | `true` | Install and integrate Engram. |
| `programs.gentle-ai.engram.package` | pinned package | Engram package, or `null` to skip installation. Its `src` supplies the plugin by default. |
| `programs.gentle-ai.engram.source` | `null` | Explicit Engram plugin source override. |
| `programs.gentle-ai.engram.sourceVersion` | `null` | Required version for an explicit Engram source; must match a non-null package. |

Package options are nullable and overridable. Harness assets are derived from each selected package's `src`, so changing a package changes its assets as one unit. A package without `src` requires an explicit source and matching `sourceVersion`; source-only overrides also require a declared version. The module rejects silent binary/asset version drift.

Disabling Engram removes its package, MCP entry, plugin, and context fragment. Disabling OpenCode leaves Gentle AI and Engram packages available but creates no OpenCode configuration.

```nix
programs.gentle-ai = {
  package = myGentleAiPackage;
  source = myGentleAiSource;
  sourceVersion = myGentleAiPackage.version;
};
```

## Ordered Context

Each fragment requires a stable `id`, accepts `text` or `source`, and sorts by `order` then `id`. Duplicate IDs and fragments with both or neither content source fail module assertions.

```nix
programs.gentle-ai.opencode.context.fragments = [
  {
    id = "local-policy";
    order = 300;
    source = ./AGENTS.local.md;
  }
  {
    id = "project-guidance";
    order = 400;
    text = "Read project-level AGENTS.md files before editing.";
  }
];
```

Managed order starts with the persona at `100` and Engram at `200`. User fragments can be placed before, between, or after them. Home Manager owns one final `programs.opencode.context`; no activation script rewrites markers or existing files.

## Native Extensions

Continue using Home Manager's OpenCode module directly. User values override Gentle AI defaults where they overlap, and unrelated values merge normally.

```nix
programs.opencode = {
  settings = {
    model = "anthropic/claude-sonnet-4-6";
    share = "manual";
  };
  tui.theme = "system";
  commands.my-command = ./commands/my-command.md;
  skills.my-skill = ./skills/my-skill;
};
```

## Secrets

Never put API keys, tokens, passwords, or secret file contents in Nix strings or fragment sources. Nix evaluation copies those values into the world-readable Nix store. Configure provider credentials outside Nix through environment variables or secret-managed files, and use OpenCode references such as `{env:VARIABLE}` or `{file:path}` where supported.

The Engram MCP entry contains only a command name and arguments. It embeds no credentials.

## Migration

Migration from a custom projection setup must be atomic because Home Manager rejects two declarations for the same generated path.

1. Remove the old owners of `opencode.json`, `tui.json`, `AGENTS.md`, `commands/`, `agents/`, `skills/`, `plugins/`, and `prompts/sdd/` in the same Home Manager change that imports this module.
2. Move host-specific settings to native `programs.opencode.*` options.
3. Move private `AGENTS.md` policy into an ordered local fragment. Do not add that fragment to this public repository.
4. Apply Home Manager once and restart OpenCode.
5. Verify `opencode`, `gentle-ai version`, and `engram version`, then start a fresh OpenCode session to verify MCP and plugin loading.

Do not run `gentle-ai sync` against files owned by this module. Declarative Home Manager state is authoritative; imperative sync would attempt to mutate Nix-managed symlinks.

## Compatibility and Status

The initial release targets current Home Manager versions that provide `programs.opencode.settings`, `tui`, `context`, `commands`, `agents`, `skills`, and MCP-compatible settings. Linux and Darwin systems supported by the upstream Go projects are exposed.

Gentle AI `2.3.0` and Engram `1.20.0` are pinned from verified upstream tags. Their public assets are rendered during Nix evaluation using the selected source trees; unresolved upstream template tokens fail evaluation. OpenCode defaults to `pkgs.opencode`, so its version follows the consumer's nixpkgs input and remains overridable.

See [`examples/home.nix`](examples/home.nix) for a runnable module fragment.

## Development

```sh
nix fmt
nix flake check
```

The repository is licensed under MIT; see [`LICENSE`](LICENSE).
