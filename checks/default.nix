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
          programs.gentle-ai.enable = true;
        }
      ]
      ++ extraModules;
    };

  rejected = modules: !(builtins.tryEval (evaluate modules).activationPackage.drvPath).success;

  defaults = evaluate [ ];
  composed = evaluate [
    {
      programs.gentle-ai.opencode.context.fragments = [
        {
          id = "middle";
          order = 300;
          text = "MIDDLE-FRAGMENT";
        }
        {
          id = "last";
          order = 900;
          text = "LAST-FRAGMENT";
        }
      ];
      programs.opencode.settings.model = "example/provider-model";
    }
  ];
  openCodeDisabled = evaluate [ { programs.gentle-ai.opencode.enable = false; } ];
  engramDisabled = evaluate [ { programs.gentle-ai.engram.enable = false; } ];

  duplicateRejected = rejected [
    {
      programs.gentle-ai.opencode.context.fragments = [
        {
          id = "duplicate";
          text = "first";
        }
        {
          id = "duplicate";
          text = "second";
        }
      ];
    }
  ];
  neitherSourceRejected = rejected [
    { programs.gentle-ai.opencode.context.fragments = [ { id = "empty"; } ]; }
  ];
  bothSourcesRejected = rejected [
    {
      programs.gentle-ai.opencode.context.fragments = [
        {
          id = "both";
          text = "inline";
          source = ../examples/AGENTS.local.md;
        }
      ];
    }
  ];
  sourceVersionRequired = rejected [
    { programs.gentle-ai.source = self.packages.${system}.gentle-ai.src; }
  ];
  sourceVersionMismatch = rejected [
    {
      programs.gentle-ai.source = self.packages.${system}.gentle-ai.src;
      programs.gentle-ai.sourceVersion = "0.0.0";
    }
  ];
  packageWithoutSourceRejected = rejected [
    { programs.gentle-ai.package = pkgs.writeShellScriptBin "gentle-ai" "exit 0"; }
  ];
  engramSourceVersionRequired = rejected [
    { programs.gentle-ai.engram.source = self.packages.${system}.engram.src; }
  ];
  engramSourceVersionMismatch = rejected [
    {
      programs.gentle-ai.engram.source = self.packages.${system}.engram.src;
      programs.gentle-ai.engram.sourceVersion = "0.0.0";
    }
  ];

  packageNames = map lib.getName defaults.config.home.packages;
  openCodeDisabledPackageNames = map lib.getName openCodeDisabled.config.home.packages;
  engramDisabledPackageNames = map lib.getName engramDisabled.config.home.packages;
  composedContext = composed.config.programs.opencode.context;
  afterPersona = builtins.elemAt (lib.splitString "## Rules" composedContext) 1;
  afterMiddle = builtins.elemAt (lib.splitString "MIDDLE-FRAGMENT" afterPersona) 1;
  orderedContext = lib.hasInfix "LAST-FRAGMENT" afterMiddle;
  files = defaults.config.xdg.configFile;

  evaluationAssertions = [
    (lib.assertMsg (lib.elem "gentle-ai" packageNames) "default config must install Gentle AI")
    (lib.assertMsg (lib.elem "engram" packageNames) "default config must install Engram")
    (lib.assertMsg (lib.elem "opencode" packageNames) "default config must install OpenCode")
    (lib.assertMsg defaults.config.programs.opencode.enable "default config must enable OpenCode")
    (lib.assertMsg orderedContext "AGENTS fragments must retain declared order")
    (lib.assertMsg (
      composed.config.programs.opencode.settings.model == "example/provider-model"
    ) "user OpenCode settings must merge")
    (lib.assertMsg (
      !openCodeDisabled.config.programs.opencode.enable
    ) "OpenCode disable toggle must be honored")
    (lib.assertMsg (
      !lib.elem "opencode" openCodeDisabledPackageNames
    ) "OpenCode disable toggle must remove its package")
    (lib.assertMsg engramDisabled.config.programs.opencode.enable "Engram disable toggle must not disable OpenCode")
    (lib.assertMsg (
      !lib.elem "engram" engramDisabledPackageNames
    ) "Engram disable toggle must remove its package")
    (lib.assertMsg (
      !(builtins.hasAttr "opencode/plugins/engram.ts" engramDisabled.config.xdg.configFile)
    ) "Engram disable toggle must remove its plugin")
    (lib.assertMsg duplicateRejected "duplicate fragment IDs must be rejected")
    (lib.assertMsg neitherSourceRejected "fragment with neither source must be rejected")
    (lib.assertMsg bothSourcesRejected "fragment with both sources must be rejected")
    (lib.assertMsg sourceVersionRequired "explicit Gentle AI source must require sourceVersion")
    (lib.assertMsg sourceVersionMismatch "sourceVersion must match package version")
    (lib.assertMsg packageWithoutSourceRejected "package override without src must require explicit source")
    (lib.assertMsg engramSourceVersionRequired "explicit Engram source must require sourceVersion")
    (lib.assertMsg engramSourceVersionMismatch "Engram sourceVersion must match package version")
    (lib.assertMsg (
      toString files."opencode/plugins/review-result-artifacts.ts".source == "${
        self.packages.${system}.gentle-ai.src
      }/internal/assets/opencode/plugins/review-result-artifacts.ts"
    ) "Gentle AI plugin must derive from package.src")
    (lib.assertMsg (
      toString files."opencode/plugins/engram.ts".source
      == "${self.packages.${system}.engram.src}/plugin/opencode/engram.ts"
    ) "Engram plugin must derive from package.src")
  ];

  generated = defaults.activationPackage;
in
{
  evaluation = builtins.deepSeq evaluationAssertions (
    pkgs.runCommand "gentle-ai-module-evaluation" { } ''
      touch $out
    ''
  );

  generated-harness =
    pkgs.runCommand "gentle-ai-generated-harness"
      {
        nativeBuildInputs = [
          pkgs.opencode
          pkgs.jq
        ];
      }
      ''
            config=${generated}/home-files/.config/opencode

            test -f "$config/opencode.json"
            test -f "$config/AGENTS.md"
            test -f "$config/commands/sdd-apply.md"
            test -f "$config/skills/sdd-apply/SKILL.md"
            test -f "$config/skills/_shared/review-ledger-contract.md"
            test -f "$config/prompts/sdd/sdd-apply.md"
            test -f "$config/plugins/review-result-artifacts.ts"
            test -f "$config/plugins/engram.ts"

            test "$(jq -r '.mcp.engram.command | join(" ")' "$config/opencode.json")" = "engram mcp --tools=agent"
            test "$(jq -r '.agent["sdd-apply"].prompt' "$config/opencode.json")" = "{file:./prompts/sdd/sdd-apply.md}"
            jq -e '.agent["gentle-orchestrator"].prompt | contains("#### Review Execution Contract") and contains("--agent opencode --next-transition")' "$config/opencode.json" >/dev/null
            jq -e '.agent["review-risk"].tools.read == false and .agent["review-risk"].permission.bash == "deny"' "$config/opencode.json" >/dev/null
            grep -F -- '--agent opencode --next-transition' "$config/commands/sdd-apply.md" >/dev/null
            grep -F -- '--agent opencode --next-transition' "$config/skills/_shared/review-ledger-contract.md" >/dev/null

            if grep -R -E '\{\{[A-Z0-9_]+\}\}' "$config"; then
              echo "unresolved Gentle AI template token in generated harness" >&2
              exit 1
            fi

        export HOME=$TMPDIR/home
        export XDG_CONFIG_HOME=$HOME/.config
        mkdir -p "$XDG_CONFIG_HOME"
        cp -R "$config" "$XDG_CONFIG_HOME/opencode"
            OPENCODE_DISABLE_PROJECT_CONFIG=1 \
              OPENCODE_DISABLE_DEFAULT_PLUGINS=1 \
              OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
              OPENCODE_PURE=1 \
              opencode debug config >/dev/null

            touch $out
      '';

  home-activation = generated;
  package-gentle-ai = self.packages.${system}.gentle-ai;
  package-engram = self.packages.${system}.engram;
}
