{ gentle-ai-nix, pkgs, ... }:

{
  imports = [ gentle-ai-nix.homeManagerModules.default ];

  programs.gentle-ai = {
    enable = true;

    opencode.context.fragments = [
      {
        id = "local-policy";
        order = 300;
        source = ./AGENTS.local.md;
      }
    ];
  };

  programs.opencode = {
    settings.model = "anthropic/claude-sonnet-4-6";
    tui.theme = "system";
    extraPackages = [ pkgs.ripgrep ];
  };
}
