{
  home-manager,
  pkgs,
  self,
  system,
}:

let
  lib = pkgs.lib;
  module = self.homeManagerModules.default;

  evaluate =
    extraModules:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        module
        {
          home.username = "test-user";
          home.homeDirectory = "/home/test-user";
          home.stateVersion = "26.05";
        }
      ]
      ++ extraModules;
    };

  accepted = modules: (builtins.tryEval (evaluate modules).activationPackage.drvPath).success;
  rejected = modules: !(accepted modules);

  minimal = {
    programs.gentle-ai = {
      enable = true;
      providers.opencode.enable = true;
    };
  };

  configured = evaluate [
    {
      programs.gentle-ai = {
        enable = true;

        providers = {
          opencode.enable = true;
          claude-code.enable = true;
        };

        components = {
          skills.enable = true;
          persona.enable = true;
          sdd.enable = true;
        };

        persona = "neutral";
        sdd.mode = "single";

        roles = {
          orchestrator = {
            renderedName = "check-orchestrator";
            mode = "primary";
            references = [ "apply" ];
            description = "Coordinates";
            prompt = "You coordinate.";
          };
          apply = {
            renderedName = "check-apply";
            mode = "subagent";
          };
        };

        extraFiles = {
          ".config/opencode/skills/check-own/SKILL.md".text = "OWN-SKILL";
          ".claude/agents/check-apply.md".text = "OVERRIDDEN";
        };
      };
    }
  ];

  rendered = configured.config.programs.gentle-ai.rendered;

  # Reading the rendered tree is what proves the flake asks Gentle AI for the
  # answer instead of reconstructing it. These assertions name only what the
  # document declared, never a path this flake decided on its own.
  treeCheck =
    name: script:
    pkgs.runCommandLocal "gentle-ai-check-${name}" { inherit rendered; } ''
      set -euo pipefail
      ${script}
      touch "$out"
    '';
in
{
  # Home Manager must accept the module and project the rendered tree without
  # colliding with anything else it links.
  moduleEvaluates = treeCheck "module-evaluates" ''
    test -n "${(evaluate [ minimal ]).activationPackage}"
  '';

  # A document naming no client configures nothing, which is a mistake worth a
  # message rather than an empty successful activation. The accepted case is
  # asserted alongside it, because a check that only ever sees rejection would
  # also pass if nothing evaluated at all.
  noAgentsRejected = treeCheck "no-agents-rejected" ''
    ${lib.optionalString (!(rejected [ { programs.gentle-ai.enable = true; } ])) ''
      echo "a document naming no client was accepted" >&2
      exit 1
    ''}
    ${lib.optionalString (!(accepted [ minimal ])) ''
      echo "a document naming a client was rejected" >&2
      exit 1
    ''}
  '';

  # Layering is what makes the harness editable: an entry must be able to add a
  # file Gentle AI does not ship and to replace one it does.
  ownContentLayersOverTheRender = treeCheck "extra-files" ''
    grep -q "OWN-SKILL" "$rendered/tree/.config/opencode/skills/check-own/SKILL.md"
    grep -q "OVERRIDDEN" "$rendered/tree/.claude/agents/check-apply.md"
  '';

  # A role the document declared must reach every client that expresses roles,
  # under the name the document rendered it as.
  declaredRoleReachesEveryAdapter = treeCheck "declared-role" ''
    test -f "$rendered/tree/.claude/agents/check-orchestrator.md"
    grep -q "check-apply" "$rendered/tree/.claude/agents/check-orchestrator.md"
    grep -q "check-orchestrator" "$rendered/tree/.config/opencode/opencode.json"
    grep -q "check-apply" "$rendered/tree/.config/opencode/opencode.json"
  '';

  # Rendered content records absolute paths to its own files. They have to name
  # the home directory the configuration is built for, never the build sandbox.
  contentNamesTheHomeDirectory = treeCheck "no-sandbox-paths" ''
    if grep -rl "$rendered" "$rendered/tree" >/dev/null 2>&1; then
      echo "rendered content names its own store path" >&2
      exit 1
    fi
  '';

  # The report Gentle AI produced is kept beside the tree so a consumer can see
  # what was rendered without re-running the renderer.
  manifestAccompaniesTheTree = treeCheck "manifest" ''
    test -s "$rendered/manifest.json"
    grep -q '"resources"' "$rendered/manifest.json"
  '';

  formatting = pkgs.runCommandLocal "gentle-ai-check-formatting" { } ''
    ${lib.getExe pkgs.nixfmt-tree} --check ${self} 2>&1 | tee "$out" || {
      echo "run 'nix fmt' to format the flake" >&2
      exit 1
    }
  '';
}
