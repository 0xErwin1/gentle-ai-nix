{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.programs.gentle-ai;

  defaultGentleAiPackage = pkgs.callPackage ../packages/gentle-ai.nix { };
  defaultEngramPackage = pkgs.callPackage ../packages/engram.nix { };

  fragmentType = types.submodule (
    { ... }: {
      options = {
        id = mkOption {
          type = types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
          description = "Stable fragment identifier used for duplicate detection.";
        };

        order = mkOption {
          type = types.int;
          default = 500;
          description = "Ascending composition order. IDs break order ties deterministically.";
        };

        text = mkOption {
          type = types.nullOr types.lines;
          default = null;
          description = "Inline fragment content. Set exactly one of text or source.";
        };

        source = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Fragment source path. Set exactly one of source or text.";
        };
      };
    }
  );

  packageSource = package: if package != null && package ? src then package.src else null;
  gentleSource = if cfg.source != null then cfg.source else packageSource cfg.package;
  engramSource =
    if cfg.engram.source != null then cfg.engram.source else packageSource cfg.engram.package;
  renderGentleSource = if gentleSource != null then gentleSource else defaultGentleAiPackage.src;
  renderEngramSource = if engramSource != null then engramSource else defaultEngramPackage.src;

  harness = import ../lib/harness.nix {
    gentleSource = renderGentleSource;
    engramSource = renderEngramSource;
    inherit lib pkgs;
  };

  managedFragments =
    lib.optional cfg.opencode.context.enablePersona {
      id = "gentle-ai-persona";
      order = 100;
      text = harness.context.persona;
      source = null;
    }
    ++ lib.optional cfg.engram.enable {
      id = "gentle-ai-engram";
      order = 200;
      text = harness.context.engram;
      source = null;
    };

  allFragments = managedFragments ++ cfg.opencode.context.fragments;
  fragmentIds = map (fragment: fragment.id) allFragments;
  uniqueFragmentIds = lib.unique fragmentIds;
  invalidFragments = builtins.filter (
    fragment: (fragment.text == null) == (fragment.source == null)
  ) allFragments;
  sortedFragments = lib.sort (
    left: right: left.order < right.order || (left.order == right.order && left.id < right.id)
  ) allFragments;
  renderFragment =
    fragment:
    lib.trim (
      if fragment.source != null then
        builtins.readFile fragment.source
      else if fragment.text != null then
        fragment.text
      else
        ""
    );
  renderedContext = lib.concatStringsSep "\n\n" (map renderFragment sortedFragments) + "\n";

  managedAgents = lib.mapAttrs (_: mkDefault) harness.agents;
  managedCommands = lib.mapAttrs (_: mkDefault) harness.commands;
  managedSkills = lib.mapAttrs (_: mkDefault) harness.skills;

  gentlePlugins = lib.removeAttrs harness.plugins [ "engram.ts" ];
  enabledPlugins =
    gentlePlugins
    // lib.optionalAttrs cfg.engram.enable {
      "engram.ts" = harness.plugins."engram.ts";
    };

  packageList = builtins.filter (package: package != null) (
    [ cfg.package ] ++ lib.optional cfg.engram.enable cfg.engram.package
  );
in
{
  options.programs.gentle-ai = {
    enable = mkEnableOption "Gentle AI for OpenCode";

    package = mkOption {
      type = types.nullOr types.package;
      default = defaultGentleAiPackage;
      defaultText = lib.literalExpression "gentle-ai-nix.packages.${pkgs.system}.gentle-ai";
      description = "Gentle AI package to install, or null to skip installation.";
    };

    source = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Gentle AI source used for harness assets. Null derives it from package.src.";
    };

    sourceVersion = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Version of an explicit Gentle AI source override. Required when source is set.";
    };

    opencode = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable OpenCode and project the Gentle AI harness.";
      };

      package = mkOption {
        type = types.nullOr types.package;
        default = pkgs.opencode;
        defaultText = lib.literalExpression "pkgs.opencode";
        description = "OpenCode package passed to programs.opencode.package, or null.";
      };

      context = {
        enablePersona = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to include the public Gentle AI persona fragment.";
        };

        fragments = mkOption {
          type = types.listOf fragmentType;
          default = [ ];
          description = "Ordered user-owned fragments appended to the managed OpenCode context.";
        };
      };
    };

    engram = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to install Engram and enable its OpenCode MCP and plugin integration.";
      };

      package = mkOption {
        type = types.nullOr types.package;
        default = defaultEngramPackage;
        defaultText = lib.literalExpression "gentle-ai-nix.packages.${pkgs.system}.engram";
        description = "Engram package to install, or null to skip installation.";
      };

      source = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Engram source used for the OpenCode plugin. Null derives it from package.src.";
      };

      sourceVersion = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Version of an explicit Engram source override. Required when source is set.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.length fragmentIds == builtins.length uniqueFragmentIds;
        message = "programs.gentle-ai.opencode.context.fragments contains duplicate or reserved fragment IDs";
      }
      {
        assertion = invalidFragments == [ ];
        message = "each Gentle AI OpenCode context fragment must set exactly one of text or source";
      }
      {
        assertion = !cfg.opencode.enable || gentleSource != null;
        message = "programs.gentle-ai requires package.src or an explicit source when OpenCode integration is enabled";
      }
      {
        assertion = cfg.source == null || cfg.sourceVersion != null;
        message = "programs.gentle-ai.sourceVersion is required when programs.gentle-ai.source is set";
      }
      {
        assertion =
          cfg.source == null || cfg.package == null || cfg.sourceVersion == lib.getVersion cfg.package;
        message = "programs.gentle-ai.sourceVersion must match programs.gentle-ai.package version";
      }
      {
        assertion = !cfg.opencode.enable || !cfg.engram.enable || engramSource != null;
        message = "programs.gentle-ai.engram requires package.src or an explicit source when integration is enabled";
      }
      {
        assertion = cfg.engram.source == null || cfg.engram.sourceVersion != null;
        message = "programs.gentle-ai.engram.sourceVersion is required when programs.gentle-ai.engram.source is set";
      }
      {
        assertion =
          cfg.engram.source == null
          || cfg.engram.package == null
          || cfg.engram.sourceVersion == lib.getVersion cfg.engram.package;
        message = "programs.gentle-ai.engram.sourceVersion must match programs.gentle-ai.engram.package version";
      }
    ];

    home.packages = packageList;

    programs.opencode = mkIf cfg.opencode.enable {
      enable = mkDefault true;
      package = mkDefault cfg.opencode.package;
      context = renderedContext;

      settings = {
        share = mkDefault "disabled";
        agent = managedAgents;
      }
      // lib.optionalAttrs cfg.engram.enable {
        mcp.engram = mkDefault {
          type = "local";
          command = [
            "engram"
            "mcp"
            "--tools=agent"
          ];
          enabled = true;
        };
      };

      commands = managedCommands;
      skills = managedSkills;
    };

    xdg.configFile = mkIf cfg.opencode.enable (
      lib.mapAttrs' (
        name: source: lib.nameValuePair "opencode/plugins/${name}" { inherit source; }
      ) enabledPlugins
      // lib.mapAttrs' (
        name: source: lib.nameValuePair "opencode/prompts/sdd/${name}.md" { inherit source; }
      ) harness.phasePrompts
    );
  };
}
