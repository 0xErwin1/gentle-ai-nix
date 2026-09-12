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

          check-registered-hook = {
            target = ".claude/settings.json";
            mode = "merge";
            unionLists = [ "hooks.SessionStart" ];
            text = builtins.toJSON {
              hooks.SessionStart = [ { command = "check-registered-hook"; } ];
              checkOwnKey = "OWN-SETTING";
            };
          };
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

  # A provider outside opencode/pi declaring profiles used to be a Nix-level
  # mistake this module named itself. That knowledge now lives in the
  # renderer, which reports it as a diagnostic instead, so the same document
  # must evaluate here: whether it is accepted is the renderer's call, made
  # against the immutable trees at render time, not this module's at eval
  # time.
  misplacedProfilesNoLongerRejectedAtEval =
    pkgs.runCommandLocal "gentle-ai-check-misplaced-profiles-not-rejected-at-eval" { }
      ''
        set -euo pipefail
        ${lib.optionalString
          (
            !(accepted [
              {
                programs.gentle-ai = {
                  enable = true;
                  providers.claude-code = {
                    enable = true;
                    profiles.cheap.orchestrator = {
                      provider = "anthropic";
                      model = "claude-haiku";
                    };
                  };
                };
              }
            ])
          )
          ''
            echo "a provider declaring profiles outside opencode/pi was rejected at Nix eval" >&2
            exit 1
          ''
        }
        touch "$out"
      '';

  # The nested providers.<id> block is the wire shape the renderer now decodes,
  # and the fields it replaced must not still reach the document: a stale
  # flat field surviving here would mean two documents disagree about what the
  # contract accepts.
  providersDocumentShape =
    let
      # A shared fixture applied to every client, so a stale top-level key any
      # old emission path used to fire through is asserted absent regardless of
      # which client used to carry it, not just the one this check happens to
      # enable.
      commonFields = {
        models.orchestrator.model = "anthropic/claude-haiku";
        modelPreset = "economy";
        skills = [ "go-testing" ];
        mcpServers.atlas.command = "atlas";
      };
      shapeConfiguration = evaluate [
        {
          programs.gentle-ai = {
            enable = true;
            providers = lib.genAttrs [ "opencode" "claude-code" "kiro-ide" "codex" "pi" ] (
              name:
              {
                enable = true;
              }
              // commonFields
              // lib.optionalAttrs (name == "opencode") {
                profiles.cheap.orchestrator = {
                  provider = "anthropic";
                  model = "claude-haiku";
                };
                profileStrategy = "generated-multi";
                activeProfile = "cheap";
              }
              // lib.optionalAttrs (name == "pi") {
                modelFamily = "codex";
                profiles.cheap.orchestrator = {
                  provider = "anthropic";
                  model = "claude-haiku";
                };
                activeProfile = "cheap";
              }
            );
            backgroundSubagents = {
              opencode = "on";
              pi = "on";
            };
          };
        }
      ];
      document = shapeConfiguration.config.programs.gentle-ai.document;
      pi = document.selection.providers.pi;
      opencode = document.selection.providers.opencode;
      removedTopLevelKeys = [
        "piModelAssignments"
        "claudeModelAssignments"
        "kiroModelAssignments"
        "codexModelAssignments"
        "modelAssignments"
        "piModelFamily"
        "modelPresets"
        "skillAssignments"
        "mcpServerAssignments"
        "sddProfileStrategy"
        "backgroundIntent"
        "piBackgroundIntent"
        "profiles"
      ];
    in
    assert pi.models.orchestrator.model == "anthropic/claude-haiku";
    assert pi.profiles.cheap.orchestrator.provider == "anthropic";
    assert pi.profiles.cheap.orchestrator.model == "claude-haiku";
    assert pi.activeProfile == "cheap";
    assert pi.backgroundIntent == "on";
    assert pi.modelFamily == "codex";
    assert pi.modelPreset == "economy";
    assert pi.skills == [ "go-testing" ];
    assert pi.mcpServers.atlas.command == "atlas";
    assert opencode.profileStrategy == "generated-multi";
    assert opencode.backgroundIntent == "on";
    assert lib.all (key: !(document.selection ? ${key})) removedTopLevelKeys;
    pkgs.runCommandLocal "gentle-ai-check-providers-document-shape" { } ''touch "$out"'';

  # `gentlePiRelease` and `engramRelease` only ever add a `packages` entry
  # under Pi's provider block, and only for the channel actually chosen off
  # its default: a document naming neither must render exactly as it did
  # before either option existed, so that pairing is asserted alongside the
  # one that carries a source, the same way providersDocumentShape pairs a
  # field's presence with its absence.
  piPackagesDocumentShape =
    let
      documentFor =
        overrides:
        (evaluate [
          {
            programs.gentle-ai = {
              enable = true;
              providers.pi.enable = true;
            }
            // overrides;
          }
        ]).config.programs.gentle-ai.document;

      defaultDocument = documentFor { };
      overriddenDocument = documentFor {
        gentlePiRelease = "main";
        engramRelease = "rc";
      };
    in
    # A `pi` block with nothing else set renders no `providers` key at all
    # (providersDocumentShape's own empty-block rule), so the no-override
    # case is asserted with a path lookup rather than through a `providers.pi`
    # that may not exist.
    assert !(lib.hasAttrByPath [ "providers" "pi" "packages" ] defaultDocument.selection);
    assert lib.hasPrefix "git:github.com/Gentleman-Programming/gentle-pi@"
      overriddenDocument.selection.providers.pi.packages.gentle-pi;
    assert lib.hasPrefix "/nix/store/" overriddenDocument.selection.providers.pi.packages.gentle-engram;
    pkgs.runCommandLocal "gentle-ai-check-pi-packages-document-shape" { } ''touch "$out"'';

  # piPackagesDocumentShape only proves the document carries the right
  # sources; this proves the renderer actually substitutes them into what Pi
  # is told to run, against the real `gentle-ai config render`, the same way
  # rendererSurfacesUnsupportedProviderMistakes exercises the renderer rather
  # than reconstructing its behaviour here.
  piPackagesRenderThrough =
    let
      gentleAi = (evaluate [ minimal ]).config.programs.gentle-ai.package;

      documentFor =
        overrides:
        (evaluate [
          {
            programs.gentle-ai = {
              enable = true;
              providers.pi.enable = true;
            }
            // overrides;
          }
        ]).config.programs.gentle-ai.document;

      defaultDocument = documentFor { };
      overriddenDocument = documentFor {
        gentlePiRelease = "main";
        engramRelease = "rc";
      };

      gentleEngramPiPath = overriddenDocument.selection.providers.pi.packages.gentle-engram;
    in
    pkgs.runCommandLocal "gentle-ai-check-pi-packages-render-through"
      {
        nativeBuildInputs = [
          gentleAi
          pkgs.jq
        ];
        defaultDocumentFile = pkgs.writeText "gentle-ai-document-pi-default.json" (
          builtins.toJSON defaultDocument
        );
        overriddenDocumentFile = pkgs.writeText "gentle-ai-document-pi-overridden.json" (
          builtins.toJSON overriddenDocument
        );
      }
      ''
        set -euo pipefail

        piCommands() {
          # commands is [][]string per resource; flattening each command with
          # a space is what the Go adapter's own tests compare against, so the
          # same join is used here rather than matching raw JSON tokens.
          jq -r '
            .manifest.resources[]
            | select(.selector == "provision" and .agent == "pi")
            | .commands[]
            | join(" ")
          ' "$1"
        }

        render() {
          local name="$1" doc="$2"
          mkdir -p "$PWD/home-$name" "$PWD/stage-$name"
          gentle-ai config render \
            --config "$doc" \
            --home "$PWD/home-$name" \
            --destination "$PWD/home-$name" \
            --stage "$PWD/stage-$name" \
            > "$PWD/$name.manifest.json"
        }

        render default "$defaultDocumentFile"
        render overridden "$overriddenDocumentFile"

        piCommands "$PWD/default.manifest.json" > default.commands
        piCommands "$PWD/overridden.manifest.json" > overridden.commands

        for want in "pi install npm:gentle-pi" "pi install npm:gentle-engram"; do
          grep -qxF "$want" default.commands || {
            echo "the default configuration no longer runs: $want" >&2
            cat default.commands >&2
            exit 1
          }
        done

        for want in \
          "pi install git:github.com/Gentleman-Programming/gentle-pi@6e4478c04615b0c013a017178dcfefa51579982d" \
          "pi install ${gentleEngramPiPath}" \
          "${gentleEngramPiPath}/bin/pi-engram init"
        do
          grep -qxF "$want" overridden.commands || {
            echo "the overridden configuration does not run: $want" >&2
            cat overridden.commands >&2
            exit 1
          }
        done

        touch "$out"
      '';

  # An unknown channel is a typo the operator should see immediately, at Nix
  # eval, rather than as a build failure once Pi tries to install a release
  # that was never in the table.
  piPackageChannelsRejectUnknownValues =
    pkgs.runCommandLocal "gentle-ai-check-pi-package-channels-reject-unknown-values" { }
      ''
        ${lib.optionalString
          (
            !(rejected [
              {
                programs.gentle-ai = {
                  enable = true;
                  providers.pi.enable = true;
                  gentlePiRelease = "nightly";
                };
              }
            ])
          )
          ''
            echo "an unknown gentlePiRelease was accepted" >&2
            exit 1
          ''
        }
        ${lib.optionalString
          (
            !(rejected [
              {
                programs.gentle-ai = {
                  enable = true;
                  providers.pi.enable = true;
                  engramRelease = "nightly";
                };
              }
            ])
          )
          ''
            echo "an unknown engramRelease was accepted" >&2
            exit 1
          ''
        }
        touch "$out"
      '';

  # The Pi plugin package itself: a directory Pi can register in place,
  # carrying the plugin's own files plus its one dependency vendored under
  # node_modules rather than left for `npm install` to resolve.
  gentleEngramPiPackageBuilds =
    let
      package = pkgs.callPackage ../packages/gentle-engram-pi.nix { };
    in
    pkgs.runCommandLocal "gentle-ai-check-gentle-engram-pi-package" { inherit package; } ''
      test -f "$package/package.json" || { echo "package.json missing from gentle-engram-pi" >&2; exit 1; }
      test -f "$package/index.ts" || { echo "index.ts missing from gentle-engram-pi" >&2; exit 1; }
      test -f "$package/cli.js" || { echo "cli.js missing from gentle-engram-pi" >&2; exit 1; }
      test -f "$package/node_modules/typebox/package.json" || {
        echo "typebox not vendored under node_modules in gentle-engram-pi" >&2
        exit 1
      }
      "$package/bin/pi-engram" --help >/dev/null || {
        echo "bin/pi-engram does not start the CLI in gentle-engram-pi" >&2
        exit 1
      }
      touch "$out"
    '';

  # The eval-level assertions this check replaced used to reject a misplaced
  # field before it ever reached Gentle AI. `misplacedProfilesNoLongerRejectedAtEval`
  # proves half of what they proved -- that Nix now accepts the document -- and
  # this proves the other half: the renderer itself still catches the mistake,
  # at build time, against the immutable document, and names it in a
  # diagnostic rather than staying silent.
  rendererSurfacesUnsupportedProviderMistakes =
    let
      gentleAi = (evaluate [ minimal ]).config.programs.gentle-ai.package;
      documentFor =
        providers:
        (evaluate [
          {
            programs.gentle-ai = {
              enable = true;
              inherit providers;
            };
          }
        ]).config.programs.gentle-ai.document;
      cases = {
        profiles = {
          code = "config.provider.profiles.unsupported-provider";
          document = documentFor {
            claude-code.enable = true;
            claude-code.profiles.cheap.orchestrator = {
              provider = "anthropic";
              model = "claude-haiku";
            };
          };
        };
        models = {
          code = "config.provider.models.unsupported-provider";
          document = documentFor {
            gemini-cli = {
              enable = true;
              models.orchestrator.model = "gemini-pro";
            };
          };
        };
        modelFamily = {
          code = "config.provider.model-family.unsupported-provider";
          document = documentFor {
            claude-code = {
              enable = true;
              modelFamily = "codex";
            };
          };
        };
      };
    in
    pkgs.runCommandLocal "gentle-ai-check-renderer-surfaces-mistakes"
      { nativeBuildInputs = [ gentleAi ]; }
      ''
        set -euo pipefail
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: case: ''
            mkdir -p "$PWD/home-${name}"
            if gentle-ai config render --config ${pkgs.writeText "gentle-ai-bad-document-${name}.json" (builtins.toJSON case.document)} --home "$PWD/home-${name}" --destination "$PWD/home-${name}" --stage "$PWD/stage-${name}" > ${name}.out 2>&1
            then
              echo "the renderer accepted a document naming ${name}, expected a ${case.code} diagnostic:" >&2
              cat ${name}.out >&2
              exit 1
            fi
            grep -q ${lib.escapeShellArg case.code} ${name}.out || {
              echo "the renderer's diagnostic did not name ${case.code}:" >&2
              cat ${name}.out >&2
              exit 1
            }
          '') cases
        )}
        touch "$out"
      '';

  # Layering is what makes the harness editable: an entry must be able to add a
  # file Gentle AI does not ship and to replace one it does.
  ownContentLayersOverTheRender = treeCheck "extra-files" ''
    grep -q "OWN-SKILL" "$rendered/tree/.config/opencode/skills/check-own/SKILL.md"
    grep -q "OVERRIDDEN" "$rendered/tree/.claude/agents/check-apply.md"
  '';

  # A tool that registers itself inside a file Gentle AI also writes must arrive
  # without either one overwriting the other, and the merged result has to be
  # readable: the merger keeps its output private everywhere else, because
  # everywhere else it is writing a credential.
  registeredContentMergesIntoTheRender = treeCheck "extra-files-merge" ''
    settings="$rendered/tree/.claude/settings.json"

    grep -q "OWN-SETTING" "$settings" || { echo "the merged content did not arrive" >&2; exit 1; }
    grep -q "outputStyle\|permissions\|hooks" "$settings" || { echo "the rendered settings were replaced" >&2; exit 1; }
    test -r "$settings" || { echo "the merged file is unreadable" >&2; exit 1; }
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

  # Settings and extensions describe the same provider document. Their nested
  # values must compose, while extensions remain the explicit override at a
  # colliding leaf and lists remain replacements.
  providerSettingsMerge =
    let
      providerSettingsConfiguration = evaluate [
        {
          programs.gentle-ai = {
            enable = true;
            providers = {
              claude-code = {
                enable = true;
                settings = {
                  providerOnly = "provider-only";
                  nested = {
                    providerOnly = "nested-provider-only";
                    shared = "provider";
                    list = [ "provider-list" ];
                  };
                };
              };
              opencode = {
                enable = true;
                settings.providerOnly = "other-provider";
              };
              pi.enable = true;
            };
            extensions = {
              claude-code = {
                extensionOnly = "extension-only";
                nested = {
                  extensionOnly = "nested-extension-only";
                  shared = "extension";
                  list = [ "extension-list" ];
                };
              };
              pi.extensionOnly = "one-sided-extension";
            };
          };
        }
      ];
      document = providerSettingsConfiguration.config.programs.gentle-ai.document;
      providerSettingsRendered = providerSettingsConfiguration.config.programs.gentle-ai.rendered;
    in
    assert document.extensions."claude-code".providerOnly == "provider-only";
    assert document.extensions."claude-code".extensionOnly == "extension-only";
    assert document.extensions."claude-code".nested.providerOnly == "nested-provider-only";
    assert document.extensions."claude-code".nested.extensionOnly == "nested-extension-only";
    assert document.extensions."claude-code".nested.shared == "extension";
    assert document.extensions."claude-code".nested.list == [ "extension-list" ];
    assert document.extensions.opencode.providerOnly == "other-provider";
    assert document.extensions.pi.extensionOnly == "one-sided-extension";
    treeCheck "provider-settings-merge" ''
      settings="${providerSettingsRendered}/tree/.claude/settings.json"
      grep -q 'provider-only' "$settings" || { echo "the provider setting was not rendered" >&2; exit 1; }
      grep -q 'extension-only' "$settings" || { echo "the extension setting was not rendered" >&2; exit 1; }
      grep -q 'nested-provider-only' "$settings" || { echo "the nested provider setting was not rendered" >&2; exit 1; }
      grep -q '"shared": "extension"' "$settings" || { echo "the extension did not win the collision" >&2; exit 1; }
      grep -q 'extension-list' "$settings" || { echo "the extension list was not rendered" >&2; exit 1; }
      grep -q 'provider-list' "$settings" && { echo "a colliding list was concatenated" >&2; exit 1; }
    '';

  # treefmt rewrites in place, so it runs against a writable copy and the check
  # is whether anything changed rather than whether it refused to run.
  # Generated reference documentation is only useful while it matches the
  # module. Committing it without this check is how a reference starts
  # describing options that were renamed a release ago.
  optionsDocumented =
    pkgs.runCommandLocal "gentle-ai-check-options-doc"
      {
        generated = import ../docs/options.nix {
          inherit pkgs;
          module = self.homeManagerModules.default;
        };
      }
      ''
        if ! diff -u ${../docs/options.md} "$generated"; then
          echo "docs/options.md is stale; regenerate it with 'nix build .#options-doc && cp result docs/options.md'" >&2
          exit 1
        fi
        touch "$out"
      '';

  # A merge that took the client's own state with it would be indistinguishable
  # from a working one until someone lost their OAuth session, so the merger is
  # exercised against a file holding exactly the kind of state it must preserve.
  mergePreservesClientState =
    pkgs.runCommandLocal "gentle-ai-check-merge"
      {
        nativeBuildInputs = [
          (pkgs.writers.writePython3Bin "gentle-ai-merge" {
            libraries = [ pkgs.python3Packages.tomlkit ];
            flakeIgnore = [
              "E501"
              "W503"
            ];
          } (builtins.readFile ../lib/merge.py))
        ];
      }
      ''
        set -euo pipefail
        printf 'v4lue' > secret

        cat > target.json <<'JSON'
        {"mcpServers":{"engram":{"command":"engram"}},"oauthAccount":{"id":"me"},"projects":{"/a":{}}}
        JSON
        cat > fragment.json <<'JSON'
        {"mcpServers":{"atlas":{"env":{"TOKEN":"@TOKEN@"}}}}
        JSON

        gentle-ai-merge --fragment fragment.json --target target.json --secret "TOKEN=$PWD/secret"

        grep -q '"oauthAccount"' target.json || { echo "the merge dropped the client's own state" >&2; exit 1; }
        grep -q '"engram"' target.json || { echo "the merge dropped an entry it did not declare" >&2; exit 1; }
        grep -q '"atlas"' target.json || { echo "the merge did not add the declared entry" >&2; exit 1; }
        grep -q 'v4lue' target.json || { echo "the placeholder was not resolved" >&2; exit 1; }
        grep -q '@TOKEN@' target.json && { echo "the placeholder survived" >&2; exit 1; }

        cat > target.toml <<'TOML'
        # a comment worth keeping
        [projects."/w"]
        trust_level = "trusted"
        TOML
        cat > fragment.toml <<'TOML'
        [mcp_servers.atlas]
        command = "atlas"
        TOML

        gentle-ai-merge --fragment fragment.toml --target target.toml --secret "TOKEN=$PWD/secret"
        cp target.toml once.toml
        gentle-ai-merge --fragment fragment.toml --target target.toml --secret "TOKEN=$PWD/secret"

        grep -q 'a comment worth keeping' target.toml || { echo "the TOML merge dropped a comment" >&2; exit 1; }
        grep -q 'trust_level' target.toml || { echo "the TOML merge dropped the client's own state" >&2; exit 1; }
        grep -q 'mcp_servers.atlas' target.toml || { echo "the TOML merge did not add the declared table" >&2; exit 1; }
        diff -u once.toml target.toml || { echo "merging twice changed the file" >&2; exit 1; }

        # An array the client maintains is the one thing a merge must not
        # replace. Pi rebuilds its package list as it installs, so replacing it
        # with the two entries the document names uninstalls the harness from
        # the client's point of view on the next switch. An array the harness
        # owns still has to be replaceable, or a rule removed from the
        # declaration would live on forever.
        cat > client.json <<'JSON'
        {"packages":["npm:gentle-pi","npm:pi-btw"],"permissions":{"deny":["stale"]}}
        JSON
        cat > declared.json <<'JSON'
        {"packages":["npm:pi-mcp-adapter"],"permissions":{"deny":["current"]}}
        JSON

        gentle-ai-merge --fragment declared.json --target client.json --union-list packages

        grep -q 'npm:gentle-pi' client.json || { echo "the merge dropped a package the client installed" >&2; exit 1; }
        grep -q 'npm:pi-mcp-adapter' client.json || { echo "the merge did not add the declared package" >&2; exit 1; }
        grep -q 'stale' client.json && { echo "a harness-owned list accumulated instead of being replaced" >&2; exit 1; }

        cp client.json once.json
        gentle-ai-merge --fragment declared.json --target client.json --union-list packages
        diff -u once.json client.json || { echo "merging twice grew the unioned list" >&2; exit 1; }

        # An unreadable secret must leave the placeholder rather than empty it:
        # an empty credential reads as a configured one and fails at use.
        cat > bare.toml <<'TOML'
        [mcp_servers.atlas]
        token = "@ABSENT@"
        TOML
        gentle-ai-merge --fragment bare.toml --target kept.toml 2>/dev/null
        grep -q '@ABSENT@' kept.toml || { echo "an unresolved placeholder was emptied" >&2; exit 1; }

        touch "$out"
      '';

  # Home Manager activates with a PATH of its own build tools. A provisioning
  # step that inherits only that PATH finds no client, skips, and leaves an
  # installation that looks done and installed nothing — which is exactly what
  # it did the first time. The activation script itself is the only place that
  # is visible, so it is what this reads.
  provisioningSeesTheClient =
    let
      provisioning = evaluate [
        {
          programs.gentle-ai = {
            enable = true;
            providers.pi = {
              enable = true;
              provisionPackages = true;
            };
          };
        }
      ];
    in
    pkgs.runCommandLocal "gentle-ai-check-provision-path"
      { activation = provisioning.config.home.activationPackage; }
      ''
        set -euo pipefail

        line=$(grep -n 'gentle-ai-provision' "$activation/activate" | head -1 | cut -d: -f1)
        test -n "$line" || { echo "no provisioning step in the activation script" >&2; exit 1; }

        context=$(sed -n "$((line > 3 ? line - 3 : 1)),''${line}p" "$activation/activate")
        echo "$context" | grep -qF ${lib.escapeShellArg "${provisioning.config.home.profileDirectory}/bin"} || {
          echo "the provisioning step cannot see the client's own profile:" >&2
          echo "$context" >&2
          exit 1
        }

        touch "$out"
      '';

  # Provisioning is the one activation step that reaches a network and installs
  # something Nix does not track, so what it must never do is as important as
  # what it does: no repeat on an unchanged list, and no failed activation when
  # the client itself is not installed.
  provisioningRunsDeclaredCommandsOnce =
    pkgs.runCommandLocal "gentle-ai-check-provision"
      {
        nativeBuildInputs = [
          (pkgs.writers.writePython3Bin "gentle-ai-provision" {
            flakeIgnore = [
              "E501"
              "W503"
            ];
          } (builtins.readFile ../lib/provision.py))
        ];
      }
      ''
        set -euo pipefail

        cat > manifest.json <<'JSON'
        {"manifest":{"resources":[
          {"path":".pi/agent/settings.json","selector":"file","digest":"abc"},
          {"path":"engram","selector":"provision","digest":"present","component":"engram"},
          {"path":"pi","selector":"provision","digest":"present","agent":"pi",
           "commands":[["fake-pi","install","npm:gentle-pi"],["fake-pi","install","npm:gentle-engram"]]}
        ]}}
        JSON

        mkdir -p bin stamps
        cat > bin/fake-pi <<'SH'
        #!/bin/sh
        echo "$@" >> "$RECORD"
        SH
        chmod +x bin/fake-pi
        export RECORD="$PWD/ran"
        touch "$RECORD"

        # Without the client on PATH the step reports and returns, so one
        # uninstalled client cannot take an unrelated switch down with it.
        gentle-ai-provision --manifest manifest.json --agent pi --stamp-dir stamps 2>/dev/null
        test -s "$RECORD" && { echo "commands ran without the client installed" >&2; exit 1; }
        test -e stamps/pi.provisioned && { echo "a skipped run recorded a stamp" >&2; exit 1; }

        export PATH="$PWD/bin:$PATH"
        gentle-ai-provision --manifest manifest.json --agent pi --stamp-dir stamps 2>/dev/null
        grep -q 'npm:gentle-pi' "$RECORD" || { echo "the declared commands did not run" >&2; exit 1; }
        grep -q 'npm:gentle-engram' "$RECORD" || { echo "only part of the stack ran" >&2; exit 1; }

        cp "$RECORD" once
        gentle-ai-provision --manifest manifest.json --agent pi --stamp-dir stamps 2>/dev/null
        diff -u once "$RECORD" || { echo "an unchanged command list ran twice" >&2; exit 1; }

        # A component provision is engram's, not an agent's: reading one as the
        # other would run a package stack for a client no document named.
        gentle-ai-provision --manifest manifest.json --agent engram --stamp-dir stamps 2>/dev/null
        diff -u once "$RECORD" || { echo "a component provision ran agent commands" >&2; exit 1; }

        # A community tool wires itself through the same step, and the two kinds
        # keep separate stamps: an agent and a tool sharing a name must not read
        # as each other's work already done.
        cat > tool.json <<'JSON'
        {"manifest":{"resources":[
          {"path":"codegraph","selector":"provision","digest":"present","tool":"codegraph",
           "commands":[["fake-pi","install","--target","claude"]]}
        ]}}
        JSON

        gentle-ai-provision --manifest tool.json --agent codegraph --stamp-dir stamps 2>/dev/null
        diff -u once "$RECORD" || { echo "a tool provision ran as an agent" >&2; exit 1; }

        gentle-ai-provision --manifest tool.json --tool codegraph --stamp-dir stamps 2>/dev/null
        grep -q 'install --target claude' "$RECORD" || { echo "the tool wiring did not run" >&2; exit 1; }
        test -e stamps/tool-codegraph.provisioned || { echo "the tool run recorded no stamp of its own" >&2; exit 1; }

        touch "$out"
      '';

  # A borrowed harness carries the source client's directory in its own prose,
  # so a client reading the copy is told to open a file under the tree it was
  # copied out of -- which is the tree it refuses to read through, for the very
  # client the copy exists for. Both directions are asserted, because a rewriter
  # that ran unconditionally would be as wrong as one that never ran.
  customProviderReferencesAreRewritten =
    let
      borrowing = evaluate [
        {
          programs.gentle-ai = {
            enable = true;

            providers.claude-code.enable = true;
            components.skills.enable = true;

            extraFiles.".claude/agents/check-reference.md".text = ''
              Read ~/.claude/skills/_shared/check-workflow.md, then .claude/CLAUDE.md.
            '';

            customProviders = {
              agens = {
                root = ".config/agens";
                from = "claude-code";
                rewriteReferences = true;
                assets = {
                  "CLAUDE.md" = "AGENTS.md";
                  agents = "agents";
                  skills = "skills";
                };
              };

              verbatim = {
                root = ".config/verbatim";
                from = "claude-code";
                assets.agents = "agents";
              };
            };
          };
        }
      ];

      sourceFor =
        target:
        (lib.findSingle (entry: entry.target == target) null null (
          lib.attrValues borrowing.config.home.file
        )).source;

      borrowed = borrowing.config.programs.gentle-ai.rendered;
    in
    pkgs.runCommandLocal "gentle-ai-check-custom-provider-references"
      {
        rewritten = sourceFor ".config/agens/agents";
        untouched = sourceFor ".config/verbatim/agents";
        original = "${borrowed}/tree/.claude/agents";
      }
      ''
        set -euo pipefail

        reference="$rewritten/check-reference.md"

        grep -qF '~/.config/agens/skills/_shared/check-workflow.md' "$reference" || {
          echo "a reference into the source client's skills was left pointing there:" >&2
          cat "$reference" >&2
          exit 1
        }
        grep -qF '.config/agens/AGENTS.md' "$reference" || {
          echo "a renamed asset was not referenced under the name it was renamed to:" >&2
          cat "$reference" >&2
          exit 1
        }
        grep -qF '.claude/' "$reference" && {
          echo "a reference to the source client's directory survived:" >&2
          cat "$reference" >&2
          exit 1
        }

        # Without the option the assets are the rendered subtree itself, not a
        # copy of it: the bytes have to be the same ones, and the path too.
        ${lib.optionalString (sourceFor ".config/verbatim/agents" != "${borrowed}/tree/.claude/agents") ''
          echo "a provider that asked for no rewriting was given a rewritten copy" >&2
          exit 1
        ''}
        diff -r "$original" "$untouched" || {
          echo "a provider that asked for no rewriting had its assets changed" >&2
          exit 1
        }

        touch "$out"
      '';

  # A receiving client may require a frontmatter key the source dialect never
  # writes. The default has to appear where it was missing, must not overwrite
  # a stated value, and must leave every provider that declared no defaults
  # with the untouched subtree.
  customProviderFrontmatterDefaultsAreFilled =
    let
      borrowing = evaluate [
        {
          programs.gentle-ai = {
            enable = true;

            providers.claude-code.enable = true;

            extraFiles.".claude/agents/check-missing.md".text = ''
              ---
              name: check-missing
              description: An agent whose source dialect states no mode.
              ---

              Body.
            '';

            extraFiles.".claude/agents/check-stated.md".text = ''
              ---
              name: check-stated
              description: An agent that already states a mode of its own.
              mode: all
              ---

              Body.
            '';

            customProviders = {
              agens = {
                root = ".config/agens";
                from = "claude-code";
                frontmatterDefaults.agents.mode = "subagent";
                assets.agents = "agents";
              };

              verbatim = {
                root = ".config/verbatim";
                from = "claude-code";
                assets.agents = "agents";
              };
            };
          };
        }
      ];

      sourceFor =
        target:
        (lib.findSingle (entry: entry.target == target) null null (
          lib.attrValues borrowing.config.home.file
        )).source;

      borrowed = borrowing.config.programs.gentle-ai.rendered;
    in
    pkgs.runCommandLocal "gentle-ai-check-custom-provider-frontmatter"
      {
        filledTree = sourceFor ".config/agens/agents";
        untouched = sourceFor ".config/verbatim/agents";
        original = "${borrowed}/tree/.claude/agents";
      }
      ''
        set -euo pipefail

        grep -qxF 'mode: subagent' "$filledTree/check-missing.md" || {
          echo "a missing frontmatter key was not filled with its default:" >&2
          cat "$filledTree/check-missing.md" >&2
          exit 1
        }
        grep -qxF 'mode: all' "$filledTree/check-stated.md" || {
          echo "a stated frontmatter value did not survive the default:" >&2
          cat "$filledTree/check-stated.md" >&2
          exit 1
        }
        grep -qxF 'mode: subagent' "$filledTree/check-stated.md" && {
          echo "a default was inserted beside a stated value:" >&2
          cat "$filledTree/check-stated.md" >&2
          exit 1
        }

        diff -r "$original" "$untouched" || {
          echo "a provider that declared no defaults had its assets changed" >&2
          exit 1
        }

        touch "$out"
      '';

  formatting = pkgs.runCommandLocal "gentle-ai-check-formatting" { } ''
    cp -r --no-preserve=mode,ownership ${self} source
    ${
      lib.getExe self.formatter.${system}
    } --tree-root source --no-cache --fail-on-change source >/dev/null || {
      echo "the flake is not formatted; run 'nix fmt'" >&2
      exit 1
    }
    touch "$out"
  '';
}
