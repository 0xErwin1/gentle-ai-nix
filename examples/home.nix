{ gentle-ai-nix, pkgs, ... }:

{
  imports = [ gentle-ai-nix.homeManagerModules.default ];

  programs.gentle-ai = {
    enable = true;

    # Clients, each with whatever differs for it alone.
    providers = {
      opencode.enable = true;

      # Profiles are per client because subscriptions are: the cheap tier
      # where the quota is tight, the expensive one where it is not.
      codex = {
        enable = true;
        modelPreset = "low-cost";
      };

      claude-code = {
        enable = true;
        modelPreset = "performance";
        skills = [ "cognitive-doc-design" ];
        settings.theme = "dark";
        models.sdd-apply = "opus";
      };
    };

    # Components are what Gentle AI configures. Engram is one of them, so
    # enabling it here is what wires the MCP server, the plugin and the protocol
    # section into every client that takes them.
    components = {
      skills.enable = true;
      persona.enable = true;
      permissions.enable = true;
      sdd.enable = true;
      theme.enable = true;
      engram.enable = true;
    };

    # Naming no skill installs every one Gentle AI ships. Entries are only for
    # narrowing that: false drops one and leaves the rest.
    skills.go-testing.enable = false;

    persona = "neutral";

    sdd = {
      mode = "single";
      strictTdd = true;
    };

    permissions.deny = [ "Bash(rm -rf:*)" ];

    # Roles reference each other by attribute name, so renaming one is a single
    # edit here and every generated reference follows.
    roles = {
      orchestrator = {
        renderedName = "my-orchestrator";
        mode = "primary";
        references = [ "apply" ];
        description = "Coordinates the change";
        prompt = "You coordinate work and delegate.";
        model = {
          provider = "anthropic";
          model = "claude-opus-5";
          effort = "high";
        };
      };

      apply = {
        renderedName = "my-apply";
        mode = "subagent";
        description = "Implements the change";
      };
    };

    # Your own harness content, layered over what Gentle AI rendered. The first
    # entry adds a skill Gentle AI does not ship; the second replaces a file it
    # does, without forking anything.
    extraFiles = {
      ".config/opencode/skills/house-style/SKILL.md".source = ./house-style.md;

      ".claude/agents/my-apply.md".text = ''
        ---
        name: my-apply
        ---
        Implement the assigned task, our way.
      '';

      # A section of your own inside a file Gentle AI regenerates. Appending
      # leaves everything it wrote in place.
      "opencode-house-rules" = {
        target = ".config/opencode/AGENTS.md";
        mode = "append";
        text = ''

          ## House rules

          Ask before touching anything under infra/.
        '';
      };
    };

    # Anything the options above do not reach. Applied after extraFiles.
    overrideRendered =
      rendered:
      pkgs.runCommandLocal "gentle-ai-config-patched" { } ''
        cp -r --no-preserve=mode,ownership ${rendered} "$out"
        substituteInPlace "$out/tree/.config/opencode/AGENTS.md" \
          --replace-warn "Gentle AI" "Our harness"
      '';
  };
}
