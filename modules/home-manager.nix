# Home Manager integration for Gentle AI.
#
# This module declares what the installation should be and lets Gentle AI decide
# what that means on disk. It deliberately holds no knowledge of agents, skills,
# commands, prompts or provider file layouts: every one of those is a Gentle AI
# semantic, and a copy of it here would drift the moment Gentle AI changed.
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
    types
    ;

  cfg = config.programs.gentle-ai;

  defaultGentleAiPackage = pkgs.callPackage ../packages/gentle-ai.nix { };
  defaultEngramPackage = pkgs.callPackage ../packages/engram.nix { };

  document = {
    version = cfg.schemaVersion;
    selection = cfg.settings;
  }
  // lib.optionalAttrs (cfg.roles != [ ]) { roles = cfg.roles; }
  // lib.optionalAttrs (cfg.extensions != { }) { extensions = cfg.extensions; };

  rendered = pkgs.callPackage ../lib/render.nix { } {
    inherit document;
    inherit (config.home) homeDirectory;
    gentle-ai = cfg.package;
  };

  packages = builtins.filter (package: package != null) (
    [ cfg.package ] ++ lib.optional cfg.engram.enable cfg.engram.package
  );
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
        so the rendered result always matches the version on PATH.
      '';
    };

    schemaVersion = mkOption {
      type = types.str;
      default = "v1";
      description = ''
        Version of the Gentle AI configuration schema this document is written
        against. Gentle AI rejects a version it cannot interpret rather than
        guessing, so pinning it here makes an incompatible upgrade a build
        failure instead of a silent reinterpretation.
      '';
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = literalExpression ''
        {
          agents = [ "opencode" "claude-code" ];
          components = [ "skills" "persona" "permissions" "sdd" "theme" ];
          skills = [ "comment-writer" ];
          persona = "neutral";
          sddMode = "single";
        }
      '';
      description = ''
        The `selection` block of the Gentle AI desired-state document, passed
        through verbatim. Every field the contract accepts is available here
        without this module needing to know it exists; Gentle AI validates the
        result and rejects an unknown field rather than ignoring it.
      '';
    };

    roles = mkOption {
      type = types.listOf (types.attrsOf types.anything);
      default = [ ];
      example = literalExpression ''
        [
          {
            id = "orchestrator";
            renderedName = "gentle-orchestrator";
            references = [ "apply" ];
            mode = "primary";
          }
          { id = "apply"; renderedName = "gentle-apply"; mode = "subagent"; }
        ]
      '';
      description = ''
        Logical agent roles. References name role ids, never rendered names, so
        renaming a role is one edit and every generated reference follows.
      '';
    };

    extensions = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = literalExpression ''{ opencode = { share = "disabled"; }; }'';
      description = ''
        Provider-specific configuration the neutral contract does not model,
        keyed by adapter. Each block is merged verbatim into that adapter's
        settings and only that adapter's.
      '';
    };

    engram = {
      enable = mkEnableOption "the Engram package" // {
        default = true;
      };

      package = mkOption {
        type = types.nullOr types.package;
        default = defaultEngramPackage;
        defaultText = literalExpression "gentle-ai-nix.packages.\${pkgs.system}.engram";
        description = ''
          Engram package to install, or null to skip it. Declaring Engram as an
          MCP server in `settings` configures the clients to use it; installing
          the binary is what makes it resolvable.
        '';
      };
    };

    rendered = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        The rendered configuration tree, exposed for inspection and for tests
        that assert on what a document produces.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings ? agents && cfg.settings.agents != [ ];
        message = "programs.gentle-ai.settings.agents must name at least one client to configure";
      }
    ];

    programs.gentle-ai.rendered = rendered;

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
