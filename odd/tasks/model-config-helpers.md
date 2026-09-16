# model-config-helpers

Native helpers for declaring model assignments, plus a profile-level effort
default, so a consumer's `home.nix` stops carrying its own `let onCodex = ...`.

- Requested by: Ignacio (2026-09-16), from the ad-hoc `profiles = let onCodex =
  ...; astra = onCodex "gpt-6-astra";` helpers in
  `~/.config/home-manager/home-manager/global/ai-harness-gentle-ai.nix`.
- Status: done (2026-09-16). Independent verification passed; nothing committed.

## Decisions

- **No provider table, ever.** Pi resolves provider ids at runtime from the
  packages installed beside it (`~/.pi/agent/models-store.json` is keyed by
  exactly those ids), so any list baked into this flake is one machine's answer
  frozen into everyone's. `on` takes the id; `for` names the ids the caller
  declares. `internal/pirouting`'s single `familyProviderPrefix` entry
  (`codex -> openai-codex/`) is the only provider-id knowledge this flake has,
  and it stays there.
- **Effort is a combinator, not a third argument.** Nix only allows argument
  defaults in attrset patterns, so `provider: model: effort ? null: ...` is not
  expressible; a two-argument form plus a separate effort modifier is the shape
  that stays strictly typed (`models.effort.high (m.on "nan" "glm")`). This is
  the "HighEffort" the request asked for.
- **`defaultEffort` is scoped to one profile.** It fills `orchestrator` and
  `phases.*` only; an assignment that states its own effort keeps it, and
  `providers.<id>.models` / `roles.<id>.model` are not a profile's to fill.
- **Pass-through, not validation.** Which reasoning levels a client accepts is
  that client's answer (`internal/pirouting` owns gentle-pi's closed set; the
  pinned contract accepts `effort` on an opencode profile assignment too, proven
  against `gentle-ai-2.9.1-main.9f2b4c17-declarative-config`). Nothing here
  narrows the strings.
- The `effort` field resolved in Nix still travels to the same
  `gentle-ai.model-presets/v1`-shaped spec JSON, unchanged: no Go change.

## Tasks

- [x] `lib/models.nix`: `on`, `withEffort`, `effort.<level>`, `for`; exported as
      the new `lib` flake output (`lib.models`).
- [x] `modules/home-manager.nix`: `profileType.defaultEffort` and its
      application inside `profile`.
- [x] `checks/default.nix`: helper shapes and refusal of non-string ids,
      `defaultEffort` precedence in the document (opencode) and in the rendered
      tree (pi `profiles.json` + `defaultThinkingLevel`).
- [x] `docs/options.md` regenerated (`nix build .#options-doc`).
- [x] README: the two conveniences, in the "What you declare" section.
- [x] `examples/home.nix`: `defaultEffort` on the cheap profile.

## Evidence

Commands and observed results, in the order the work closed. Each of the three
new checks was run once before the implementation existed (RED) and again
after (GREEN); the RED failures are recorded with the check they belong to.

- `nix build .#checks.x86_64-linux.modelHelpersBuildDeclaredProviders` -- RED:
  `error: attribute 'lib' missing` at `self.lib.models`. GREEN: built
  `gentle-ai-check-model-helpers-shapes`; all six grep shapes held (mechanical
  names from ids and from aliases, the seven effort levels, effort added and
  absent).
- `nix build .#checks.x86_64-linux.modelHelpersRefuseNonProviderIds` -- RED:
  same missing `lib` error. GREEN: built; `42`, `[ 7 ]` and `[ "" ]` all
  rejected.
- `nix build
  .#checks.x86_64-linux.defaultEffortFillsProfileAssignmentsWithoutOverridingThem`
  -- RED: `The option
  'programs.gentle-ai.providers.opencode.profiles.helpers.defaultEffort' does
  not exist`. GREEN: built through the real render (`gentle-ai config render`
  plus `gentle-nix pi routing`): the opencode document shows `high` on
  orchestrator and `sdd-apply` and keeps `low` on `sdd-verify`; the rendered
  tree carries `"active": "helpers"`, `"nan/glm5.3-flash"`, `"thinking":
  "high"` and `"thinking": "low"` in `profiles.json`, and
  `"defaultThinkingLevel": "high"` in `agent/settings.json`.
- `nix build .#options-doc && cp -f result docs/options.md` -- regenerated. The
  diff is the new `defaultEffort` option plus a two-line blank-line reshuffle
  the doc generator itself produced around `secrets.envFiles`/`secrets.merge`;
  the file is a fresh render, which is what `optionsDocumented` compares
  against.
- `nix build .#checks.x86_64-linux.optionsDocumented` -- built.
- `nix fmt`, then `git status --short` -- 7 files formatted, 2 changed (the
  formatter reindented the new code to the file's own 2-space convention;
  content kept as written). Status shows only the files this feature owns plus
  the pre-existing untracked `odd/`.
- `nix build .#checks.x86_64-linux.formatting` -- built, 0 files changed.

`nix flake check` was not run: the release-channel builds need the network and
were explicitly out of scope for this task.

`lib/models.nix` is new, and a flake cannot see an untracked file, so it carries
an intent-to-add index entry (`git add -N`): an empty blob in the index, no
staged content, reversible with `git rm --cached lib/models.nix` -- at the cost
of `nix build .#` losing sight of the file until it is staged or committed.

An independent read-only verifier re-ran all three checks plus
`optionsDocumented` and `formatting` with `--rebuild`, evaluated the library from
its own expressions, diffed `docs/options.md` against a fresh render
(byte-identical), and checked the README and the option description against the
implementation: PASS on every item, no defect found. The parent spot check
re-ran `defaultEffortFillsProfileAssignmentsWithoutOverridingThem` and evaluated
`.#lib.models` from the flake reference.

## Native review

Lineage `review-41831c6d85453fba`, tier medium, one lens (`review-reliability`),
7 changed files, 356 changed lines, correction budget 178. Status approved and
the acknowledgement burned the authority
(`gentle-ai.review-acknowledged/v1`). This task file was deliberately left out
of the review's candidate paths -- it is planning record, not deliverable -- and
it was not touched by the review.

The review blocked first with `package-local-binary-missing`, which traced to the
runtime-repair path in the home-manager configuration (see
`~/.config/home-manager/odd/tasks/gentle-pi-runtime-repair-path.md`). Once that
was fixed and the bundled binary was extracted, the same candidate started and
closed normally.

Two advisory findings came back, both informational and non-blocking. They are
follow-up work, not a reason to re-review this candidate:

- `R3-effort-precedence` (`lib/models.nix:26`) -- `withEffort` merges with `//`, so
  the modifier replaces an effort the assignment already states instead of
  yielding to it, unlike `defaultEffort`. That is the intended reading of a
  modifier, but the two rules are worth stating side by side in the README.
- `R3-constructor-collisions` (`lib/models.nix:63`) -- in the list form of `for`,
  two ids that camelCase the same (`a-b` and `a_b`, say) collapse to one key and
  `listToAttrs` keeps the last silently. Unlikely, but it is the one shape where
  the mechanical names can lose an entry without a message.

## Risks

- `docs/options.md` and the README must not describe a shape the module does not
  have; `optionsDocumented` in `checks/default.nix` enforces the first.
- A profile default silently changing an assignment nobody re-read is the one
  way this feature can lie. The precedence check is what keeps it honest.
