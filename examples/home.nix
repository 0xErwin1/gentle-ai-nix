{ gentle-ai-nix, ... }:

{
  imports = [ gentle-ai-nix.homeManagerModules.default ];

  programs.gentle-ai = {
    enable = true;

    settings = {
      agents = [
        "opencode"
        "claude-code"
      ];
      components = [
        "skills"
        "persona"
        "permissions"
        "sdd"
        "theme"
      ];
      skills = [ "comment-writer" ];
      persona = "neutral";
      sddMode = "single";

      mcpServers.engram = {
        command = "engram";
        args = [
          "mcp"
          "--tools=agent"
        ];
      };
    };

    # Roles reference each other by id, so renaming one is a single edit here
    # and every generated reference follows.
    roles = [
      {
        id = "orchestrator";
        renderedName = "my-orchestrator";
        mode = "primary";
        references = [ "apply" ];
        description = "Coordinates the change";
        prompt = "You coordinate work and delegate.";
      }
      {
        id = "apply";
        renderedName = "my-apply";
        mode = "subagent";
        description = "Implements the change";
        prompt = "You implement the assigned task.";
      }
    ];

    extensions.opencode.share = "disabled";
  };
}
