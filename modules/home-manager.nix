# Home Manager integration for Gentle AI.
#
# The options here are grouped the way an operator thinks about the
# installation — by provider, by component, by skill, by role — and are
# translated into one Gentle AI desired-state document. Gentle AI decides what
# that document means on disk.
#
# What this module deliberately does not hold is any knowledge of what a skill
# or an agent *is*: no asset paths, no phase names, no rendering rules. Group
# names are free-form, so a provider, component or skill Gentle AI gains works
# here the day it ships, and one it does not have is rejected by Gentle AI with
# a diagnostic rather than accepted and ignored.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    literalExpression
    literalMD
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    types
    ;

  cfg = config.programs.gentle-ai;

  releases = import ../packages/versions.nix;

  selectedRelease = releases.${cfg.release};

  defaultGentleAiPackage = pkgs.callPackage ../packages/gentle-ai.nix {
    release = selectedRelease;
  };

  engramReleases = import ../packages/engram-versions.nix;

  selectedEngramRelease = engramReleases.${cfg.engramRelease};

  defaultEngramPackage = pkgs.callPackage ../packages/engram.nix {
    release = selectedEngramRelease;
  };

  # Engram's Pi plugin, built only when it is actually wanted: Nix's laziness
  # means this derivation is never evaluated, let alone built, unless
  # `engramRelease` is off stable and Pi is enabled, the one case
  # `pluginPackagesFor` below reads it in.
  gentleEngramPiPackage = pkgs.callPackage ../packages/gentle-engram-pi.nix {
    release = selectedEngramRelease;
  };

  # Where the plugin lands inside the rendered tree, and so inside the home
  # directory once that tree is linked in. A store path is not usable here:
  # Pi records a local source by its path, so installing the store path
  # directly would change identity on every rebuild and leave Pi holding two
  # entries for what is meant to be the same plugin. Landing it at a fixed
  # path under Pi's own Gentle AI directory instead is what keeps the
  # identity Pi records stable across rebuilds, the store path underneath it
  # notwithstanding.
  gentleEngramPiPluginPath = ".pi/gentle-ai/plugins/gentle-engram";
  gentleEngramPiHomePath = "${config.home.homeDirectory}/${gentleEngramPiPluginPath}";

  piEnabled = enabledProviders ? pi;

  # Only Pi reads `packages`; a non-pi provider setting it is named here so
  # the assertion below can point at exactly the providers at fault.
  nonPiProvidersWithPackages = lib.attrNames (
    lib.filterAttrs (name: provider: name != "pi" && provider.packages != { }) enabledProviders
  );

  # Mirrors gentle-nix provision's own ValidSource
  # (internal/provision/source.go): a Pi install source is only an
  # `npm:`, `git:`, `https://`, or `ssh://` reference with a non-empty
  # payload, or an absolute local path with at least one non-empty
  # component after the leading "/". A value padded with leading or
  # trailing whitespace is never valid either. A providers.pi.packages
  # entry missing its scheme (a bare package name copied from npm without
  # its `npm:` prefix, say) would otherwise reach `pi install` unchanged
  # and only fail once Pi tries to run it at activation.
  piPackageSourceIsValid =
    source:
    let
      hasNonEmptyPayload = prefix: lib.hasPrefix prefix source && source != prefix;
    in
    lib.trim source == source
    && source != ""
    && (
      hasNonEmptyPayload "npm:"
      || hasNonEmptyPayload "git:"
      || hasNonEmptyPayload "https://"
      || hasNonEmptyPayload "ssh://"
      || (lib.hasPrefix "/" source && lib.any (part: part != "") (lib.splitString "/" source))
    );

  piPackagesWithInvalidSources = lib.attrNames (
    lib.filterAttrs (_: source: !(piPackageSourceIsValid source)) (cfg.providers.pi.packages or { })
  );

  # The plugin is only worth linking into the tree for the one case it is
  # ever installed from: Pi enabled, and `engramRelease` off the npm default.
  embedGentleEngramPiPlugin = piEnabled && cfg.engramRelease != "stable";

  gentlePiReleases = import ../packages/pi-versions.nix;

  selectedGentlePiRelease = gentlePiReleases.${cfg.gentlePiRelease};

  # gentle-pi is not a derivation this flake builds: Pi installs it itself
  # from whatever source string this resolves to. `stable` already names one
  # directly; every other channel is a revision Pi's own git installer
  # fetches, so the source is composed from it here instead of being
  # restated per channel in pi-versions.nix.
  gentlePiSource =
    release: release.source or "git:github.com/Gentleman-Programming/gentle-pi@${release.rev}";

  # Pi-only install source overrides, keyed the way the contract's
  # `providers.pi.packages` wants them: by the npm package name the adapter
  # installs. Present only for a channel actually chosen off its default, so
  # a default configuration emits nothing here and the document this flake
  # has always rendered for Pi does not change shape.
  pluginPackagesFor =
    optionalAttrs (cfg.gentlePiRelease != "stable") {
      gentle-pi = gentlePiSource selectedGentlePiRelease;
    }
    // optionalAttrs (cfg.engramRelease != "stable") {
      gentle-engram = gentleEngramPiHomePath;
    };

  # The npm package names `gentle-nix provision`'s Pi adapter always installs
  # -- a name naming one of these overrides that package's install source in
  # place; any other name is an additional package appended after the fixed
  # sequence. Mirrored from fixedPiPackageNames in the pinned fork's Pi
  # adapter (internal/agents/pi/adapter.go), because the split between
  # `--override` and `--extra` gentle-nix provision needs has to agree with
  # exactly the same set the fork itself used to read out of the document.
  fixedPiPackageNames = [
    "gentle-pi"
    "gentle-engram"
    "pi-mcp-adapter"
    "@juicesharp/rpiv-ask-user-question"
    "pi-web-access"
    "pi-btw"
  ];

  # Channel-managed sources and `providers.pi.packages` combined the same
  # way `providerBlock` used to combine them for the document's `packages`
  # field -- now split instead into what `gentle-nix provision` rewrites in
  # place (`--override`) and what it appends after the fixed sequence
  # (`--extra`), since neither travels through the document any more.
  piCombinedPackages = (cfg.providers.pi.packages or { }) // pluginPackagesFor;

  piProvisionOverrides = lib.filterAttrs (
    name: _: lib.elem name fixedPiPackageNames
  ) piCombinedPackages;

  # lib.attrNames/mapAttrsToList always iterate in sorted-key order, so this
  # already lists extras by package name the same way the fork's
  # sortedExtraPiPackageNames did -- gentle-nix provision only sees the
  # sources, never the names, but the order it receives them in is already
  # exactly that sort.
  piProvisionExtra = lib.mapAttrsToList (_: source: source) (
    lib.filterAttrs (name: _: !(lib.elem name fixedPiPackageNames)) piCombinedPackages
  );

  # The community tools this flake packages, keyed by Gentle AI's own tool id.
  # Like providerRoots this is contract knowledge rather than asset knowledge:
  # the option is generic over the tool name, so a name-keyed table is the only
  # way a packaged tool can carry its own default without the module enumerating
  # the tools Gentle AI knows. A tool absent from here still defaults to null and
  # is configured with whatever binary the operator supplies.
  communityToolPackages = {
    "codegraph" = pkgs.callPackage ../packages/codegraph.nix { };
  };

  enabledNames = group: lib.attrNames (lib.filterAttrs (_: value: value.enable) group);
  disabledNames = group: lib.attrNames (lib.filterAttrs (_: value: !value.enable) group);

  # Only a value the operator actually set reaches the document. The contract
  # reads an omitted field as unresolved and a present one as a decision, so
  # emitting a default would turn silence into an explicit choice.
  whenSet =
    name: value: optionalAttrs (value != null && value != [ ] && value != { }) { ${name} = value; };

  modelAssignmentType = types.submodule {
    options = {
      provider = mkOption {
        type = types.str;
        description = "Model provider id.";
      };
      model = mkOption {
        type = types.str;
        description = "Model id within the provider.";
      };
      effort = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Reasoning effort, where the provider expresses one.";
      };
    };
  };

  toModelAssignment =
    assignment: { inherit (assignment) provider model; } // whenSet "effort" assignment.effort;

  profileType = types.submodule {
    options = {
      orchestrator = mkOption {
        type = types.nullOr modelAssignmentType;
        default = null;
        description = "Model this profile's orchestrator runs on.";
      };
      phases = mkOption {
        type = types.attrsOf modelAssignmentType;
        default = { };
        example = literalExpression ''
          {
            sdd-apply = {
              provider = "anthropic";
              model = "claude-sonnet-5";
            };
          }
        '';
        description = "Model per SDD phase within this profile.";
      };
    };
  };

  providerType = types.submodule (
    { name, ... }:
    {
      options = {
        enable = mkEnableOption "the ${name} client";

        skills = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          description = ''
            Skills for this provider only. Null takes the globally enabled
            skills, so a provider is named here only when it must differ.

            Resolved by `gentle-nix skills` as post-processing of the tree,
            not by Gentle AI itself: the document's own `skills` field is one
            flat list shared by every client, so a per-client override has no
            shape to travel through it. This client's skills directory is
            pruned down to exactly this list once activation renders -- a
            full replacement of the globally enabled skills for this client
            only, not a further narrowing of them, so the top-level `skills`
            option's own disabled entries are not applied on top of it.
          '';
        };

        settings = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          example = literalExpression ''{ share = "disabled"; }'';
          description = ''
            Provider-specific configuration the neutral contract does not model.
            It is recursively merged into this provider's settings and no other's.
          '';
        };

        modelPreset = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "economy";
          description = ''
            One of Gentle AI's own model profiles for this client, by name.
            Profiles are per client because subscriptions are: the cheap tier on
            one and the expensive tier on another is a thing you can want, and a
            single global profile cannot say it.

            Naming the profile rather than restating the models it resolves to
            is what keeps it the profile Gentle AI recommends today. An
            assignment set explicitly in `models` still wins over it.

            Not every client offers profiles; one that does not is reported
            rather than accepted and ignored.
          '';
        };

        profiles = mkOption {
          type = types.attrsOf profileType;
          default = { };
          example = literalExpression ''
            {
              cheap.orchestrator = {
                provider = "anthropic";
                model = "claude-haiku";
              };
            }
          '';
          description = ''
            Named SDD profiles for this client, switchable at runtime.

            OpenCode generates its own orchestrator and phase agents per
            profile, alongside the default set, so a task can run on cheap
            models without reconfiguring anything. Pi has no agents of its
            own to generate: it keeps these in gentle-pi's global profile
            store, `~/.pi/gentle-ai/profiles.json`, and its own `apply`
            switches between them; see `activeProfile` for declaring which
            one is active. A profile's name follows gentle-pi's own rule —
            letters or digits, then letters, digits, `.`, `_` or `-`, at most
            64 characters — because that is the name gentle-pi has to accept
            it under, on Pi.
          '';
        };

        profileStrategy = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "generated-multi";
          description = ''
            How profiles are materialised for this client: generated alongside
            the default agents, or left to an external profile manager that
            keeps one active at a time. Omitted, Gentle AI detects it.

            This is OpenCode's own concept: Pi's profiles live in gentle-pi's
            profile store instead, and are switched with `activeProfile`
            rather than a materialisation strategy.
          '';
        };

        activeProfile = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "cheap";
          description = ''
            Names one of this provider's `profiles` to activate.

            For Pi, the renderer writes it into gentle-pi's global profile
            store alongside the profiles themselves and materialises that
            profile's routing and orchestrator defaults, the same thing
            running `/gentle:profiles` inside Pi would do. Declaring it here
            is the declarative form of that command: the profile named wins
            over whatever gentle-pi last had active, on the next switch.

            Only Pi reads this; a profile is otherwise activated by the
            client's own runtime.
          '';
        };

        mcpServers = mkOption {
          type = types.attrsOf mcpServerType;
          default = { };
          description = ''
            MCP servers for this client only, replacing the flat set. A client
            that identifies itself to a server, or one an installation gives
            tools the others have no use for, is named here; the rest take the
            flat set.

            Rendered by `gentle-nix mcp` the same way the top-level
            `programs.gentle-ai.mcpServers` is; see that option for which
            clients can express one.
          '';
        };

        packages = mkOption {
          type = types.attrsOf types.str;
          default = { };
          example = literalExpression ''{ pi-btw = "npm:pi-btw"; }'';
          description = ''
            Pi packages this installation adds, keyed by package name with a Pi
            install source as the value: `npm:<name>[@version]`,
            `git:<host>/<user>/<repo>[@ref]`, an `https://` or `ssh://` URL, or
            an absolute local path -- any other shape, such as a bare package
            name missing its `npm:` prefix, is refused at eval. A Pi extension
            is itself an npm (or git) package, installed the same way as
            gentle-pi's own harness, so this is where one is declared.

            `gentle-pi` and `gentle-engram` are managed by `gentlePiRelease`
            and `engramRelease` instead, and are refused here at eval; use
            those options to choose where those two come from. A key naming
            one of Pi's own other fixed packages (`pi-mcp-adapter`,
            `@juicesharp/rpiv-ask-user-question`, `pi-web-access`, `pi-btw`)
            overrides that package's install source in place rather than
            adding a second entry alongside it.

            Removing a package from this set retires its installed entry on
            the next switch, the same way changing its source while the name
            stays the same does -- both are recorded against what the
            previous switch declared, the same way a channel change retires
            `gentle-pi` or `gentle-engram`. The very first switch after this
            behavior was added has no earlier declaration to compare
            against, so a package already removed before that switch still
            needs one manual `pi remove`; every removal after it is
            automatic. A dropped key naming one of Pi's own other fixed
            packages goes back to that package's harness default instead of
            being removed, since the key only ever overrode its source.

            Only Pi reads this; a provider other than pi is refused for
            setting it.
          '';
        };

        models = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          example = literalExpression ''{ sdd-apply = "opus"; }'';
          description = ''
            Model assignments in this provider's own vocabulary, keyed by the
            phase or agent it routes. Providers express models differently — an
            alias, a reasoning effort, a provider/model pair — so values are
            passed through as written.

            Where the client also offers a `modelPreset`, what is named here
            wins over what the profile would have given that key.
          '';
        };

        modelFamily = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "codex";
          description = ''
            The client whose model profile this one borrows, by Gentle AI's own
            id.

            A client with no catalogue of its own — Pi runs on whatever provider
            it was pointed at — has a profile that can only assign reasoning
            effort. Naming the provider it actually runs on takes that
            provider's model table too, the one Gentle AI tunes, instead of
            restating it here.

            The agents that table does not name keep the profile's levels, and
            `models` still wins over both.
          '';
        };

        provisionPackages = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Run the package installation this client's harness needs, using the
            client's own tool, during activation.

            Some clients keep their harness in packages rather than in files —
            Pi is the one that does today. Rendering produces the configuration
            around such a harness but cannot produce the harness itself, because
            installing it means running that client's installer against a
            network. Enabling this runs exactly the commands Gentle AI declares
            for the client, once per change to that command list, and skips with
            a message when the client's own binary is not on PATH.

            It is off by default: it is the one part of this module that
            reaches the network, and what it installs is not tracked by Nix.
          '';
        };

        provisionRefresh = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Run this client's provisioning commands on every activation instead
            of once per change to the command list.

            The commands a client declares name packages without naming
            versions, so their text never changes while what they resolve to
            does. Stamping them by their own text therefore means they run once
            and the packages stay at whatever the first activation installed,
            with no signal that a newer one exists.

            Enabling this trades a network call on every switch for packages
            that follow their channel. It is off by default because the cost is
            paid by every activation, including the ones that changed nothing.
          '';
        };

        provisionEnvironment = mkOption {
          type = types.attrsOf types.str;
          default = { };
          example = literalExpression ''{ GENTLE_PI_SKIP_GENTLE_AI_INSTALL = "1"; }'';
          description = ''
            Environment given to this client's provisioning commands.

            A package installer is free to expect things a Nix machine does not
            have — an FHS path, a system extractor, a writable prefix — and it
            usually offers a variable to say so. Setting it here keeps that
            answer with the declaration instead of in a shell profile that the
            activation does not read anyway.
          '';
        };

        secrets = {
          paths = mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = literalExpression ''[ "mcp/atlas.json" ]'';
            description = ''
              Like `programs.gentle-ai.secrets.paths`, but every entry is
              relative to ${name}'s own root instead of the home directory, so
              declaring one takes no knowledge of where Gentle AI rooted this
              client. Resolved against that root and folded into the same
              withheld set the global option populates -- both forms are
              interchangeable, and an entry declared here reaches exactly the
              same file a home-relative path in the global option would have
              named.

              A leading `../` reaches outside the root for the rare file a
              client keeps beside it rather than inside it. The result is
              still normalised to a home-relative path, and an entry that
              would resolve outside the home directory entirely is refused at
              eval rather than silently clipped.
            '';
          };

          merge = mkOption {
            type = types.listOf (types.either types.str mergeTargetType);
            default = [ ];
            example = literalExpression ''
              [
                {
                  path = "agent/settings.json";
                  unionLists = [ "packages" ];
                }
              ]
            '';
            description = ''
              Like `programs.gentle-ai.secrets.merge`, but every path is
              relative to ${name}'s own root; see `paths` above for the
              `../` escape hatch and how a per-provider path is resolved to
              the home-relative spelling the merge step actually uses. This is
              the preferred spelling over the global option's home-relative
              paths: declaring a merge target here takes no knowledge of
              where Gentle AI rooted ${name}, only what the client itself
              calls the file. Global and per-provider entries are folded into
              the same merge set, so the two forms are interchangeable.
            '';
          };
        };
      };
    }
  );

  roleType = types.submodule {
    options = {
      renderedName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Name this role is rendered as. Null renders it under its id. Other
          roles always reference the id, so changing this is one edit.
        '';
      };

      references = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Ids of the roles this one delegates to.";
      };

      description = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "One-line description shown by the client.";
      };

      prompt = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "System prompt for this role.";
      };

      tools = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Tools this role may use. Null leaves the client's default.";
      };

      model = mkOption {
        type = types.nullOr modelAssignmentType;
        default = null;
        description = "Model this role runs on.";
      };

      mode = mkOption {
        type = types.nullOr (
          types.enum [
            "primary"
            "subagent"
          ]
        );
        default = null;
        description = ''
          Whether the operator addresses this role directly or another role
          delegates to it.
        '';
      };

      hidden = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Whether the client hides this role from its agent list.";
      };
    };
  };

  mcpServerType = types.submodule {
    options = {
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Executable for a local server.";
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Arguments for the command.";
      };
      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment for the command.";
      };
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Endpoint for a remote server. Mutually exclusive with command.";
      };
      headers = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = literalExpression ''{ Authorization = "Bearer @TOKEN@"; }'';
        description = ''
          Credentials a remote server takes in an HTTP header. Without them a
          hosted endpoint can be named but not reached.
        '';
      };
      enable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Whether the client should start this server.";
      };
    };
  };

  customProviderType = types.submodule (
    { name, ... }:
    {
      options = {
        root = mkOption {
          type = types.str;
          example = ".config/agens";
          description = "Directory this client reads, relative to the home directory.";
        };

        from = mkOption {
          type = types.str;
          example = "claude-code";
          description = ''
            The declared client whose rendered harness this one receives. Gentle
            AI has no adapter for ${name}, so rather than mapping every asset by
            hand it is given what a client Gentle AI does know already produced.
          '';
        };

        assets = mkOption {
          type = types.attrsOf types.str;
          default = { };
          example = literalExpression ''
            {
              "CLAUDE.md" = "AGENTS.md";
              agents = "agents";
              skills = "skills";
            }
          '';
          description = ''
            What to take, mapped from a path inside the source client's
            directory to a path inside this one. Left empty, the source
            directory is taken whole.
          '';
        };

        delivery = mkOption {
          type = types.enum [
            "symlink"
            "copy"
          ];
          default = "symlink";
          description = ''
            How the assets arrive. Copy exists for clients that refuse to read
            through a symbolic link; it is authoritative, so each target is
            replaced on every activation and edits under it do not survive.
          '';
        };

        frontmatterDefaults = mkOption {
          type = types.attrsOf (types.attrsOf types.str);
          default = { };
          example = literalExpression ''
            {
              agents = {
                mode = "subagent";
              };
            }
          '';
          description = ''
            Frontmatter keys filled into the markdown files of the named asset
            when a file does not already state them, keyed by the asset's source
            path as declared in `assets`.

            A borrowed harness speaks the source client's dialect, and this
            client may require a field the source never writes: agens refuses an
            agent definition without `mode:`, while Claude Code has no such
            field. That requirement belongs to this projection rather than to
            the source files, so it is declared here and inserted at build time.

            Only a missing key is filled — a file that states the key keeps its
            own value — and a file without a frontmatter block is left alone.
          '';
        };

        rewriteReferences = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Point the assets' own cross-references at this client's directory
            instead of the source client's.

            A harness names the directory it was rendered for: an agent taken
            from Claude Code tells the model to read
            `~/.claude/skills/_shared/...`, which sends this client back into
            the source tree even though the same file arrived beside it. Where
            the assets were copied precisely because the client refuses to read
            through a symbolic link, that reference resolves to a path it cannot
            open at all.

            The replacements come from `assets`, so the mapping is the one
            declared above rather than a second copy of it that drifts: a path
            named there is rewritten to what it was renamed to, and the source
            directory covers everything it does not name. Rewriting happens at
            build time, so what activation delivers is the store copy, and only
            text is touched — anything that is not valid UTF-8 arrives byte for
            byte.
          '';
        };
      };
    }
  );

  mergeTargetType = types.submodule (
    { name, ... }:
    {
      options = {
        path = mkOption {
          type = types.str;
          default = name;
          description = "Path relative to the home directory.";
        };

        unionLists = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = literalExpression ''[ "packages" ]'';
          description = ''
            Dotted paths to arrays in this file that the client appends to
            itself, merged by union instead of being replaced.

            An array is replaced by default, because one the harness owns has to
            be able to lose an entry: a rule removed from the declaration has to
            disappear from the file. Where the client is the one appending — a
            list of installed packages it maintains — replacing is what destroys
            state, and the rendered entries mean "these must be present" rather
            than "these are all there is".
          '';
        };
      };
    }
  );

  # A merge target is a path or a path with a policy, so the rest of the module
  # reads one shape.
  mergeTargets = map (
    entry:
    if builtins.isString entry then
      {
        path = entry;
        unionLists = [ ];
      }
    else
      entry
  ) cfg.secrets.merge;

  extraFileType = types.submodule (
    { name, ... }:
    {
      options = {
        text = mkOption {
          type = types.nullOr types.lines;
          default = null;
          description = "Inline content. Set exactly one of text or source.";
        };
        source = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File or directory to copy. Set exactly one of source or text.";
        };
        target = mkOption {
          type = types.str;
          default = name;
          description = "Path relative to the home directory.";
        };
        unionLists = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = literalExpression ''[ "hooks.SessionStart" ]'';
          description = ''
            With `mode = "merge"`, the dotted paths to arrays that accumulate
            instead of being replaced. Everything else follows the same rule as
            `secrets.merge`: an array is replaced unless it is named here.
          '';
        };
        mode = mkOption {
          type = types.enum [
            "replace"
            "append"
            "fill"
            "merge"
          ];
          default = "replace";
          description = ''
            How this content meets what Gentle AI rendered at the same path.

            `replace` overwrites it. `append` adds after it, which is how a
            section of your own survives in a file Gentle AI regenerates.

            `fill` copies only what is not there already, so a directory of your
            own can be layered over a directory Gentle AI renders without your
            copy of a file it also ships winning. That is what lets you keep a
            tree of extra agents or skills beside the generated ones without
            listing them, and without a stale copy shadowing the current one.

            `merge` merges structured content into what Gentle AI rendered, so
            a tool that has to register itself inside a file Gentle AI also
            writes — a hook in a settings file — arrives without either one
            overwriting the other. JSON and TOML only. See `unionLists` for the
            arrays that accumulate rather than being replaced.
          '';
        };
      };
    }
  );

  enabledProviders = lib.filterAttrs (_: provider: provider.enable) cfg.providers;

  providerSettings = lib.filterAttrs (_: value: value != { }) (
    lib.mapAttrs (_: provider: provider.settings) enabledProviders
  );

  # providers.<name>.settings no longer travels through the document as
  # `extensions` for the fork to merge (internal/cli/config_stager.go's
  # stageDeclaredExtensions/mergeExtensionBlock, in the pinned Gentle AI
  # fork); gentle-nix does the merge itself, in the overlay derivation
  # below, at exactly the same per-client files those adapters used.
  #
  # Codex and Kimi keep their own settings in TOML rather than JSON, so
  # their block is routed through the existing Python gentle-ai-merge
  # (lib/merge.py) instead of gentle-nix settings (JSON-only, deliberately:
  # see internal/settings' package doc) -- the same tool `extraFiles`'
  # `merge` mode already uses for a TOML target. `pkgs.formats.toml`
  # renders the declared attrset into fragment TOML text for it, so this
  # module never has to implement a TOML writer of its own.
  tomlSettingsProviders = [
    "codex"
    "kimi"
  ];

  jsonProviderSettings = lib.filterAttrs (
    name: _: !(lib.elem name tomlSettingsProviders)
  ) providerSettings;
  tomlProviderSettings = lib.filterAttrs (
    name: _: lib.elem name tomlSettingsProviders
  ) providerSettings;

  # Mirrors the pinned fork's own Codex/Kimi adapters (MCPConfigPath /
  # SettingsPath in internal/agents/codex and internal/agents/kimi),
  # relative to the tree root, the same way internal/settings' own
  # settingsPaths mirrors every JSON one.
  tomlSettingsPaths = {
    codex = ".codex/config.toml";
    kimi = ".kimi/config.toml";
  };

  tomlSettingsFormat = pkgs.formats.toml { };

  # A profile's own shape, nested under providers.<id>.profiles.<name>. The
  # name lives in the enclosing attribute set's key, the same way the
  # contract keys it, so it is not restated inside the value.
  profile =
    value:
    optionalAttrs (value.orchestrator != null) {
      orchestrator = toModelAssignment value.orchestrator;
    }
    // whenSet "phaseAssignments" (lib.mapAttrs (_: toModelAssignment) value.phases);

  # OpenCode is the one client whose `models` carries full provider-qualified
  # assignments rather than a vocabulary it decodes itself; every other client
  # takes what was declared verbatim, because the contract decodes each
  # provider's models in that provider's own shape.
  providerModels =
    name: models: if name == "opencode" then lib.mapAttrs (_: toModelAssignment) models else models;

  # One block per enabled provider, nested the way the contract nests it:
  # a provider's own vocabulary, its profiles, and its overrides all live
  # under its own key instead of a flat field per provider suffixed with that
  # provider's name. What a provider does and does not accept here — whether
  # it has a model catalogue, whether it expresses profiles, whether
  # `activeProfile` means anything to it — is no longer this module's
  # knowledge to duplicate: the renderer decodes each block in that
  # provider's own shape and reports a mismatch as a diagnostic, the same way
  # an unknown provider or skill already is.
  #
  # Pi is the one exception: `models`, `profiles`, `activeProfile`,
  # `modelFamily` and `modelPreset` are gentle-pi's own routing and profile
  # store, not a Gentle AI feature, so they no longer reach the document for
  # pi at all -- `gentle-nix pi routing` writes them straight into the
  # rendered tree instead (see piRoutingSpecBody and the `overlaid`
  # derivation below). Every other provider keeps sending them through the
  # document unchanged.
  providerBlock =
    name: provider:
    optionalAttrs (name != "pi") (
      whenSet "models" (providerModels name provider.models)
      // whenSet "modelFamily" provider.modelFamily
      // whenSet "modelPreset" provider.modelPreset
      // whenSet "profiles" (lib.mapAttrs (_: profile) provider.profiles)
      // whenSet "activeProfile" provider.activeProfile
    )
    // whenSet "backgroundIntent" (cfg.backgroundSubagents.${name} or null)
    // whenSet "profileStrategy" provider.profileStrategy;
  # `skills` no longer travels through the document for any provider either:
  # the document's own "skills" field can only ever be one flat list, so a
  # per-client override has no shape to travel through it at all --
  # `gentle-nix skills` resolves it as post-processing instead, the same way
  # roles, MCP servers and Pi routing already are -- see skillsSpecBody and
  # the `gentle-nix skills` invocation in `overlaid` below.
  #
  # `mcpServers` no longer travels through the document for any provider:
  # wiring a user-declared MCP server is not something Gentle AI does
  # imperatively, so `gentle-nix mcp` writes it straight into the rendered
  # tree instead -- see mcpSpecBody and the `gentle-nix mcp` invocation in
  # `overlaid` below.

  # gentle-nix pi routing's own input, built from the raw
  # providers.pi.{models,profiles,activeProfile,modelFamily,modelPreset}
  # options rather than from `providers` above, since providerBlock no
  # longer carries them for pi. Empty when pi is not enabled or none of
  # these were declared, in which case nothing invokes the subcommand at
  # all -- see piRoutingNeeded.
  piRoutingSpecBody =
    if !piEnabled then
      { }
    else
      let
        piProvider = cfg.providers.pi;
      in
      whenSet "models" (providerModels "pi" piProvider.models)
      // whenSet "profiles" (lib.mapAttrs (_: profile) piProvider.profiles)
      // whenSet "activeProfile" piProvider.activeProfile
      // whenSet "modelFamily" piProvider.modelFamily
      // whenSet "modelPreset" piProvider.modelPreset
      // optionalAttrs (piProvider.modelFamily != null && piProvider.modelPreset != null) {
        # A relative path: `gentle-nix pi routing` reads it from its own
        # working directory, which is this derivation's build directory --
        # see the `overlaid` derivation, which writes the presets document
        # at exactly this name before invoking the subcommand.
        presets = piPresetsRelPath;
      };

  piPresetsRelPath = "gentle-ai-pi-presets.json";

  piRoutingNeeded = piRoutingSpecBody != { };

  piRoutingSpecFile = pkgs.writeText "gentle-ai-pi-routing-spec.json" (
    builtins.toJSON piRoutingSpecBody
  );

  # A provider enabled with nothing else set has nothing worth nesting: an
  # empty block would still be a key the renderer has to look at and find
  # nothing in, so it is left out of the document instead.
  providers = lib.filterAttrs (_: block: block != { }) (lib.mapAttrs providerBlock enabledProviders);

  # Renaming or defining roles is not something Gentle AI does imperatively,
  # so a role is no longer part of the document at all: `roleSpecEntry`
  # feeds `gentle-nix roles` instead (see rolesSpecBody, rolesNeeded and the
  # `gentle-nix roles` invocation in `overlaid` below), which renders it as
  # post-processing of the tree `gentle-ai config render` already produced.
  # The id travels as the map key there, not as a field, so this keeps
  # exactly the fields a role's own file or settings entry carries.
  roleSpecEntry =
    value:
    whenSet "renderedName" value.renderedName
    // whenSet "references" value.references
    // whenSet "description" value.description
    // whenSet "prompt" value.prompt
    // whenSet "tools" value.tools
    // whenSet "mode" value.mode
    // optionalAttrs (value.model != null) { model = toModelAssignment value.model; }
    // optionalAttrs (value.hidden != null) { inherit (value) hidden; };

  # The five adapters `internal/roles` (gentle-nix's own role renderer)
  # knows how to write a role for: the four that keep every role as its own
  # frontmatter file, plus opencode, whose roles live inside its own
  # settings file. Every other adapter has no notion of a role at all,
  # mirrored from the pinned fork's own render.ProviderFor.
  roleCapableProviders = [
    "claude-code"
    "cursor"
    "kimi"
    "kiro-ide"
    "opencode"
  ];

  rolesUnsupportedAdapters = lib.filter (name: !(lib.elem name roleCapableProviders)) (
    lib.attrNames enabledProviders
  );

  rolesNeeded = cfg.roles != { };

  rolesSpecBody = {
    agents = enabledNames cfg.providers;
    roles = lib.mapAttrs (_: roleSpecEntry) cfg.roles;
  };

  rolesSpecFile = pkgs.writeText "gentle-ai-roles-spec.json" (builtins.toJSON rolesSpecBody);

  # A declared MCP server's own JSON shape, in the same fields
  # `internal/mcp.Server` decodes: this is `gentle-nix mcp`'s own input
  # contract, not the document's -- see mcpSpecBody below.
  mcpServer =
    value:
    whenSet "command" value.command
    // whenSet "args" value.args
    // whenSet "env" value.env
    // whenSet "url" value.url
    // whenSet "headers" value.headers
    // optionalAttrs (value.enable != null) { enabled = value.enable; };

  # Wiring a user-declared MCP server is not something Gentle AI does
  # imperatively either -- it only wires its own fixed servers, such as
  # Context7 -- so `mcpServers` and every `providers.<id>.mcpServers` no
  # longer travel through the document at all. `gentle-nix mcp` writes them
  # straight into the rendered tree instead, the same post-processing step
  # roles and Pi routing already are -- see internal/mcp for the exact
  # per-adapter formats. Codex is the one exception: its config lives in
  # TOML, so it is resolved separately below (codexMcpServers) and routed
  # through the existing TOML merger instead of this subcommand.
  mcpSpecBody = {
    agents = enabledNames cfg.providers;
    servers = lib.mapAttrs (_: mcpServer) cfg.mcpServers;
    assignments = lib.mapAttrs (_: provider: lib.mapAttrs (_: mcpServer) provider.mcpServers) (
      lib.filterAttrs (_: provider: provider.mcpServers != { }) cfg.providers
    );
  };

  # The adapters `internal/mcp` (gentle-nix's own MCP renderer) knows how to
  # write a server for, plus codex (handled separately by this module's own
  # TOML path below) -- mirrors the pinned fork's own set of adapters whose
  # MCPStrategy is not "unsupported". hermes and the OS-variant IDE clients
  # (windsurf, trae-ide, vscode-copilot, antigravity) have none.
  mcpCapableProviders = [
    "claude-code"
    "cursor"
    "kimi"
    "kiro-ide"
    "pi"
    "gemini-cli"
    "qwen-code"
    "openclaw"
    "opencode"
    "kilocode"
    "codex"
  ];

  mcpUnsupportedAdapters = lib.filter (name: !(lib.elem name mcpCapableProviders)) (
    lib.attrNames enabledProviders
  );

  mcpNeeded = mcpSpecBody.servers != { } || mcpSpecBody.assignments != { };

  mcpSpecFile = pkgs.writeText "gentle-ai-mcp-spec.json" (builtins.toJSON mcpSpecBody);

  # Codex keeps its MCP config in config.toml, so `gentle-nix mcp` never
  # writes it: resolving Codex's own declared set here, the same
  # flat-set-or-full-replace rule `internal/mcp.declaredFor` applies for
  # every other adapter, is what lets the module hand it to the existing
  # TOML merger below instead. Env is dropped, and there is no "enabled"
  # field, because the pinned fork's own Codex TOML writer
  # (filemerge.UpsertCodexMCPServerBlock / UpsertCodexRemoteMCPServerBlock)
  # never wrote either for an MCP server -- matching that, not "fixing" it,
  # is what keeps the bytes gentle-nix writes the ones the fork already did.
  codexMcpServers =
    if !(enabledProviders ? codex) then
      { }
    else if cfg.providers.codex.mcpServers != { } then
      cfg.providers.codex.mcpServers
    else
      cfg.mcpServers;

  codexMcpTomlEntry =
    value:
    if value.url != null then
      { url = value.url; } // optionalAttrs (value.headers != { }) { headers = value.headers; }
    else
      {
        command = value.command;
        # The fork's own Codex writer always emits `args = [...]`, even when
        # empty, rather than omitting it -- mcpServerType's own default ([ ])
        # already matches that, so no whenSet is needed here.
        inherit (value) args;
      };

  codexMcpToml = tomlSettingsFormat.generate "gentle-ai-codex-mcp-servers.toml" {
    mcp_servers = lib.mapAttrs (_: codexMcpTomlEntry) codexMcpServers;
  };

  # A user permission rule is not something every client expresses the same
  # way -- only Claude Code takes a declared allow/deny/ask rule list at all
  # -- so `permissions` no longer travels through the document either.
  # `gentle-nix permissions` unions it straight into `.claude/settings.json`
  # instead, the same post-processing step roles, MCP servers and Pi routing
  # already are -- see internal/permissions for the exact union semantics
  # and why only Claude Code qualifies.
  permissionsSpecBody = {
    agents = enabledNames cfg.providers;
  }
  // whenSet "allow" cfg.permissions.allow
  // whenSet "deny" cfg.permissions.deny
  // whenSet "ask" cfg.permissions.ask;

  permissionsNeeded =
    cfg.permissions.allow != [ ] || cfg.permissions.deny != [ ] || cfg.permissions.ask != [ ];

  permissionsSpecFile = pkgs.writeText "gentle-ai-permissions-spec.json" (
    builtins.toJSON permissionsSpecBody
  );

  # Per-client skill scoping -- `providers.<id>.skills` overriding the flat
  # list, and `skillExclusions` narrowing it everywhere else -- has no shape
  # to travel through the document: the contract's own "skills" field is one
  # flat list, decoded the same way for every client. So the document is
  # sent the UNION of every skill any client needs instead (every client's
  # own resolved set, flattened), which makes Gentle AI stage every needed
  # skill into every enabled client's own skills directory; `gentle-nix
  # skills` then prunes each directory back down to what that one client
  # actually resolves to -- see internal/skills for the exact resolution
  # rule and the per-adapter directories it prunes.
  # Exclusions alone must not narrow to nothing; flat stays `null` (Gentle
  # AI's default set) unless at least one entry is set to `true`.
  skillsFlatDeclared = enabledNames cfg.skills != [ ];

  skillsSpecBody = {
    agents = enabledNames cfg.providers;
    flat = if skillsFlatDeclared then enabledNames cfg.skills else null;
    exclusions = disabledNames cfg.skills;
    assignments = lib.mapAttrs (_: provider: provider.skills) (
      lib.filterAttrs (_: provider: provider.skills != null) enabledProviders
    );
  };

  # Sent only when narrowed; `[ ]` (omitted below) keeps the default staged.
  skillsUnion =
    if skillsFlatDeclared then
      lib.unique (
        lib.subtractLists skillsSpecBody.exclusions skillsSpecBody.flat
        ++ lib.concatLists (lib.attrValues skillsSpecBody.assignments)
      )
    else
      [ ];

  # No-op only when nothing narrows anyone's resolution.
  skillsScopingNeeded = skillsSpecBody.exclusions != [ ] || skillsSpecBody.assignments != { };

  skillsSpecFile = pkgs.writeText "gentle-ai-skills-spec.json" (builtins.toJSON skillsSpecBody);

  selection =
    whenSet "agents" (enabledNames cfg.providers)
    // whenSet "components" (enabledNames cfg.components)
    // whenSet "skills" skillsUnion
    // whenSet "communityTools" (enabledNames cfg.communityTools)
    // whenSet "openCodePlugins" (enabledNames cfg.openCodePlugins)
    // whenSet "persona" cfg.persona
    // whenSet "preset" cfg.preset
    // whenSet "sddMode" cfg.sdd.mode
    // optionalAttrs cfg.sdd.strictTdd { strictTDD = true; }
    // whenSet "scope" cfg.install.scope
    // whenSet "channel" cfg.install.channel
    // whenSet "rddMode" cfg.review.mode
    // whenSet "providers" providers
    // whenSet "claudePhaseAssignments" cfg.models.claudePhases
    // whenSet "codexCarrilModelAssignments" cfg.models.codexCarril
    // whenSet "codexPhaseModelAssignments" cfg.models.codexPhases
    // whenSet "codexOrchestrator" cfg.models.codexOrchestrator
    // cfg.settings;
  # `permissions` no longer travels through the document either -- see
  # permissionsSpecBody above -- and neither does `skillExclusions` or any
  # `providers.<id>.skills`; `skills` above is the union skillsSpecBody
  # describes, not the flat enabled set it used to be. See the comment on
  # providerBlock above for `mcpServers`, which also never travels through
  # the document.

  document = {
    version = cfg.schemaVersion;
    inherit selection;
  };

  documentFile = pkgs.writeText "gentle-ai-document.json" (builtins.toJSON document);

  base = pkgs.callPackage ../lib/render.nix { } {
    inherit document;
    inherit (config.home) homeDirectory;
    gentle-ai = cfg.package;
  };

  # Layering happens after Gentle AI has rendered, so an entry can add a file
  # Gentle AI does not ship and can replace one it does. Doing it here rather
  # than through a second home.file entry keeps the result one tree, which is
  # what makes overriding a generated file possible at all: two Home Manager
  # entries for one path collide instead of layering.
  #
  # The embedded Pi plugin travels the same tree for the same reason: landing
  # it through a second home.file entry would fight the one below for the
  # same directory the moment both exist, where layering onto one tree just
  # works.
  overlaid =
    if
      cfg.extraFiles == { }
      && !embedGentleEngramPiPlugin
      && providerSettings == { }
      && !piRoutingNeeded
      && !rolesNeeded
      && !mcpNeeded
      && codexMcpServers == { }
      && !permissionsNeeded
      && !skillsScopingNeeded
    then
      base
    else
      pkgs.runCommandLocal "gentle-ai-config-overlaid" { } ''
        cp -r --no-preserve=mode,ownership ${base} "$out"
        ${lib.optionalString embedGentleEngramPiPlugin ''
          target="$out/tree/${gentleEngramPiPluginPath}"
          mkdir -p "$(dirname "$target")"
          rm -rf "$target"
          cp -r --no-preserve=mode,ownership ${gentleEngramPiPackage} "$target"

          # `--no-preserve=mode` is what keeps a copied tree from carrying the
          # store's read-only bits, but it also drops the wrapper's execute
          # bit; that has to come back or `bin/pi-engram` stops being runnable
          # the moment it is copied rather than symlinked.
          chmod -R u+rwX,go+rX "$target"
          find "$target/bin" -type f -exec chmod +x {} +
        ''}
        ${lib.optionalString piRoutingNeeded ''
          # gentle-nix pi routing writes gentle-pi's own routing and profile
          # store, and the orchestrator defaults it merges into
          # .pi/agent/settings.json. It has to run before the
          # `gentle-nix settings` loop below: an operator's own
          # `providers.pi.settings` is a decision, a profile's orchestrator
          # default is only a fallback, and the settings loop's overlay
          # always wins at a shared leaf (see internal/settings'
          # mergeObjects) -- so the fallback has to be the base and the
          # decision the overlay, not the other way around.
          ${lib.optionalString (piRoutingSpecBody ? presets) ''
            # The verb is probed by running it: `--help` exits non-zero by
            # design of the flag parser, so only the real call says whether
            # this build has it.
            ${lib.getExe cfg.package} config presets --provider ${lib.escapeShellArg piRoutingSpecBody.modelFamily} --json > ${lib.escapeShellArg piPresetsRelPath} || {
              echo "gentle-ai config presets: not supported by the pinned gentle-ai build (${cfg.package}); cannot fill providers.pi.modelPreset ${lib.escapeShellArg piRoutingSpecBody.modelPreset} for modelFamily ${lib.escapeShellArg piRoutingSpecBody.modelFamily}" >&2
              exit 1
            }
          ''}
          ${lib.getExe gentleNix} pi routing \
            --tree "$out/tree" \
            --spec ${piRoutingSpecFile}
        ''}
        ${lib.optionalString rolesNeeded ''
          # gentle-nix roles renders every declared programs.gentle-ai.roles
          # entry onto the tree, the same post-processing step pi routing
          # is above. It runs before the `gentle-nix settings` loop below
          # for the same reason: a rendered role is only ever a fallback
          # shape for whatever an operator's own `providers.opencode.settings`
          # decides at the same key (e.g. that role's own entry under
          # `agent.<name>`), and the settings loop's overlay always wins at
          # a shared leaf -- so the role has to be the base and the
          # operator's own setting the overlay, not the other way around.
          ${lib.getExe gentleNix} roles \
            --tree "$out/tree" \
            --spec ${rolesSpecFile}
        ''}
        ${lib.optionalString mcpNeeded ''
          # gentle-nix mcp writes every declared MCP server onto the tree,
          # the same post-processing step roles and Pi routing are above,
          # and for the same reason it runs before the `gentle-nix settings`
          # loop below: a rendered server is only ever a fallback shape for
          # whatever an operator's own `providers.<name>.settings` decides
          # at the same key, and the settings loop's overlay always wins at
          # a shared leaf -- so the declared server has to be the base and
          # the operator's own setting the overlay, not the other way
          # around. Codex is excluded here; it is merged from
          # codexMcpToml below instead.
          ${lib.getExe gentleNix} mcp \
            --tree "$out/tree" \
            --spec ${mcpSpecFile}
        ''}
        ${lib.optionalString permissionsNeeded ''
          # gentle-nix permissions unions every declared
          # programs.gentle-ai.permissions rule into .claude/settings.json,
          # the same post-processing step roles, MCP servers and Pi routing
          # are above, and for the same reason it runs before the
          # `gentle-nix settings` loop below: a declared rule is unioned
          # onto whatever is already there, while an operator's own
          # `providers.claude-code.settings.permissions` is a decision that
          # should win outright at the same key -- so the union has to be
          # the base and the operator's own setting the overlay, not the
          # other way around.
          ${lib.getExe gentleNix} permissions \
            --tree "$out/tree" \
            --spec ${permissionsSpecFile}
        ''}
        ${lib.optionalString skillsScopingNeeded ''
          # gentle-nix skills prunes every enabled client's skills directory
          # down to what it actually resolves to -- its own
          # providers.<id>.skills assignment, or the flat set minus
          # skillExclusions otherwise. It runs after the base render (which
          # already staged the union skillsSpecBody describes into every
          # client) and before extraFiles below, so a skill an operator adds
          # of their own through extraFiles is never at risk of being pruned
          # as unresolved.
          ${lib.getExe gentleNix} skills \
            --tree "$out/tree" \
            --spec ${skillsSpecFile}
        ''}
        ${lib.optionalString (codexMcpServers != { }) ''
          # Codex keeps its MCP config in config.toml, so its declared
          # servers are merged through the same Python TOML merger Codex's
          # other settings already use, rather than through `gentle-nix
          # mcp` -- see codexMcpServers and codexMcpToml above. This runs
          # before the TOML settings loop below for the same base/overlay
          # precedence reason the JSON case does.
          target="$out/tree/${tomlSettingsPaths.codex}"
          mkdir -p "$(dirname "$target")"
          ${lib.getExe merger} \
            --fragment ${codexMcpToml} \
            --target "$target"
          chmod 644 "$target"
        ''}
        ${lib.concatMapStringsSep "\n" (name: ''
          ${lib.getExe gentleNix} settings \
            --tree "$out/tree" \
            --provider ${lib.escapeShellArg "${name}=${pkgs.writeText "gentle-ai-provider-settings-${name}.json" (builtins.toJSON jsonProviderSettings.${name})}"}
        '') (lib.attrNames jsonProviderSettings)}
        ${lib.concatMapStringsSep "\n" (name: ''
          target="$out/tree/${tomlSettingsPaths.${name}}"
          mkdir -p "$(dirname "$target")"
          ${lib.getExe merger} \
            --fragment ${
              tomlSettingsFormat.generate "gentle-ai-provider-settings-${name}.toml" tomlProviderSettings.${name}
            } \
            --target "$target"

          # The merger writes credentials elsewhere, so it keeps its output
          # private; here the result is a store path Gentle AI renders
          # from, which nothing can read at mode 600.
          chmod 644 "$target"
        '') (lib.attrNames tomlProviderSettings)}
        ${lib.concatMapStringsSep "\n" (
          entry:
          let
            content =
              if entry.source != null then entry.source else pkgs.writeText "gentle-ai-extra-file" entry.text;
          in
          if entry.mode == "append" then
            ''
              target="$out/tree/${entry.target}"
              mkdir -p "$(dirname "$target")"
              touch "$target"
              cat ${content} >> "$target"
            ''
          else if entry.mode == "merge" then
            ''
              target="$out/tree/${entry.target}"
              mkdir -p "$(dirname "$target")"
              ${lib.getExe merger} \
                --fragment ${content} \
                --target "$target" \
                ${lib.concatMapStringsSep " " (path: "--union-list ${lib.escapeShellArg path}") entry.unionLists}

              # The merger writes credentials elsewhere, so it keeps its output
              # private. Here the result is a store path Gentle AI renders from,
              # which nothing can read at mode 600.
              chmod 644 "$target"
            ''
          else if entry.mode == "fill" then
            ''
              target="$out/tree/${entry.target}"
              mkdir -p "$target"
              cp -r --no-preserve=mode,ownership --no-clobber ${content}/. "$target/" 2>/dev/null || true
            ''
          else
            ''
              target="$out/tree/${entry.target}"
              mkdir -p "$(dirname "$target")"
              rm -rf "$target"
              cp -r --no-preserve=mode,ownership ${content} "$target"
            ''
        ) (lib.attrValues cfg.extraFiles)}
      '';

  rendered = cfg.overrideRendered overlaid;

  # A file that has to carry a credential cannot be a store symlink: the store
  # is world-readable and read-only, so the value could neither be kept private
  # nor written at all. Those paths are held back from the projection and
  # delivered as real files at activation instead, with the placeholder replaced
  # by the contents of a file the operator points at.
  #
  # Where that file comes from is deliberately not this module's business: a
  # sops-nix or agenix secret exposes exactly such a path, and so does a plain
  # file, so none of them has to be a dependency here.
  # `providerSecretPaths`/`providerMergeTargets` are declared with
  # `providerRoots`, below this binding in the file, but `let` bindings are
  # lazy and mutually visible regardless of order, so referencing them here
  # costs nothing and keeps `withheld` next to the option it is withholding
  # against.
  allSecretPaths = lib.unique (cfg.secrets.paths ++ providerSecretPaths);
  allMergeTargets = mergeTargets ++ providerMergeTargets;

  withheld = allSecretPaths ++ map (entry: entry.path) allMergeTargets;

  # gentle-nix is the one Go binary this repository builds from its own
  # source (cmd/gentle-nix, internal/...), replacing four of the five
  # writePython3Bin helpers that used to be wrapped here. Each is exposed
  # under its old binary name through a one-line shell wrapper, so an
  # activation script, a stamp file, or a check that names
  # "gentle-ai-provision" (or -retire, -rewrite, -frontmatter) keeps
  # working unchanged: only what runs behind that name changed.
  #
  # "merge" is the one helper still Python: it depends on tomlkit's
  # comment- and ordering-preserving TOML editing, which has no dependable
  # Go equivalent, so gentle-ai-merge stays as it was below.
  gentleNix = pkgs.callPackage ../packages/gentle-nix.nix { };

  provisioner = pkgs.writeShellScriptBin "gentle-ai-provision" ''
    exec ${lib.getExe gentleNix} provision "$@"
  '';

  retirer = pkgs.writeShellScriptBin "gentle-ai-retire" ''
    exec ${lib.getExe gentleNix} retire "$@"
  '';

  piSettingsPath = "${config.home.homeDirectory}/.pi/agent/settings.json";

  # A displaced entry is one Pi still lists that the channel this generation
  # picked no longer wants: a package now installed under a different source,
  # or a plugin build now installed by a different path. Each rule names one
  # identity a channel choice displaces; `gentle-ai-retire` reads it back
  # against Pi's own settings.json, never against a copy this module keeps.
  # gentle-pi's own npm default, spelled the way the fixed sequence's own
  # unoverridden `pi install npm:<name>` command would spell it -- the
  # `wanted` a rule compares against when there is no channel override.
  gentlePiNpmDefault = "npm:gentle-pi";
  gentleEngramNpmDefault = "npm:gentle-engram";

  # Every rule below carries a `wanted` spelling: the exact entry (or, for a
  # local path, the location it resolves to) that has to already be present
  # in Pi's freshly read package list before that rule is allowed to retire
  # anything. Without this, retiring right after a provisioning step that
  # failed silently -- a registry or git host unreachable, which costs only
  # the provisioning step's own packages, never the switch -- would remove
  # the previous, working entry and leave nothing installed at all until some
  # later switch happens to reach the network. Requiring the replacement
  # first is what keeps that failure costing only a missed retirement instead
  # of the harness itself.
  displacedPiRules =
    lib.optional (cfg.gentlePiRelease != "stable") {
      type = "npm";
      name = "gentle-pi";
      wanted = pluginPackagesFor.gentle-pi;
    }
    # A revision bump within the same non-stable channel is still a source
    # change: the earlier rev's git entry is a different spelling of the same
    # package, so it displaces the same way a user-declared package's own
    # source change does, and is retired the same way -- by package identity,
    # keeping only the exact source this generation declared.
    ++ lib.optional (cfg.gentlePiRelease != "stable") {
      type = "package";
      keep = pluginPackagesFor.gentle-pi;
      wanted = pluginPackagesFor.gentle-pi;
    }
    ++ lib.optional (cfg.gentlePiRelease == "stable") {
      type = "git";
      name = "gentle-pi";
      wanted = gentlePiNpmDefault;
    }
    ++ lib.optional (cfg.engramRelease != "stable") {
      type = "npm";
      name = "gentle-engram";
      wanted = gentleEngramPiHomePath;
    }
    ++ [
      (
        {
          type = "local";
          # A plugin installed by store path changes identity on every
          # rebuild, so the versioned store path itself is always displaced,
          # regardless of channel; a plugin installed at some earlier stable
          # path is displaced the same way.
          patterns = [
            "-gentle-engram-pi-[^/]*$"
            "/gentle-engram$"
          ];
        }
        // (
          if cfg.engramRelease != "stable" then
            {
              # The one local entry this generation still wants kept, off
              # stable. On stable there is none to except: every local entry,
              # the current plugin path included, is displaced.
              except = gentleEngramPiHomePath;
              wanted = gentleEngramPiHomePath;
            }
          else
            {
              wanted = gentleEngramNpmDefault;
            }
        )
      )
    ]
    # A user-declared extension package changing its source displaces its own
    # earlier entry the same way a channel change displaces gentle-pi's or
    # gentle-engram's: same package, different identity. The identity is read
    # from the source itself, never from the attribute key here -- the key is
    # free-form and Pi has no notion of it. Dropping a package from the set
    # entirely is not covered -- there is no record here of what an earlier
    # generation declared, only what this one does -- so that still needs a
    # manual `pi remove`, as `packages`'s own description says.
    ++ lib.mapAttrsToList (_: source: {
      type = "package";
      keep = source;
      wanted = source;
    }) (cfg.providers.pi.packages or { });

  # `providers.pi.packages` exactly as this generation declares it, handed
  # to `gentle-nix retire` alongside a record of what the previous
  # generation declared (below) so a package dropped from the set entirely
  # -- something no displaced-package rule above can express, since every
  # one of them names what a still-declared package used to look like, never
  # a package that stopped being declared at all -- is retired too, instead
  # of needing a manual `pi remove`.
  declaredPiPackagesFile = pkgs.writeText "gentle-ai-declared-pi-packages.json" (
    builtins.toJSON (cfg.providers.pi.packages or { })
  );

  # Where the retirer persists the declared set it was just handed, for the
  # next switch to diff against. Lives under the same state directory
  # `gentle-nix provision`'s own stamps do, so both survive the same way
  # across generations and neither is ever mistaken for a Nix store path.
  declaredPiPackagesRecordPath = "${config.xdg.stateHome}/gentle-ai-nix/pi-declared-packages.json";

  # Which clients were asked to have their package harness installed. The
  # commands themselves are read from the rendered manifest at activation, so
  # this module never holds a copy of a package list that could go stale.
  provisioningProviders = lib.attrNames (
    lib.filterAttrs (_: provider: provider.provisionPackages) enabledProviders
  );

  piProvisionsPackages = piEnabled && enabledProviders.pi.provisionPackages;

  # Community tools wire themselves into the clients through their own CLI. That
  # call is local and idempotent, unlike a client's package installation, so it
  # follows the declaration rather than needing a second opt-in.
  provisioningTools = lib.attrNames (
    lib.filterAttrs (_: tool: tool.enable && tool.provision) cfg.communityTools
  );

  provisionEnvironmentFor =
    name:
    lib.concatMapStringsSep " " (
      variable:
      "${variable}=${lib.escapeShellArg enabledProviders.${name}.provisionEnvironment.${variable}}"
    ) (lib.attrNames enabledProviders.${name}.provisionEnvironment);

  merger = pkgs.writers.writePython3Bin "gentle-ai-merge" {
    libraries = [ pkgs.python3Packages.tomlkit ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../lib/merge.py);

  referenceRewriter = pkgs.writeShellScriptBin "gentle-ai-rewrite" ''
    exec ${lib.getExe gentleNix} rewrite "$@"
  '';

  frontmatterFiller = pkgs.writeShellScriptBin "gentle-ai-frontmatter" ''
    exec ${lib.getExe gentleNix} frontmatter "$@"
  '';

  secretArguments =
    lib.concatMapStringsSep " " (path: "--env-file ${lib.escapeShellArg path}") cfg.secrets.envFiles
    + " "
    + lib.concatMapStringsSep " " (
      name: "--secret ${lib.escapeShellArg "${name}=${cfg.secrets.placeholders.${name}}"}"
    ) (lib.attrNames cfg.secrets.placeholders);

  # The plugin's entry point must reach the home executable. An
  # `overrideRendered` sits between the overlay that set the bit and this
  # projection, and a copy in there that drops modes -- the usual
  # `--no-preserve=mode` idiom -- is what a `permission denied` at activation
  # looks like, so the bit is put back here rather than trusted to survive.
  restoreExecutables = lib.optionalString embedGentleEngramPiPlugin ''
    find "$out/tree/${gentleEngramPiPluginPath}/bin" -type f -exec chmod +x {} +
  '';

  projected =
    if withheld == [ ] && !embedGentleEngramPiPlugin then
      rendered
    else
      # Modes are kept on the way through; ownership is not ours to keep, and
      # the copy is made writable so the withheld paths can go.
      pkgs.runCommandLocal "gentle-ai-config-projected" { } ''
        cp -r --no-preserve=ownership ${rendered} "$out"
        chmod -R u+w "$out"
        ${lib.concatMapStringsSep "\n" (path: ''rm -f "$out/tree/${path}"'') withheld}
        ${restoreExecutables}
      '';

  providerRoots = {
    "opencode" = ".config/opencode";
    "claude-code" = ".claude";
    "codex" = ".codex";
    "pi" = ".pi";
    "gemini-cli" = ".gemini";
    "qwen-code" = ".qwen";
    "kimi" = ".kimi";
    "openclaw" = ".openclaw";
  };

  # A provider-scoped secret path is written relative to that provider's own
  # root, so it is resolved against `providerRoots` and normalised to the
  # home-relative spelling `withheld` and the merge/activation loops already
  # work in -- the two forms have to land on exactly the same path, or an
  # operator switching from one spelling to the other would see a file
  # suddenly reappear in the projection or drop out of the merge set.
  #
  # A leading `../` component is how a path reaches outside the provider's
  # root for the rare file a client keeps beside it instead of inside it
  # (Claude Code's `.claude.json`, next to `.claude/`); walking the joined
  # path component by component, popping the stack on `..`, is what resolves
  # that back to a home-relative path without ever shelling out to a real
  # filesystem path (these are declaration-time strings, not paths that have
  # to exist). Popping past an empty stack means the entry would land outside
  # the home directory entirely, which is refused below rather than silently
  # clipped to whatever the stack still held.
  resolveProviderSecretPath =
    root: path:
    let
      combined = "${root}/${path}";
      parts = lib.filter (part: part != "" && part != ".") (lib.splitString "/" combined);
      step =
        acc: part:
        if acc.escaped then
          acc
        else if part == ".." then
          if acc.out == [ ] then
            acc // { escaped = true; }
          else
            acc // { out = lib.sublist 0 (lib.length acc.out - 1) acc.out; }
        else
          acc // { out = acc.out ++ [ part ]; };
      result = lib.foldl' step {
        out = [ ];
        escaped = false;
      } parts;
    in
    result // { path = lib.concatStringsSep "/" result.out; };

  providersDeclaringSecrets = lib.filterAttrs (
    _: provider: provider.secrets.paths != [ ] || provider.secrets.merge != [ ]
  ) cfg.providers;

  # Named for the assertion below rather than resolved: a provider Gentle AI
  # has no root for cannot have its declared secrets normalised at all, so
  # this is checked before `providerSecrets` ever touches `providerRoots.
  # ${name}` for one.
  unknownSecretsProviders = lib.attrNames (
    lib.filterAttrs (name: _: !(providerRoots ? ${name})) providersDeclaringSecrets
  );

  # Escaped entries are named the same way, by provider and the path as
  # declared, so the assertion below can point at exactly what was written
  # instead of the stack this module reduced it to.
  escapedProviderSecretPaths = lib.concatLists (
    lib.mapAttrsToList (
      name: provider:
      let
        root = providerRoots.${name};
      in
      lib.optional (lib.any (path: (resolveProviderSecretPath root path).escaped) provider.secrets.paths)
        {
          inherit name;
          path = lib.findFirst (
            path: (resolveProviderSecretPath root path).escaped
          ) null provider.secrets.paths;
        }
      ++ lib.concatMap (
        entry:
        let
          path = if builtins.isString entry then entry else entry.path;
        in
        lib.optional (resolveProviderSecretPath root path).escaped {
          inherit name path;
        }
      ) provider.secrets.merge
    ) (lib.filterAttrs (name: _: providerRoots ? ${name}) providersDeclaringSecrets)
  );

  providerSecretsFor =
    name: provider:
    let
      root = providerRoots.${name};
      resolve = path: (resolveProviderSecretPath root path).path;
    in
    {
      paths = map resolve provider.secrets.paths;
      merge = map (
        entry:
        if builtins.isString entry then
          {
            path = resolve entry;
            unionLists = [ ];
          }
        else
          entry // { path = resolve entry.path; }
      ) provider.secrets.merge;
    };

  providerSecrets = lib.mapAttrsToList providerSecretsFor (
    lib.filterAttrs (name: _: providerRoots ? ${name}) providersDeclaringSecrets
  );

  providerSecretPaths = lib.concatMap (entry: entry.paths) providerSecrets;
  providerMergeTargets = lib.concatMap (entry: entry.merge) providerSecrets;

  # A client Gentle AI has no adapter for still reads the same kind of harness,
  # so it is given one another client already produced rather than a hand-written
  # mapping that drifts the moment Gentle AI changes what it renders.
  customProviderCopies = lib.concatLists (
    lib.mapAttrsToList (
      name: provider:
      let
        sourceRoot = providerRoots.${provider.from};
        source = "${rendered}/tree/${sourceRoot}";
        pairs =
          if provider.assets == { } then
            [
              {
                from = ".";
                to = ".";
              }
            ]
          else
            lib.mapAttrsToList (from: to: { inherit from to; }) provider.assets;

        # What the assets say about themselves, derived from what they were
        # renamed to rather than declared a second time. The source root is the
        # last entry so it covers whatever the mapping does not name; the
        # rewriter applies the most specific match, so a renamed file keeps its
        # new name instead of its old one under the new root.
        replacements =
          map (pair: "${sourceRoot}/${pair.from}=${provider.root}/${pair.to}") (
            builtins.filter (pair: pair.from != ".") pairs
          )
          ++ [ "${sourceRoot}/=${provider.root}/" ];

        # Rewriting at build time keeps activation the plain copy it is, and
        # puts the result in the store where it is reproducible.
        rewritten = pkgs.runCommandLocal "gentle-ai-custom-provider-${name}" { } ''
          ${lib.getExe referenceRewriter} \
            --source ${lib.escapeShellArg source} \
            --target "$out" \
            ${lib.concatMapStringsSep " " (entry: "--replace ${lib.escapeShellArg entry}") replacements}
        '';

        delivered = if provider.rewriteReferences then "${rewritten}" else source;

        # A required key the source dialect never writes is filled per asset,
        # after the rewrite, so the filled copy carries this client's own
        # references too.
        filled =
          pair:
          let
            defaults = provider.frontmatterDefaults.${pair.from};
          in
          pkgs.runCommandLocal "gentle-ai-custom-provider-${name}-frontmatter" { } ''
            ${lib.getExe frontmatterFiller} \
              --source ${lib.escapeShellArg "${delivered}/${pair.from}"} \
              --target "$out" \
              ${lib.concatMapStringsSep " " (
                key: "--default ${lib.escapeShellArg "${key}=${defaults.${key}}"}"
              ) (lib.attrNames defaults)}
          '';
      in
      map (pair: {
        inherit (provider) delivery;
        source =
          if provider.frontmatterDefaults ? ${pair.from} then
            "${filled pair}"
          else
            "${delivered}/${pair.from}";
        target = "${provider.root}/${pair.to}";
      }) pairs
    ) cfg.customProviders
  );

  copiedTargets = builtins.filter (entry: entry.delivery == "copy") customProviderCopies;
  linkedTargets = builtins.filter (entry: entry.delivery == "symlink") customProviderCopies;

  unknownSourceProviders = lib.attrNames (
    lib.filterAttrs (
      _: provider: !(providerRoots ? ${provider.from}) || !(enabledProviders ? ${provider.from})
    ) cfg.customProviders
  );

  engramEnabled = cfg.components ? engram && cfg.components.engram.enable;

  enabledCommunityToolPackages = lib.mapAttrsToList (_: tool: tool.package) (
    lib.filterAttrs (_: tool: tool.enable) cfg.communityTools
  );

  packages = builtins.filter (package: package != null) (
    [ cfg.package ] ++ lib.optional engramEnabled cfg.engramPackage ++ enabledCommunityToolPackages
  );

  enableGroup =
    what:
    mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options.enable = mkEnableOption "the ${name} ${what}";
          }
        )
      );
      default = { };
      description = ''
        The ${what}s to configure, keyed by Gentle AI's own id. The names are
        deliberately not enumerated here: Gentle AI rejects one it does not know
        rather than ignoring it, so a ${what} it gains works the day it ships.
      '';
    };
in
{
  options.programs.gentle-ai = {
    enable = mkEnableOption "Gentle AI";

    release = mkOption {
      type = types.enum (lib.attrNames releases);
      default = "contract";
      description = ''
        Which Gentle AI release to build, by channel.

        `stable` is the newest tagged release. `beta` is the tip of Gentle AI's
        main branch, which is what `gentle-ai upgrade --channel beta` resolves
        to. `contract` is main with the declarative configuration contract this
        module renders through on top, and is the default only because no
        upstream channel has that contract yet: choosing another one builds
        fine and then fails when the renderer runs, because `gentle-ai config`
        does not exist there.

        Setting `package` directly overrides this.
      '';
    };

    package = mkOption {
      type = types.package;
      default = defaultGentleAiPackage;
      defaultText = literalExpression "gentle-ai-nix.packages.\${pkgs.system}.gentle-ai";
      description = ''
        Gentle AI package. It both renders the configuration and is installed,
        so what runs matches what was rendered.
      '';
    };

    engramPackage = mkOption {
      type = types.nullOr types.package;
      default = defaultEngramPackage;
      defaultText = literalExpression "gentle-ai-nix.packages.\${pkgs.system}.engram";
      description = ''
        Engram package, installed when the engram component is enabled. The
        component is what configures the clients to use it; this only puts the
        binary on PATH, which Nix does rather than letting Gentle AI fetch it.

        Defaults to `engramRelease`'s build; setting this directly overrides
        that choice the same way `package` overrides `release`.
      '';
    };

    gentlePiRelease = mkOption {
      type = types.enum (lib.attrNames gentlePiReleases);
      default = "stable";
      description = ''
        Which gentle-pi release Pi installs, by channel.

        `stable` is npm's published release, which is what Pi already
        installs on its own; choosing it changes nothing about how Pi's
        packages are provisioned. `main` is the tip of gentle-pi's main
        branch pinned to a revision, installed from git instead of npm --
        the same "a pin is how a flake expresses a branch" argument
        `release` above makes for Gentle AI's own beta channel.

        gentle-pi is not a package this flake builds: Nix only supplies the
        install source Pi's `pi install` uses at activation.
      '';
    };

    engramRelease = mkOption {
      type = types.enum (lib.attrNames engramReleases);
      default = "stable";
      description = ''
        Which Engram release to build, by channel. Controls both the Engram
        binary (`engramPackage`'s default) and, when Pi is enabled, which
        build of Engram's Pi plugin Pi installs -- the two are one release
        moving together, because a store with one Engram's wire format and
        another's Pi plugin is not a configuration anyone chose on purpose.

        `stable` is the newest tagged release, and Pi installs its plugin
        from npm as it always has. `rc` is the 2.0 candidate selectable in
        engram-versions.nix; choosing it also has Pi install the plugin
        built from that same revision, so the harness binary and the plugin
        can never drift apart. The build is linked into the rendered tree at
        `.pi/gentle-ai/plugins/gentle-engram`, a path stable across rebuilds,
        rather than installed from its own store path directly: Pi records a
        local source by its path, so the store path itself would change
        identity on every rebuild and leave Pi holding two entries for what
        is meant to be the same plugin.

        Setting `engramPackage` directly overrides the binary this resolves
        to, but not which plugin build Pi installs.
      '';
    };

    schemaVersion = mkOption {
      type = types.str;
      default = "v1";
      description = ''
        Version of the Gentle AI configuration schema this document is written
        against. Gentle AI rejects a version it cannot interpret, so pinning it
        turns an incompatible upgrade into a build failure rather than a silent
        reinterpretation.
      '';
    };

    providers = mkOption {
      type = types.attrsOf providerType;
      default = { };
      example = literalExpression ''
        {
          opencode.enable = true;
          claude-code = {
            enable = true;
            skills = [ "cognitive-doc-design" ];
            settings.theme = "system";
          };
        }
      '';
      description = "Clients to configure, keyed by Gentle AI's own provider id.";
    };

    components = enableGroup "component";

    skills = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options.enable = mkEnableOption "the ${name} skill";
          }
        )
      );
      default = { };
      example = literalExpression "{ go-testing.enable = false; }";
      description = ''
        Skills, keyed by Gentle AI's own id. Naming none installs every skill
        Gentle AI ships, so this is only for narrowing that: an entry set to
        false excludes one skill and leaves the rest, and any entry set to true
        narrows the installation to the ones named.

        This resolves the same way for every client except one that sets its
        own `providers.<id>.skills`, which fully replaces this resolution for
        that client only. Resolution happens through `gentle-nix skills` as
        post-processing of the tree: setting an entry to `true` narrows the
        document's `skills` to those named (unioned with every assignment);
        `false` entries alone, or none at all, leave `skills` out of the
        document entirely, so a client without its own assignment keeps
        Gentle AI's default set minus any `false` entries.
      '';
    };

    communityTools = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              enable = mkEnableOption "the ${name} community tool";

              provision = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Let the tool point itself at the declared clients during
                  activation, by running the command Gentle AI declares for it.

                  Configuring a tool and never wiring it leaves prompts that
                  describe a server nothing configured. The call is local and
                  idempotent, so unlike a client's package installation it
                  follows the declaration instead of asking again.
                '';
              };

              package = mkOption {
                type = types.nullOr types.package;
                default = communityToolPackages.${name} or null;
                defaultText = literalMD "the package this flake ships for the tool, when it ships one, and `null` otherwise";
                example = literalExpression "pkgs.codegraph";
                description = ''
                  The tool's own binary, installed alongside the harness when
                  this tool is enabled.

                  Gentle AI would otherwise fetch it through a package manager
                  at install time. Taking it from Nix is the same choice the
                  engram component makes: nothing is downloaded at activation
                  and the version is the one this configuration pins.

                  A tool this flake packages already defaults to that package,
                  so enabling it is enough. For any other tool the default is
                  null, and then the tool is configured and the binary is your
                  business.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = ''
        The community tools to configure, keyed by Gentle AI's own id. The names
        are deliberately not enumerated here: Gentle AI rejects one it does not
        know rather than ignoring it, so a tool it gains works the day it ships.
      '';
    };
    openCodePlugins = enableGroup "OpenCode plugin";

    persona = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Persona applied to the generated guidance.";
    };

    preset = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Preset the installation starts from.";
    };

    sdd = {
      mode = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SDD orchestrator mode.";
      };
      strictTdd = mkOption {
        type = types.bool;
        default = false;
        description = "Whether SDD phases enforce strict TDD.";
      };
    };

    review.mode = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Global review kill switch. Left unset, the machine's own setting stands:
        this is a user-owned choice, so declaring it is opting into managing it.
      '';
    };

    backgroundSubagents =
      let
        intent =
          client:
          mkOption {
            type = types.nullOr (
              types.enum [
                "auto"
                "on"
                "off"
              ]
            );
            default = null;
            example = "on";
            description = ''
              Whether ${client} runs its sub-agents in the background, which
              changes the orchestration policy its prompts carry.

              `on` and `off` are the answer; `auto` defers to whatever the
              client's runtime turns out to support, and renders the same thing as
              declaring nothing, because a build cannot ask the runtime without
              making the same configuration differ per machine.
            '';
          };
      in
      {
        opencode = intent "OpenCode";
        pi = intent "Pi";
      };

    models = {
      claudePhases = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        example = literalExpression ''{ sdd-apply = { model = "opus"; effort = "high"; }; }'';
        description = "Claude phase assignments carrying both a model and an effort.";
      };
      codexCarril = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Codex carril to model id.";
      };
      codexPhases = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Codex phase to model id.";
      };
      codexOrchestrator = mkOption {
        type = types.nullOr (types.attrsOf types.anything);
        default = null;
        description = "Model and effort for the Codex main session.";
      };

    };

    # Only Claude Code takes a declared allow/deny/ask rule list at all --
    # every other client either has no injectable permission overlay, or
    # keys it a different way entirely. Rendered by `gentle-nix permissions`
    # as post-processing of the tree, not by Gentle AI itself: it unions
    # these rules onto whatever the shipped overlay already put at
    # `.claude/settings.json`'s own `permissions.allow/deny/ask`, so a rule
    # this declares never removes a guardrail it does not repeat.
    permissions = {
      allow = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Rules allowed on top of the shipped guardrails.";
      };
      deny = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Rules denied on top of the shipped guardrails.";
      };
      ask = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Rules that prompt on top of the shipped guardrails.";
      };
    };

    mcpServers = mkOption {
      type = types.attrsOf mcpServerType;
      default = { };
      description = ''
        MCP servers, keyed by name. A server a component already configures does
        not need an entry here; this is for the ones only you know about.

        Rendered by `gentle-nix mcp` as post-processing of the tree, not by
        Gentle AI itself: wiring a user-declared server is not something Gentle
        AI does imperatively. Every enabled client can express one except
        hermes and the OS-variant IDE clients (windsurf, trae-ide,
        vscode-copilot, antigravity) -- declaring a server while one of those
        is enabled fails at eval rather than silently dropping it.
      '';
    };

    roles = mkOption {
      type = types.attrsOf roleType;
      default = { };
      example = literalExpression ''
        {
          orchestrator = {
            renderedName = "my-orchestrator";
            mode = "primary";
            references = [ "apply" ];
          };
          apply = {
            renderedName = "my-apply";
            mode = "subagent";
          };
        }
      '';
      description = "Logical agent roles, keyed by id. References name ids, never rendered names.";
    };

    install = {
      scope = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Install scope.";
      };
      channel = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Release channel.";
      };
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = literalExpression "{ someNewContractField = true; }";
      description = ''
        Raw `selection` fields merged last, overriding everything the grouped
        options produced. This is the escape hatch for a contract field newer
        than this module.
      '';
    };

    customProviders = mkOption {
      type = types.attrsOf customProviderType;
      default = { };
      example = literalExpression ''
        {
          agens = {
            root = ".config/agens";
            from = "claude-code";
            delivery = "copy";
            assets = {
              "CLAUDE.md" = "AGENTS.md";
              agents = "agents";
              commands = "commands";
              skills = "skills";
            };
          };
        }
      '';
      description = ''
        Clients Gentle AI has no adapter for, given the harness another client
        already produced. This is how a tool that reads the same kind of agents
        and skills participates without Gentle AI needing to learn about it.
      '';
    };

    secrets = {
      paths = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = literalExpression ''[ ".claude/mcp/atlas.json" ]'';
        description = ''
          Rendered paths that carry a credential and that Gentle AI owns whole.
          They are kept out of the projection and written as real files at
          activation with every placeholder below replaced, because a store
          symlink can be neither private nor written.

          Every entry here is relative to the home directory, which means
          knowing where Gentle AI rooted the client that owns it.
          `providers.<name>.secrets.paths` takes the same entries relative to
          that client's own root instead, and is the preferred spelling for a
          path that belongs to one client.
        '';
      };

      merge = mkOption {
        type = types.listOf (types.either types.str mergeTargetType);
        default = [ ];
        example = literalExpression ''
          [
            ".claude.json"
            {
              path = ".pi/agent/settings.json";
              unionLists = [ "packages" ];
            }
          ]
        '';
        description = ''
          Rendered paths Gentle AI shares with the client itself. Claude Code
          keeps its OAuth and project history in `.claude.json`, Codex its
          per-project trust levels in `config.toml`, so writing the rendered
          copy over them would take that state with it. The fragment is merged
          in instead and everything it does not mention is left alone.

          JSON and TOML are supported; TOML keeps its comments and ordering.
          Merging is additive, so a server dropped from the document is not
          removed from the file — that entry may be one the client wrote, and
          this file is not ours to prune.

          An entry is a path, or an attribute set naming the arrays in it the
          client appends to itself. See `unionLists` for when that matters.

          Every path here is relative to the home directory.
          `providers.<name>.secrets.merge` takes the same entries relative to
          that client's own root instead, and is the preferred spelling: it
          needs no knowledge of where Gentle AI rooted the client, only what
          the client itself calls the file.
        '';
      };

      envFiles = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = literalExpression ''[ "/home/you/.config/secrets/mcp.env" ]'';
        description = ''
          Files of `NAME=value` lines, each supplying a placeholder. This is the
          shape a shell-sourced secret file already has, and the shape a sops
          template can render, so an existing one needs no rewriting.

          An unreadable file is reported and its placeholders stay unresolved.
        '';
      };

      placeholders = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = literalExpression ''{ ATLAS_TOKEN = config.sops.secrets."ai/atlas-token".path; }'';
        description = ''
          Maps a placeholder name to a file holding its value, read at
          activation. `ATLAS_TOKEN` replaces every `@ATLAS_TOKEN@` in the paths
          above. A sops-nix or agenix secret exposes exactly such a path.
        '';
      };
    };

    extraFiles = mkOption {
      type = types.attrsOf extraFileType;
      default = { };
      example = literalExpression ''
        {
          ".config/opencode/skills/house-style/SKILL.md".source = ./house-style.md;
          ".claude/agents/gentle-apply.md".text = "---\nname: gentle-apply\n---\nMy own prompt.\n";
        }
      '';
      description = ''
        Files layered onto the rendered tree, replacing whatever Gentle AI put
        at the same path. This is how you add a skill of your own or override a
        generated one without forking Gentle AI.
      '';
    };

    overrideRendered = mkOption {
      type = types.functionTo types.package;
      default = lib.id;
      defaultText = literalExpression "lib.id";
      description = ''
        Arbitrary post-processing of the rendered tree, applied after
        `extraFiles`. The derivation holds `tree/` and `manifest.json`.
      '';
    };

    document = mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
      description = "The desired-state document these options produced.";
    };

    rendered = mkOption {
      type = types.package;
      readOnly = true;
      description = "The rendered tree, after extraFiles and overrideRendered.";
    };

    piProvisionOverrides = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = ''
        `--override name=source` arguments `gentle-nix provision` needs to
        rewrite Pi's fixed install sequence back to what
        `providers.pi.packages` and the plugin channels declare, now that
        neither is in the rendered document. Keyed the same way
        `providers.pi.packages` is: by the npm package name a fixed Pi
        package installs as.
      '';
    };

    piProvisionExtra = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      description = ''
        `--extra <source>` arguments for the Pi packages `providers.pi.packages`
        declares that name none of Pi's fixed packages, in the same order
        `gentle-nix provision --print` would sort them.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != defaultGentleAiPackage || selectedRelease.providesContract;
        message = "programs.gentle-ai.release = \"${cfg.release}\" selects Gentle AI ${selectedRelease.version}, which has no `gentle-ai config` and so cannot render this configuration; use the contract channel until it lands in a release, or set programs.gentle-ai.package to a build that has it";
      }
      {
        assertion = enabledNames cfg.providers != [ ];
        message = "programs.gentle-ai.providers must enable at least one client to configure";
      }
      {
        # gentlePiRelease's and engramRelease's own `types.enum` already
        # refuses an unknown channel the moment something reads the option
        # -- but now that pluginPackagesFor (and so selectedGentlePiRelease
        # / selectedEngramRelease) is only read from gentle-nix provision's
        # own --override/--extra arguments, gated behind
        # providers.pi.provisionPackages, a Pi installation that never
        # provisions would otherwise never force that read at all. These
        # two force it unconditionally, the way embedding `packages` in the
        # document unconditionally used to.
        assertion = lib.elem cfg.gentlePiRelease (lib.attrNames gentlePiReleases);
        message = "programs.gentle-ai.gentlePiRelease = \"${cfg.gentlePiRelease}\" is not a known channel";
      }
      {
        assertion = lib.elem cfg.engramRelease (lib.attrNames engramReleases);
        message = "programs.gentle-ai.engramRelease = \"${cfg.engramRelease}\" is not a known channel";
      }
      {
        assertion = unknownSourceProviders == [ ];
        message = "programs.gentle-ai.customProviders.${lib.concatStringsSep ", " unknownSourceProviders} takes its harness from a client that is not enabled, or that has no known directory";
      }
      {
        # `providers.<name>.secrets` is resolved against `providerRoots`, so
        # a name that is not in that table -- a client Gentle AI has no
        # adapter for, or a typo -- has nothing to resolve it against.
        assertion = unknownSecretsProviders == [ ];
        message = "programs.gentle-ai.providers.${lib.concatStringsSep ", " unknownSecretsProviders}.secrets is set, but that client has no known root; use programs.gentle-ai.secrets for a home-relative path instead";
      }
      {
        # A `../` component walks the joined path back past the home
        # directory itself, which is not a mistake this module can silently
        # clip to the nearest path that does exist without also picking
        # which existing path was meant.
        assertion = escapedProviderSecretPaths == [ ];
        message = "programs.gentle-ai.providers.<name>.secrets declares a path that escapes the home directory: ${
          lib.concatMapStringsSep ", " (
            entry: "${entry.name}.secrets: `${entry.path}`"
          ) escapedProviderSecretPaths
        }";
      }
      {
        assertion = lib.all (entry: (entry.text == null) != (entry.source == null)) (
          lib.attrValues cfg.extraFiles
        );
        message = "each programs.gentle-ai.extraFiles entry must set exactly one of text or source";
      }
      {
        assertion = lib.all (server: (server.command == null) != (server.url == null)) (
          lib.attrValues cfg.mcpServers
          ++ lib.concatMap (provider: lib.attrValues provider.mcpServers) (lib.attrValues cfg.providers)
        );
        message = "each programs.gentle-ai.mcpServers or providers.<name>.mcpServers entry must set exactly one of command or url";
      }
      {
        # backgroundSubagents is keyed to a fixed set of clients, not to
        # enabledProviders, so declaring it for a client this installation
        # never enables would otherwise render nothing and say nothing.
        assertion = lib.all (name: cfg.backgroundSubagents.${name} == null || enabledProviders ? ${name}) [
          "opencode"
          "pi"
        ];
        message = "programs.gentle-ai.backgroundSubagents declares an intent for a client this installation does not enable; enable programs.gentle-ai.providers.<name> or drop the intent";
      }
      {
        # gentle-pi and gentle-engram are the two entries gentlePiRelease and
        # engramRelease already manage; accepting them here too would let a
        # channel choice and a hand-written source silently disagree about
        # which one Pi actually installs.
        assertion =
          !(lib.any (
            name:
            lib.elem name [
              "gentle-pi"
              "gentle-engram"
            ]
          ) (lib.attrNames (cfg.providers.pi.packages or { })));
        message = "programs.gentle-ai.providers.pi.packages must not name gentle-pi or gentle-engram; use programs.gentle-ai.gentlePiRelease and programs.gentle-ai.engramRelease to choose where those come from";
      }
      {
        # Pi is what reads this; a provider other than pi setting it is a
        # mistake worth naming at eval rather than a `packages` block the
        # document carries for a client that will never look at it.
        assertion = nonPiProvidersWithPackages == [ ];
        message = "programs.gentle-ai.providers.${lib.concatStringsSep ", " nonPiProvidersWithPackages}.packages is refused: only providers.pi reads packages";
      }
      {
        assertion = piPackagesWithInvalidSources == [ ];
        message = "programs.gentle-ai.providers.pi.packages.${lib.concatStringsSep ", " piPackagesWithInvalidSources} uses an unsupported Pi package source: use npm:<name>[@version], git:<host>/<user>/<repo>[@ref], an https:// or ssh:// URL, or an absolute path";
      }
      {
        # Mirrors the pinned fork's own `config.role.unsupported-adapter`
        # refusal at eval time, the same way this flake already mirrors
        # other Gentle AI refusals as assertions: a declared role is only
        # rendered by `internal/roles`, which knows how to write one for
        # claude-code, cursor, kimi, kiro-ide and opencode and nothing
        # else, so an installation naming a role alongside any other
        # client would otherwise fail silently -- `gentle-nix roles` also
        # refuses this itself as a second layer (see internal/roles'
        # Validate), but naming it here catches the mistake before a build
        # even reaches that command.
        assertion = cfg.roles == { } || rolesUnsupportedAdapters == [ ];
        message = "programs.gentle-ai.roles declares roles, but programs.gentle-ai.providers.${lib.concatStringsSep ", " rolesUnsupportedAdapters} expresses no agent roles; remove the roles or drop that client";
      }
      {
        # Mirrors the pinned fork's own MCP adapters: only claude-code,
        # cursor, kimi, kiro-ide, pi, gemini-cli, qwen-code, openclaw,
        # opencode, kilocode and codex can express a declared MCP server at
        # all. hermes and the OS-variant IDE clients (windsurf, trae-ide,
        # vscode-copilot, antigravity) would otherwise silently drop a
        # declared server -- `gentle-nix mcp` also refuses this itself as a
        # second layer (see internal/mcp's Validate), but naming it here
        # catches the mistake before a build even reaches that command.
        assertion = !mcpNeeded || mcpUnsupportedAdapters == [ ];
        message = "programs.gentle-ai.mcpServers or a providers.<name>.mcpServers declares MCP servers, but programs.gentle-ai.providers.${lib.concatStringsSep ", " mcpUnsupportedAdapters} expresses no MCP servers; remove the servers or drop that client";
      }
    ];

    programs.gentle-ai = {
      inherit document rendered;
      inherit piProvisionOverrides piProvisionExtra;
    };

    home.packages = packages;

    # The rendered tree is laid out relative to the home directory, so it is
    # projected onto the home directory as a whole. Linking it recursively keeps
    # every file its own symlink, which leaves unrelated files in the same
    # directories alone and lets Home Manager report a genuine collision instead
    # of one module silently shadowing another's directory.
    home.file = {
      gentle-ai = {
        source = "${projected}/tree";
        target = ".";
        recursive = true;
      };
    }
    // lib.listToAttrs (
      lib.imap0 (index: entry: {
        name = "gentle-ai-custom-${toString index}";
        value = {
          inherit (entry) source target;
          recursive = true;
        };
      }) linkedTargets
    );

    # Gentle AI reads its own state to answer for the installation, and that
    # state is written only by its install and sync commands. Rendering the tree
    # here leaves doctor reporting an installation that is plainly present as
    # absent, and recommending it be installed again. Adopting records the
    # document without claiming a single file.
    home.activation.gentleAiAdopt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe cfg.package} config adopt \
        --config ${documentFile} \
        --home ${lib.escapeShellArg config.home.homeDirectory} >/dev/null
    '';

    home.activation.gentleAiMergedSecrets = lib.mkIf (allMergeTargets != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStringsSep "\n" (entry: ''
          run ${lib.getExe merger} \
            --fragment ${lib.escapeShellArg "${rendered}/tree/${entry.path}"} \
            --target ${lib.escapeShellArg "${config.home.homeDirectory}/${entry.path}"} \
            ${
              lib.concatMapStringsSep " " (name: "--union-list ${lib.escapeShellArg name}") entry.unionLists
            } \
            ${secretArguments}
        '') allMergeTargets
      )
    );

    home.activation.gentleAiSecrets = lib.mkIf (allSecretPaths != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStringsSep "\n" (path: ''
          run ${lib.getExe merger} --replace \
            --fragment ${lib.escapeShellArg "${rendered}/tree/${path}"} \
            --target ${lib.escapeShellArg "${config.home.homeDirectory}/${path}"} \
            ${secretArguments}
        '') allSecretPaths
      )
    );

    # Copied rather than linked, for the clients that refuse to read through a
    # symbolic link. The copy is authoritative: each target is replaced on every
    # activation, so an edit under it does not survive.
    home.activation.gentleAiCustomProviders = lib.mkIf (copiedTargets != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStringsSep "\n" (entry: ''
          run rm -rf ${lib.escapeShellArg "${config.home.homeDirectory}/${entry.target}"}
          run mkdir -p "$(dirname ${lib.escapeShellArg "${config.home.homeDirectory}/${entry.target}"})"
          run cp -rL --no-preserve=mode,ownership ${lib.escapeShellArg entry.source} ${lib.escapeShellArg "${config.home.homeDirectory}/${entry.target}"}
          run chmod -R u+w ${lib.escapeShellArg "${config.home.homeDirectory}/${entry.target}"}
        '') copiedTargets
      )
    );

    # After Pi has installed whatever this generation's channels want, it is
    # asked to drop what they displaced -- running after, rather than before,
    # provisioning is necessary but not sufficient on its own: provisioning
    # degrades a failed install to a logged line and exit 0, so this step
    # still runs even when the replacement never arrived. Each rule's own
    # `wanted` spelling is what actually prevents that from costing the
    # harness: the retirer checks it is already present in Pi's freshly read
    # packages before retiring anything for that rule, so a replacement that
    # failed to install leaves the previous, working entry in place instead
    # of removing it into nothing.
    home.activation.gentleAiRetireDisplacedPiPackages = lib.mkIf piProvisionsPackages (
      lib.hm.dag.entryAfter [ "writeBoundary" "gentleAiProvisionPackages" ] ''
        PATH=${lib.escapeShellArg "${config.home.profileDirectory}/bin"}:"$PATH" \
          run ${lib.getExe retirer} \
            --settings ${lib.escapeShellArg piSettingsPath} \
            --declared ${lib.escapeShellArg "${declaredPiPackagesFile}"} \
            --declared-record ${lib.escapeShellArg declaredPiPackagesRecordPath} \
            ${lib.concatMapStringsSep " " (
              rule: "--displaced ${lib.escapeShellArg (builtins.toJSON rule)}"
            ) displacedPiRules}
      ''
    );

    # Last, because it is the only step that reaches a network: everything a
    # switch can produce on its own is already in place when it runs, so a
    # registry being down costs the packages rather than the whole activation.
    # Last, because it is the only step that reaches outside the store:
    # everything a switch can produce on its own is already in place when it
    # runs, so a registry being down costs the packages rather than the whole
    # activation.
    home.activation.gentleAiProvisionPackages =
      lib.mkIf (provisioningProviders != [ ] || provisioningTools != [ ])
        (
          lib.hm.dag.entryAfter [ "writeBoundary" ] (
            lib.concatStringsSep "\n" (
              # Home Manager activates with a PATH of its own build tools, which
              # is not where the client lives. Without its own profile on PATH
              # the step finds nothing and skips every time, so the harness
              # silently never arrives.
              map (name: ''
                PATH=${lib.escapeShellArg "${config.home.profileDirectory}/bin"}:"$PATH" \
                  ${provisionEnvironmentFor name} \
                  run ${lib.getExe provisioner} \
                    --manifest ${lib.escapeShellArg "${rendered}/manifest.json"} \
                    --agent ${lib.escapeShellArg name} \
                    --stamp-dir ${lib.escapeShellArg "${config.xdg.stateHome}/gentle-ai-nix"} ${
                      lib.optionalString cfg.providers.${name}.provisionRefresh "--force"
                    } ${
                      # Only Pi ever has overrides/extras: piCombinedPackages
                      # is empty for every other provider, so this is a no-op
                      # everywhere else.
                      lib.optionalString (name == "pi") (
                        lib.concatMapStringsSep " " (
                          packageName:
                          "--override ${lib.escapeShellArg "${packageName}=${piProvisionOverrides.${packageName}}"}"
                        ) (lib.attrNames piProvisionOverrides)
                        + lib.optionalString (piProvisionExtra != [ ]) " "
                        + lib.concatMapStringsSep " " (source: "--extra ${lib.escapeShellArg source}") piProvisionExtra
                      )
                    }
              '') provisioningProviders
              ++ map (name: ''
                PATH=${lib.escapeShellArg "${config.home.profileDirectory}/bin"}:"$PATH" \
                  run ${lib.getExe provisioner} \
                    --manifest ${lib.escapeShellArg "${rendered}/manifest.json"} \
                    --tool ${lib.escapeShellArg name} \
                    --stamp-dir ${lib.escapeShellArg "${config.xdg.stateHome}/gentle-ai-nix"}
              '') provisioningTools
            )
          )
        );
  };
}
