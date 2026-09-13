# Per-OS locations for the four clients whose settings/MCP file the pinned
# Gentle AI fork's own adapter resolves from runtime.GOOS rather than a
# fixed path (internal/agents/{vscode,antigravity,windsurf,trae}/adapter.go's
# own SettingsPath/MCPConfigPath), plus hermes' single YAML MCP config (not
# OS-variant, but new to gentle-nix mcp all the same, and carried here so
# gentle-nix mcp's --spec paths block, gentle-nix settings' --settings-path
# and gentle-nix skills' skillsDir all read from the one table).
#
# This is pure data -- no pkgs, no lib -- on purpose: modules/home-manager.nix
# picks the winning OS key at eval time from pkgs.stdenv.hostPlatform (it has
# no equivalent of its own to hand gentle-nix), and checks/default.nix
# asserts this table is well-formed for both OS keys without needing to
# evaluate the module for a second platform at all.
#
# Some of the paths below are the same on every OS -- carried here anyway so
# this stays one table a reader can check straight against the adapters,
# rather than half living here and half in gentle-nix's own built-in tables
# (internal/settings, internal/mcp, internal/skills), which a caller never
# has to know or care about: every path here is simply handed down as an
# override, and an override always wins.
#
# Antigravity is the one exception worth calling out: the fork's own adapter
# does not actually select its directory by OS at all -- it inspects which
# of two variant directories already exists on the real machine at run time,
# which a Nix derivation, sandboxed away from the user's home directory at
# build time, cannot do. Both OS entries below carry the same "cli" variant
# the adapter itself falls back to when neither exists yet. There is no
# user-facing option to redirect this at the time of writing; an
# installation that actually landed in the "desktop" variant has to override
# this table directly (a local module override of
# clientLocations.<os>.antigravity, or a gentle-nix settings/mcp/skills
# invocation of its own outside this module) until one is added.
{
  linux = {
    vscode-copilot = {
      settings = ".config/Code/User/settings.json";
      mcp = ".config/Code/User/mcp.json";
    };
    windsurf = {
      settings = ".config/Windsurf/User/settings.json";
      mcp = ".codeium/windsurf/mcp_config.json";
      skills = ".codeium/windsurf/skills";
    };
    trae-ide = {
      settings = ".config/Trae/User/settings.json";
      mcp = ".config/Trae/User/mcp.json";
      skills = ".trae/skills";
    };
    antigravity = {
      settings = ".gemini/antigravity-cli/settings.json";
      mcp = ".gemini/antigravity-cli/mcp_config.json";
      skills = ".gemini/antigravity-cli/skills";
    };
    hermes.mcp = ".hermes/config.yaml";
  };
  darwin = {
    vscode-copilot = {
      settings = "Library/Application Support/Code/User/settings.json";
      mcp = "Library/Application Support/Code/User/mcp.json";
    };
    windsurf = {
      settings = "Library/Application Support/Windsurf/User/settings.json";
      mcp = ".codeium/windsurf/mcp_config.json";
      skills = ".codeium/windsurf/skills";
    };
    trae-ide = {
      settings = "Library/Application Support/Trae/User/settings.json";
      mcp = "Library/Application Support/Trae/User/mcp.json";
      skills = ".trae/skills";
    };
    antigravity = {
      settings = ".gemini/antigravity-cli/settings.json";
      mcp = ".gemini/antigravity-cli/mcp_config.json";
      skills = ".gemini/antigravity-cli/skills";
    };
    hermes.mcp = ".hermes/config.yaml";
  };
}
