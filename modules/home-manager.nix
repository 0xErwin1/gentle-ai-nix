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

  releases = import ../packages/versions.nix;

  selectedRelease = releases.${cfg.release};

  defaultGentleAiPackage = pkgs.callPackage ../packages/gentle-ai.nix {
    release = selectedRelease;
  };
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
            Named SDD profiles for this client, switchable at runtime. Each one
            generates its own orchestrator and phase agents alongside the
            default set, so a task can run on cheap models without reconfiguring
            anything.

            Only OpenCode expresses these today.
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

            Only OpenCode expresses this today.
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

  providerSkills = lib.filterAttrs (_: value: value != null) (
    lib.mapAttrs (_: provider: provider.skills) enabledProviders
  );

  providerSettings = lib.filterAttrs (_: value: value != { }) (
    lib.mapAttrs (_: provider: provider.settings) enabledProviders
  );

  providerServers = lib.filterAttrs (_: value: value != { }) (
    lib.mapAttrs (_: provider: lib.mapAttrs (_: mcpServer) provider.mcpServers) enabledProviders
  );

  providerPresets = lib.filterAttrs (_: value: value != null) (
    lib.mapAttrs (_: provider: provider.modelPreset) enabledProviders
  );

  profile =
    name: value:
    {
      inherit name;
    }
    // optionalAttrs (value.orchestrator != null) {
      orchestrator = toModelAssignment value.orchestrator;
    }
    // whenSet "phaseAssignments" (lib.mapAttrs (_: toModelAssignment) value.phases);

  # Profiles and their strategy are one client's concept, so they are collected
  # from the clients that declared them rather than from an installation-wide
  # option that could only ever mean one of them.
  declaredProfiles = lib.concatLists (
    lib.mapAttrsToList (_: provider: lib.mapAttrsToList profile provider.profiles) enabledProviders
  );

  declaredProfileStrategy = lib.findFirst (value: value != null) null (
    lib.mapAttrsToList (_: provider: provider.profileStrategy) enabledProviders
  );

  # Only one client expresses profiles today, so anything else declaring them is
  # a mistake worth naming rather than configuration that quietly does nothing.
  profileCapable = [ "opencode" ];

  misplacedProfiles = lib.attrNames (
    lib.filterAttrs (
      name: provider:
      (provider.profiles != { } || provider.profileStrategy != null)
      && !(builtins.elem name profileCapable)
    ) enabledProviders
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
    "pi" = "piModelAssignments";
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
    // whenSet "headers" value.headers
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
    // whenSet "sddProfileStrategy" declaredProfileStrategy
    // optionalAttrs cfg.sdd.strictTdd { strictTDD = true; }
    // whenSet "profiles" declaredProfiles
    // whenSet "scope" cfg.install.scope
    // whenSet "channel" cfg.install.channel
    // whenSet "rddMode" cfg.review.mode
    // whenSet "backgroundIntent" cfg.backgroundSubagents.opencode
    // whenSet "piBackgroundIntent" cfg.backgroundSubagents.pi
    // providerModels
    // providerModelFamilies
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
    // whenSet "mcpServerAssignments" providerServers
    // cfg.settings;

  document = {
    version = cfg.schemaVersion;
    inherit selection;
  }
  // whenSet "roles" (lib.mapAttrsToList role cfg.roles)
  // whenSet "extensions" (providerSettings // cfg.extensions);

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
  withheld = cfg.secrets.paths ++ map (entry: entry.path) mergeTargets;

  provisioner = pkgs.writers.writePython3Bin "gentle-ai-provision" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../lib/provision.py);

  # Which clients were asked to have their package harness installed. The
  # commands themselves are read from the rendered manifest at activation, so
  # this module never holds a copy of a package list that could go stale.
  provisioningProviders = lib.attrNames (
    lib.filterAttrs (_: provider: provider.provisionPackages) enabledProviders
  );

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

  secretArguments =
    lib.concatMapStringsSep " " (path: "--env-file ${lib.escapeShellArg path}") cfg.secrets.envFiles
    + " "
    + lib.concatMapStringsSep " " (
      name: "--secret ${lib.escapeShellArg "${name}=${cfg.secrets.placeholders.${name}}"}"
    ) (lib.attrNames cfg.secrets.placeholders);

  projected =
    if withheld == [ ] then
      rendered
    else
      pkgs.runCommandLocal "gentle-ai-config-projected" { } ''
        cp -r --no-preserve=mode,ownership ${rendered} "$out"
        ${lib.concatMapStringsSep "\n" (path: ''rm -f "$out/tree/${path}"'') withheld}
      '';

  # Which contract field carries a borrowed model profile. Only one client has
  # no catalogue of its own today, and one that is absent here is reported
  # rather than accepted and ignored.
  providerModelFamilyField = {
    "pi" = "piModelFamily";
  };

  providerModelFamilies = lib.foldlAttrs (
    acc: name: provider:
    let
      field = providerModelFamilyField.${name} or null;
    in
    if provider.modelFamily == null || field == null then
      acc
    else
      acc // { ${field} = provider.modelFamily; }
  ) { } enabledProviders;

  unborrowableProviders = lib.attrNames (
    lib.filterAttrs (
      name: provider: provider.modelFamily != null && !(providerModelFamilyField ? ${name})
    ) enabledProviders
  );

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

  # A client Gentle AI has no adapter for still reads the same kind of harness,
  # so it is given one another client already produced rather than a hand-written
  # mapping that drifts the moment Gentle AI changes what it renders.
  customProviderCopies = lib.concatLists (
    lib.mapAttrsToList (
      name: provider:
      let
        source = "${rendered}/tree/${providerRoots.${provider.from}}";
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
      in
      map (pair: {
        inherit (provider) delivery;
        source = "${source}/${pair.from}";
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

        `stable` and `beta` are the published ones. `contract` is the branch
        carrying the declarative configuration contract this module renders
        through, and is the default only because no release has that contract
        yet: choosing a published channel builds fine and then fails when the
        renderer runs, because `gentle-ai config` does not exist there.

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
                default = null;
                example = literalExpression "pkgs.codegraph";
                description = ''
                  The tool's own binary, installed alongside the harness when
                  this tool is enabled.

                  Gentle AI would otherwise fetch it through a package manager
                  at install time. Naming it here is the same choice the engram
                  component takes: the binary comes from Nix, so nothing is
                  downloaded at activation and the version is the one this
                  configuration pins.

                  Left null, the tool is configured and the binary is your
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
        assertion = unknownSourceProviders == [ ];
        message = "programs.gentle-ai.customProviders.${lib.concatStringsSep ", " unknownSourceProviders} takes its harness from a client that is not enabled, or that has no known directory";
      }
      {
        assertion = unborrowableProviders == [ ];
        message = "programs.gentle-ai.providers.${lib.concatStringsSep ", " unborrowableProviders}.modelFamily names a client that has a model catalogue of its own; assign its models directly";
      }
      {
        assertion = misplacedProfiles == [ ];
        message = "programs.gentle-ai.providers.${lib.concatStringsSep ", " misplacedProfiles} declares profiles, which only ${lib.concatStringsSep ", " profileCapable} expresses";
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

    home.activation.gentleAiMergedSecrets = lib.mkIf (cfg.secrets.merge != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStringsSep "\n" (entry: ''
          run ${lib.getExe merger} \
            --fragment ${lib.escapeShellArg "${rendered}/tree/${entry.path}"} \
            --target ${lib.escapeShellArg "${config.home.homeDirectory}/${entry.path}"} \
            ${
              lib.concatMapStringsSep " " (name: "--union-list ${lib.escapeShellArg name}") entry.unionLists
            } \
            ${secretArguments}
        '') mergeTargets
      )
    );

    home.activation.gentleAiSecrets = lib.mkIf (cfg.secrets.paths != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStringsSep "\n" (path: ''
          run ${lib.getExe merger} --replace \
            --fragment ${lib.escapeShellArg "${rendered}/tree/${path}"} \
            --target ${lib.escapeShellArg "${config.home.homeDirectory}/${path}"} \
            ${secretArguments}
        '') cfg.secrets.paths
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
                    --stamp-dir ${lib.escapeShellArg "${config.xdg.stateHome}/gentle-ai-nix"}
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
