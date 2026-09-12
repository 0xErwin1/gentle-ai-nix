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
| `providers.<name>` | A client, with `modelPreset`, `modelFamily`, `profiles`, `activeProfile`, `skills`, `settings`, `models`, `packages`, `mcpServers` and its package provisioning for it alone. |
| `components.<name>` | What Gentle AI configures — skills, persona, permissions, sdd, theme, engram, gga. |
| `skills.<name>` | Naming none installs every skill Gentle AI ships. Entries only narrow that: `false` drops one, `true` restricts to the ones named. |
| `communityTools.<name>` | The optional extras, plus the `package` Nix supplies for one and whether it wires itself in. |
| `openCodePlugins.<name>` | The optional OpenCode plugins, same shape as the skills. |
| `roles.<id>` | Logical agent roles. `references` name ids, so renaming one is a single edit. |
| `sdd`, `review`, `install`, `backgroundSubagents` | Workflow mode and strict TDD, the review kill switch, scope and channel, background policy. |
| `models` | Assignments the contract keeps outside a provider. |
| `permissions`, `mcpServers` | Rules layered over the shipped guardrails, and servers no component configures. |
| `persona`, `preset`, `schemaVersion`, `package` | The rest. |

Two different things are called a profile, and both live on the client. `providers.<name>.modelPreset` names a tier Gentle AI recommends — Codex, Claude and Kiro each offer their own, with their own vocabulary. `providers.<name>.profiles.<name>` is a model configuration *you* name, switchable at runtime; OpenCode and Pi both take it, but materialise it differently. OpenCode generates its own orchestrator and phase agents per profile, alongside the default set — `providers.opencode.profileStrategy` says whether Gentle AI generates them itself or leaves an external profile manager to keep one active. Pi has no agents of its own to generate: its profiles live in gentle-pi's global profile store, `~/.pi/gentle-ai/profiles.json`, and `providers.pi.activeProfile` is the declarative form of running `/gentle:profiles` inside Pi. Unlike every other provider's own fields, these five — `models`, `profiles`, `activeProfile`, `modelFamily`, `modelPreset` — never reach the Gentle AI document for Pi: gentle-nix writes `profiles.json` and `models.json` and merges the orchestrator defaults into Pi's own settings directly, because gentle-pi's routing and profile store are not a Gentle AI feature.

A profile and explicit assignments compose rather than exclude each other. For OpenCode, name the profile for the shape you want, then override the phases you care about with `providers.<name>.models`, and the rest stay on the profile. For Pi, routing follows one precedence order: an explicit `providers.pi.models` entry wins, then the active profile, then `modelPreset` and `modelFamily` fill in whatever agent neither of those named.

Model profiles live on the client, not on the installation: `providers.codex.modelPreset = "low-cost"` alongside `providers.claude-code.modelPreset = "performance"` is a thing you can want, because subscriptions differ per client. Naming the profile rather than restating the models it resolves to is what keeps it the profile Gentle AI recommends today rather than the one it recommended when you wrote the file. A client that offers no profiles is reported rather than accepted and ignored.

Engram is a component, not something to wire by hand: `components.engram.enable` is what configures the MCP server, the plugin and the protocol section in every client that takes them. Nix supplies the binary through `engramPackage` so nothing is downloaded at activation.

Engram is built per channel too, in
[`packages/engram-versions.nix`](packages/engram-versions.nix). `stable` is the
default and the only one a plain `engramPackage` resolves to. The 2.0 candidate
is available as `engram-rc`, and taking it is a decision written into the
configuration rather than a version bump that arrives with a flake update:

```nix
programs.gentle-ai.engramPackage = gentle-ai-nix.packages.${pkgs.system}.engram-rc;
```

Its own release notes ask that a stable installation stay available rather than
be replaced, and two of its named risk areas apply to any store with history:
legacy sessions with blank ownership, which `engram doctor` reports, and
Pi/OpenCode session attribution becoming fail-closed on the runtime identity.

A community tool takes the same shape one level down. `communityTools.codegraph.enable` writes the guidance, `communityTools.codegraph.package` is where its binary comes from, and the CLI call that points it at the declared clients runs at activation from the commands Gentle AI put in the manifest:

```nix
communityTools.codegraph.enable = true;
```

CodeGraph is packaged here, so `package` already points at it and the binary comes from Nix rather than the `npm install -g` Gentle AI would otherwise print. Set it yourself to pin a different one. For a tool this flake does not package the default is null, and then the tool is configured and the binary is your business. Without `provision` — it defaults on — the guidance is written and nothing is wired, which is a configuration describing a server that was never set up.

## Editing the harness

A wrapper you cannot edit is a worse harness than the one you wrote yourself. Three ways in, cheapest first.

| You want to | Use |
|-------------|-----|
| Add a skill, agent or command Gentle AI does not ship | `extraFiles."<path>".source` |
| Replace a file Gentle AI does ship | `extraFiles."<path>".text` — same path, your content wins |
| Keep a section of your own in a file Gentle AI regenerates | `extraFiles.<name> = { target; mode = "append"; text; }` |
| Layer a tree of your own beside a generated one, without shadowing it | `extraFiles.<name> = { target; mode = "fill"; source; }` |
| Register something inside a file Gentle AI also writes — a hook in a settings file | `extraFiles.<name> = { target; mode = "merge"; unionLists; source; }` |
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

## Beyond the contract

Two things live here rather than in Gentle AI, because they are how a Nix
installation works rather than what a Gentle AI installation is.

**A client Gentle AI has no adapter for** can still receive the harness another
client produced:

```nix
customProviders.agens = {
  root = ".config/agens";
  from = "claude-code";
  delivery = "copy";                      # for a client that refuses symlinks
  rewriteReferences = true;               # so the prose names this client's own tree
  assets = { "CLAUDE.md" = "AGENTS.md"; agents = "agents"; skills = "skills"; };
};
```

A borrowed harness names the directory it was rendered for, so an agent taken
from Claude Code still tells the model to read `~/.claude/skills/...` — back
into the tree this client refuses to read through, which is why the assets were
copied in the first place. `rewriteReferences` rewrites those references from
the `assets` mapping itself, at build time, so the copy points at its own files
and the mapping is not restated anywhere that could drift from it.

**A client whose harness is packages rather than files** — Pi installs its
through its own tool — cannot have that part rendered at all, because installing
it means running the client's installer against a network:

```nix
providers.pi = {
  enable = true;
  provisionPackages = true;
  provisionEnvironment.SOME_INSTALLER_FLAG = "1";
};
```

The commands come from the rendered manifest, so this module holds no copy of a
package list that could go stale. They run once per change to that list, and skip
with a message when the client's own binary is not on PATH. It is off by default:
it is the one part of this module that reaches a network, and what it installs is
not tracked by Nix.

Two of Pi's own packages are picked by channel rather than declared directly.
`gentlePiRelease = "stable" | "main"` chooses gentle-pi itself: `stable` is
npm's published release, the same thing Pi already installs on its own;
`main` pins a revision on gentle-pi's main branch and installs it from git
instead, refreshed the same way [`packages/versions.nix`](packages/versions.nix)
tracks Gentle AI's own beta channel — `git ls-remote` against the branch, then a
new pin. `engramRelease = "stable" | "rc"` drives both the Engram binary and,
when Pi is enabled, which build of Engram's Pi plugin Pi installs, so the wire
format and the plugin can never drift apart: on `rc` the plugin is built from
that same Engram revision and linked into the rendered tree at
`.pi/gentle-ai/plugins/gentle-engram`, installed by path because gentle-pi's
git installer cannot reach a subdirectory of a repository.

Everything else Pi installs is `providers.pi.packages`, keyed by name with a Pi
install source as the value — `npm:<name>[@version]`,
`git:<host>/<user>/<repo>[@ref]`, or an absolute local path:

```nix
providers.pi.packages.pi-btw = "npm:pi-btw";
```

`gentle-pi` and `gentle-engram` are refused here at eval; the two channel
options above own them. Naming one of Pi's other fixed packages
(`pi-mcp-adapter`, `@juicesharp/rpiv-ask-user-question`, `pi-web-access`,
`pi-btw`) overrides its install source in place rather than adding a second
entry.

A switch that changes a channel or a declared package's source retires the
entry it displaces — the previous `gentle-pi` build, the previous plugin path,
the previous source for a name that stayed the same — but only once the
replacement is confirmed installed, so a registry or git host unreachable
during provisioning costs a missed retirement rather than the previous,
working install. Removing a package from `packages` entirely does not retire
it on its own: the module has no record of what an earlier generation
declared, only what this one does, so that still needs a manual `pi remove`.

**A file that has to carry a credential** cannot be a store symlink — the store
is world-readable and read-only. Those paths are held back from the projection
and written at activation with the placeholder replaced:

```nix
mcpServers.atlas.env.ATLAS_TOKEN = "@ATLAS_TOKEN@";

secrets = {
  paths = [ ".config/opencode/opencode.json" ];
  placeholders.ATLAS_TOKEN = config.sops.secrets."ai/atlas-token".path;
};
```

Where that path comes from is not this flake's business: a sops-nix or agenix
secret exposes exactly such a file, and so does a plain one, so none of them is
a dependency here.

**A file the client also writes** — Claude Code keeps its OAuth session and
project history in `.claude.json`, Codex its per-project trust levels in
`config.toml` — cannot be replaced either. Those are merged instead:

```nix
secrets.merge = [ ".claude.json" ".codex/config.toml" ];
```

The fragment goes in and everything it does not mention stays, comments and all.
Merging is additive: an entry dropped from the document is not removed from the
file, because the entry may be one the client wrote and the file is not ours to
prune.

An array is replaced, because one the harness owns has to be able to lose an
entry: a rule taken out of the declaration has to disappear from the file. Where
the client is the one appending — a list of installed packages it maintains —
replacing is what destroys state, so those are named:

```nix
secrets.merge = [
  ".claude.json"
  { path = ".pi/agent/settings.json"; unionLists = [ "packages" ]; }
];
```

| | `secrets.paths` | `secrets.merge` |
|---|---|---|
| Ownership | Gentle AI owns the file whole | shared with the client |
| Written | replaced | merged in |
| Formats | any | JSON and TOML |

## Reference

Every option, with its type, default and example, is in [`docs/options.md`](docs/options.md). It is generated from the module itself and a check fails the build if the committed copy drifts, so it cannot describe an option the module does not have.

```console
nix build .#options-doc && cp result docs/options.md
```

For the fields these options produce — what each accepts, and what omitting it means — see the [contract reference](https://github.com/Gentleman-Programming/gentle-ai/blob/main/docs/declarative-config-reference.md) in Gentle AI itself.

## How it works

```
programs.gentle-ai.settings ─────────────────┐
programs.gentle-ai.providers.<name>.settings ┘─► gentle-ai.json ─► gentle-ai config render ─► store tree ┐
                                                                                                          ├─► home.file
programs.gentle-ai.roles ────────────────────────────────────────────────► gentle-nix roles ─────────────┘
```

Renaming or defining roles is not something Gentle AI does imperatively, so
`roles` never reaches `gentle-ai.json`: `gentle-nix roles` renders them as
post-processing of the store tree `gentle-ai config render` already
produced, for the five clients that can express a role at all.

| Decision | Why |
|----------|-----|
| Rendering happens in a derivation | The result is a store path: reproducible, cacheable, and inspectable through `programs.gentle-ai.rendered` before it is linked. |
| The document carries your home directory | Rendered content records absolute paths to its own files, so it is built for the directory it will live in rather than for the build sandbox. |
| The tree is linked recursively | Every file is its own symlink, so unrelated files in the same directories are left alone and a genuine collision is reported instead of one module shadowing another's directory. |
| Nothing is rewritten at activation | Activation only links what was already rendered and verified at build time. |

## Releases

Gentle AI is built per channel, selected declaratively:

```nix
programs.gentle-ai.release = "beta";   # stable | beta | contract
```

| Channel | What it builds |
|---------|----------------|
| `stable` | the newest release |
| `beta` | the tip of Gentle AI's main branch, the same thing `gentle-ai upgrade --channel beta` installs |
| `contract` | main, with the declarative configuration contract on top |

The versions each one resolves to live in
[`packages/versions.nix`](packages/versions.nix), alongside whether that release
has `gentle-ai config` at all.

`contract` is the default, and only because the declarative configuration
contract this flake renders through is not in a release yet. Choosing a
channel without it is rejected while the configuration is evaluated, naming
the reason, rather than failing later inside the renderer. Setting
`programs.gentle-ai.package` overrides the channel entirely.

The channels are also packages: `nix build .#gentle-ai-stable`,
`nix build .#gentle-ai-beta`.

Adding a release is one entry in [`packages/versions.nix`](packages/versions.nix).

## Requirements

This flake calls `gentle-ai config render`, the declarative configuration contract from [Gentle AI issue #3248](https://github.com/Gentleman-Programming/gentle-ai/issues/3248). It is not in an upstream release yet, which is what the `contract` channel above exists for. Once it merges, drop that entry from `packages/versions.nix` and set `providesContract = true` on the release that carries it; nothing else changes.

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
