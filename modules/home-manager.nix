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
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    types
    ;

  cfg = config.programs.gentle-ai;

  defaultGentleAiPackage = pkgs.callPackage ../packages/gentle-ai.nix { };
  defaultEngramPackage = pkgs.callPackage ../packages/engram.nix { };

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
          '';
        };

        settings = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          example = literalExpression ''{ share = "disabled"; }'';
          description = ''
            Provider-specific configuration the neutral contract does not model.
            It is merged verbatim into this provider's settings and no other's.
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

        models = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          example = literalExpression ''{ sdd-apply = "opus"; }'';
          description = ''
            Model assignments in this provider's own vocabulary, keyed by phase.
            Providers express models differently — an alias, a reasoning effort,
            a provider/model pair — so values are passed through as written.
          '';
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
      enable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Whether the client should start this server.";
      };
    };
  };

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
        mode = mkOption {
          type = types.enum [
            "replace"
            "append"
          ];
          default = "replace";
          description = ''
            Whether this content replaces what Gentle AI rendered at the path or
            is appended after it. Appending is how a section of your own
            survives in a file Gentle AI regenerates.
          '';
        };
      };
    }
  );

  enabledProviders = lib.filterAttrs (_: provider: provider.enable) cfg.providers;

  providerSkills = lib.filterAttrs (_: value: value != null) (
    lib.mapAttrs (_: provider: provider.skills) enabledProviders
  );

  providerSettings = lib.filterAttrs (_: value: value != { }) (
    lib.mapAttrs (_: provider: provider.settings) enabledProviders
  );

  providerPresets = lib.filterAttrs (_: value: value != null) (
    lib.mapAttrs (_: provider: provider.modelPreset) enabledProviders
  );

  # Providers express model assignments in their own vocabulary, so the contract
  # keeps one field per shape rather than one field pretending they are alike.
  # This table is the whole of the provider knowledge in this module, and it is
  # contract knowledge — versioned and documented — not asset knowledge.
  providerModelField = {
    "opencode" = "modelAssignments";
    "claude-code" = "claudeModelAssignments";
    "kiro-ide" = "kiroModelAssignments";
    "codex" = "codexModelAssignments";
  };

  providerModels = lib.foldlAttrs (
    acc: name: provider:
    let
      field = providerModelField.${name} or null;
    in
    if provider.models == { } || field == null then
      acc
    else
      acc
      // {
        ${field} =
          (acc.${field} or { })
          // (
            if field == "modelAssignments" then
              lib.mapAttrs (_: toModelAssignment) provider.models
            else
              provider.models
          );
      }
  ) { } enabledProviders;

  unmodelledProviders = lib.attrNames (
    lib.filterAttrs (
      name: provider: provider.models != { } && !(providerModelField ? ${name})
    ) enabledProviders
  );

  role =
    id: value:
    {
      inherit id;
    }
    // whenSet "renderedName" value.renderedName
    // whenSet "references" value.references
    // whenSet "description" value.description
    // whenSet "prompt" value.prompt
    // whenSet "tools" value.tools
    // whenSet "mode" value.mode
    // optionalAttrs (value.model != null) { model = toModelAssignment value.model; }
    // optionalAttrs (value.hidden != null) { inherit (value) hidden; };

  mcpServer =
    value:
    whenSet "command" value.command
    // whenSet "args" value.args
    // whenSet "env" value.env
    // whenSet "url" value.url
    // optionalAttrs (value.enable != null) { enabled = value.enable; };

  selection =
    whenSet "agents" (enabledNames cfg.providers)
    // whenSet "components" (enabledNames cfg.components)
    // whenSet "skills" (enabledNames cfg.skills)
    // whenSet "skillExclusions" (disabledNames cfg.skills)
    // whenSet "skillAssignments" providerSkills
    // whenSet "communityTools" (enabledNames cfg.communityTools)
    // whenSet "openCodePlugins" (enabledNames cfg.openCodePlugins)
    // whenSet "persona" cfg.persona
    // whenSet "preset" cfg.preset
    // whenSet "sddMode" cfg.sdd.mode
    // whenSet "sddProfileStrategy" cfg.sdd.profileStrategy
    // optionalAttrs cfg.sdd.strictTdd { strictTDD = true; }
    // whenSet "profiles" cfg.sdd.profiles
    // whenSet "scope" cfg.install.scope
    // whenSet "channel" cfg.install.channel
    // whenSet "rddMode" cfg.review.mode
    // whenSet "backgroundIntent" cfg.backgroundSubagents.opencode
    // whenSet "piBackgroundIntent" cfg.backgroundSubagents.pi
    // providerModels
    // whenSet "claudePhaseAssignments" cfg.models.claudePhases
    // whenSet "codexCarrilModelAssignments" cfg.models.codexCarril
    // whenSet "codexPhaseModelAssignments" cfg.models.codexPhases
    // whenSet "codexOrchestrator" cfg.models.codexOrchestrator
    // whenSet "modelPresets" providerPresets
    // whenSet "permissions" (
      whenSet "allow" cfg.permissions.allow
      // whenSet "deny" cfg.permissions.deny
      // whenSet "ask" cfg.permissions.ask
    )
    // whenSet "mcpServers" (lib.mapAttrs (_: mcpServer) cfg.mcpServers)
    // cfg.settings;

  document = {
    version = cfg.schemaVersion;
    inherit selection;
  }
  // whenSet "roles" (lib.mapAttrsToList role cfg.roles)
  // whenSet "extensions" (providerSettings // cfg.extensions);

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
  overlaid =
    if cfg.extraFiles == { } then
      base
    else
      pkgs.runCommandLocal "gentle-ai-config-overlaid" { } ''
        cp -r --no-preserve=mode,ownership ${base} "$out"
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

  engramEnabled = cfg.components ? engram && cfg.components.engram.enable;

  packages = builtins.filter (package: package != null) (
    [ cfg.package ] ++ lib.optional engramEnabled cfg.engramPackage
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
      '';
    };

    communityTools = enableGroup "community tool";
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
      profileStrategy = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "How SDD profiles are derived.";
      };
      strictTdd = mkOption {
        type = types.bool;
        default = false;
        description = "Whether SDD phases enforce strict TDD.";
      };
      profiles = mkOption {
        type = types.listOf (types.attrsOf types.anything);
        default = [ ];
        example = literalExpression ''
          [
            {
              name = "fast";
              orchestrator = {
                provider = "anthropic";
                model = "claude-sonnet-5";
              };
            }
          ]
        '';
        description = "Named SDD profiles with their own orchestrator and phase models.";
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

    backgroundSubagents = {
      opencode = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "OpenCode background subagent policy.";
      };
      pi = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Pi background subagent policy.";
      };
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

    extensions = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        Provider-specific configuration keyed by provider, for a provider not
        declared through `providers`. Prefer `providers.<name>.settings`.
      '';
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
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = enabledNames cfg.providers != [ ];
        message = "programs.gentle-ai.providers must enable at least one client to configure";
      }
      {
        assertion = unmodelledProviders == [ ];
        message = "programs.gentle-ai.providers.${lib.concatStringsSep ", " unmodelledProviders}.models is set, but the contract models no assignments for that provider; move them under programs.gentle-ai.settings if a newer contract added them";
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
        );
        message = "each programs.gentle-ai.mcpServers entry must set exactly one of command or url";
      }
    ];

    programs.gentle-ai = { inherit document rendered; };

    home.packages = packages;

    # The rendered tree is laid out relative to the home directory, so it is
    # projected onto the home directory as a whole. Linking it recursively keeps
    # every file its own symlink, which leaves unrelated files in the same
    # directories alone and lets Home Manager report a genuine collision instead
    # of one module silently shadowing another's directory.
    home.file.gentle-ai = {
      source = "${rendered}/tree";
      target = ".";
      recursive = true;
    };
  };
}
