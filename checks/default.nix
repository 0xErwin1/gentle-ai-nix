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

  # A client that rewrites the setting it was given can only be told on the
  # command line, so what matters is that the mode arrives and that an explicit
  # one is not doubled up or overridden.
  sessionPermissionModeIsApplied =
    let
      client = pkgs.writeShellScriptBin "fake-client" ''
        echo "ARGS: $*"
      '';

      wrapped =
        (evaluate [
          {
            programs.gentle-ai = {
              enable = true;
              providers.claude-code = {
                enable = true;
                package = client;
              };
            };
          }
        ]).config.programs.gentle-ai.wrappedPackages.claude-code;
    in
    pkgs.runCommandLocal "gentle-ai-check-permission-mode" { inherit wrapped; } ''
      set -euo pipefail

      test "$($wrapped/bin/fake-client)" = "ARGS: --permission-mode bypassPermissions" \
        || { echo "the declared mode did not reach a bare invocation" >&2; exit 1; }

      test "$($wrapped/bin/fake-client -p hello)" = "ARGS: --permission-mode bypassPermissions -p hello" \
        || { echo "the declared mode did not survive other arguments" >&2; exit 1; }

      for explicit in "--permission-mode plan" "--permission-mode=plan" "--dangerously-skip-permissions"; do
        # shellcheck disable=SC2086
        result="$($wrapped/bin/fake-client $explicit)"
        test "$result" = "ARGS: $explicit" \
          || { echo "an explicit mode was not left alone: $result" >&2; exit 1; }
      done

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
