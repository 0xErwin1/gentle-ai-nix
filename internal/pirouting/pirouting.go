// Package pirouting owns the three files the pinned Gentle AI fork used to
// render for Pi from the document's providers.pi block --
// .pi/gentle-ai/profiles.json, .pi/gentle-ai/models.json, and the
// orchestrator defaults merged into .pi/agent/settings.json -- now that
// gentle-nix stops emitting providers.pi.{models,profiles,activeProfile,
// modelFamily,modelPreset} in the document at all. Pi's own routing and
// gentle-pi's own profile store are not Gentle AI features: they are
// gentle-pi's, and gentle-nix reaches them directly instead of asking the
// document to carry fields only this flake needs.
//
// This package reproduces exactly what the fork's own
// internal/model.PiModelsFromCodexPreset, internal/config.applyPiActiveProfile
// and internal/cli/config_stager.go's stagePiModelRouting/stagePiAgentProfiles/
// stagePiActiveProfileDefaults wrote, so the bytes on disk do not change the
// day this flake takes over writing them.
package pirouting

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/0xErwin1/gentle-ai-nix/internal/settings"
)

// ValidationError marks a problem with the declared spec itself -- a bad
// profile name, an incomplete assignment, an unknown preset -- as opposed to
// an I/O failure while writing the result. gentle-nix pi routing uses this
// distinction to exit 2 for the former and 1 for the latter, the same split
// gentle-nix settings already makes for an unknown provider.
type ValidationError struct{ msg string }

func (e ValidationError) Error() string { return e.msg }

func validationErrorf(format string, args ...any) error {
	return ValidationError{msg: fmt.Sprintf(format, args...)}
}

// ModelAssignment is one phase's or orchestrator's model, in the same shape
// modelAssignmentType in modules/home-manager.nix renders it: a provider and
// a model are both required, effort is optional. This mirrors the pinned
// fork's own config.ModelAssignment.
type ModelAssignment struct {
	Provider string `json:"provider"`
	Model    string `json:"model"`
	Effort   string `json:"effort,omitempty"`
}

func (a ModelAssignment) empty() bool {
	return a.Provider == "" && a.Model == "" && a.Effort == ""
}

// AgentRouting is one Pi agent's routing: a model, a reasoning level, or
// both. Either half stands alone, mirroring the fork's own
// model.PiAgentRouting -- a model with no level takes the level Pi is
// running at, and a level with no model applies to whatever model the
// session is on.
type AgentRouting struct {
	Model    string `json:"model,omitempty"`
	Thinking string `json:"thinking,omitempty"`
}

// Profile is one named gentle-pi profile: an orchestrator entry and a set of
// per-phase entries, the same shape modules/home-manager.nix's own `profile`
// function renders it in (see providerBlock's whenSet "phaseAssignments").
type Profile struct {
	Orchestrator     *ModelAssignment           `json:"orchestrator,omitempty"`
	PhaseAssignments map[string]ModelAssignment `json:"phaseAssignments,omitempty"`
}

// Spec is gentle-nix pi routing's own input contract: what the Nix module
// writes from providers.pi.{models,profiles,activeProfile,modelFamily,
// modelPreset}, plus the presets document that provider's model table comes
// from when a family and a preset are both named.
type Spec struct {
	Models        map[string]AgentRouting `json:"models,omitempty"`
	Profiles      map[string]Profile      `json:"profiles,omitempty"`
	ActiveProfile string                  `json:"activeProfile,omitempty"`
	ModelFamily   string                  `json:"modelFamily,omitempty"`
	ModelPreset   string                  `json:"modelPreset,omitempty"`

	// Presets is either the gentle-ai.model-presets/v1 document itself (a
	// JSON object) or a JSON string naming the path to a file holding it.
	// Only read when ModelFamily and ModelPreset are both set.
	Presets json.RawMessage `json:"presets,omitempty"`
}

// validThinkingLevels mirrors the fork's own model.PiThinkingLevel.Valid.
var validThinkingLevels = map[string]bool{
	"off": true, "minimal": true, "low": true, "medium": true,
	"high": true, "xhigh": true, "max": true,
}

// ValidThinking reports whether level is empty or one of gentle-pi's own
// reasoning levels.
func ValidThinking(level string) bool {
	return level == "" || validThinkingLevels[level]
}

// safeProfileName mirrors the fork's own safePiProfileName: the pattern
// gentle-pi validates a profile name against.
var safeProfileName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`)

var reservedProfileNames = map[string]bool{
	"__proto__": true, "constructor": true, "prototype": true,
}

// reservedPhaseKey is the phase key gentle-pi reserves for the profile's
// orchestrator entry; a phase assignment cannot reuse it.
const reservedPhaseKey = "orchestrator"

// supportedModelFamilies are the providers whose model table this package
// knows how to fill Pi's routing from. Pi has no catalogue of its own, so
// naming a family it cannot borrow from is a document mistake worth failing
// on rather than silently filling nothing.
var supportedModelFamilies = map[string]bool{"codex": true}

// Validate reports the first problem found in spec, in the same spirit as
// the fork's own validateProviderModelFamily/validateProviderModelPreset/
// validatePiProfileNames/validatePiProfileValues/validatePiRoutingValues:
// one clear message per mistake, rather than a partial apply.
func Validate(spec Spec) error {
	for agent, routing := range spec.Models {
		if !ValidThinking(routing.Thinking) {
			return validationErrorf("models.%s.thinking: unsupported reasoning level %q", agent, routing.Thinking)
		}
	}

	for name, profile := range spec.Profiles {
		if reservedProfileNames[name] || !safeProfileName.MatchString(name) {
			return validationErrorf("profiles.%s: invalid profile name; use letters or digits, then letters, digits, '.', '_' or '-', at most 64 characters, and not a reserved name", name)
		}

		if profile.Orchestrator != nil {
			if err := validateAssignment("profiles."+name+".orchestrator", *profile.Orchestrator); err != nil {
				return err
			}
		}

		if _, reserved := profile.PhaseAssignments[reservedPhaseKey]; reserved {
			return validationErrorf("profiles.%s.phaseAssignments.%s: phase %q is reserved for the profile's orchestrator entry", name, reservedPhaseKey, reservedPhaseKey)
		}

		for phase, assignment := range profile.PhaseAssignments {
			if err := validateAssignment(fmt.Sprintf("profiles.%s.phaseAssignments.%s", name, phase), assignment); err != nil {
				return err
			}
		}
	}

	if spec.ActiveProfile != "" {
		if _, ok := spec.Profiles[spec.ActiveProfile]; !ok {
			return validationErrorf("activeProfile %q does not name a declared profile", spec.ActiveProfile)
		}
	}

	if spec.ModelPreset != "" && spec.ModelFamily == "" {
		return validationErrorf("modelPreset %q was set without modelFamily; naming the family is what tells Pi's routing which provider table to borrow", spec.ModelPreset)
	}

	if spec.ModelFamily != "" && !supportedModelFamilies[spec.ModelFamily] {
		return validationErrorf("modelFamily %q is not a provider gentle-nix can fill Pi's routing from", spec.ModelFamily)
	}

	return nil
}

func validateAssignment(path string, assignment ModelAssignment) error {
	if assignment.Provider == "" || assignment.Model == "" {
		return validationErrorf("%s: a model assignment requires both provider and model", path)
	}
	if !ValidThinking(assignment.Effort) {
		return validationErrorf("%s.effort: unsupported reasoning level %q", path, assignment.Effort)
	}
	return nil
}

// routingFromAssignment mirrors the fork's own piRoutingFromAssignment /
// piProfileEntryFromAssignment: a phase's provider-qualified model becomes
// "<provider>/<model>", and its effort becomes the reasoning level.
func routingFromAssignment(assignment ModelAssignment) AgentRouting {
	routing := AgentRouting{Thinking: assignment.Effort}
	if !assignment.empty() {
		routing.Model = assignment.Provider + "/" + assignment.Model
	}
	return routing
}

// Result is what Build resolves from a validated Spec: the bytes for
// profiles.json (nil when there is nothing to write), the routing table for
// models.json (nil when empty), and the orchestrator defaults to merge into
// Pi's own settings.json (nil when the active profile assigns none).
type Result struct {
	ProfilesDocument []byte
	ModelRouting     map[string]AgentRouting
	SettingsDefaults map[string]string
}

// piAgentForPhase renames the phases whose gentle-pi agent name differs from
// Gentle AI's own phase id. Mirrors the fork's own piAgentForPhase.
var piAgentForPhase = map[string]string{
	"sdd-propose": "sdd-proposal",
}

// familyProviderPrefix maps a model family to the provider prefix Pi
// resolves a bare model id through, e.g. "openai-codex/<model>" for codex.
// One small table, extended only as gentle-nix learns to fill Pi's routing
// from another provider's preset table.
var familyProviderPrefix = map[string]string{
	"codex": "openai-codex/",
}

// Build resolves spec into the files gentle-nix pi routing writes.
// loadPresets is called only when spec.ModelFamily and spec.ModelPreset are
// both set, and receives spec.Presets verbatim (an embedded document or a
// path string) so callers can keep the file-reading concern outside this
// pure function.
func Build(spec Spec, presets *PresetsDocument) (Result, error) {
	if err := Validate(spec); err != nil {
		return Result{}, err
	}

	routing := map[string]AgentRouting{}

	// Lowest precedence: the family preset fills only the agents the fork's
	// own PiModelsFromCodexPreset would have filled.
	if spec.ModelFamily != "" && spec.ModelPreset != "" {
		if presets == nil {
			return Result{}, validationErrorf("modelFamily %q and modelPreset %q were declared but no presets document was given", spec.ModelFamily, spec.ModelPreset)
		}
		fill, err := familyPresetFill(spec.ModelFamily, spec.ModelPreset, *presets)
		if err != nil {
			return Result{}, err
		}
		for agent, entry := range fill {
			routing[agent] = entry
		}
	}

	// Middle precedence: the active profile's expansion, orchestrator
	// included under its reserved key.
	var settingsDefaults map[string]string
	if spec.ActiveProfile != "" {
		profile := spec.Profiles[spec.ActiveProfile]
		if profile.Orchestrator != nil {
			routing[reservedPhaseKey] = routingFromAssignment(*profile.Orchestrator)
			settingsDefaults = orchestratorDefaults(*profile.Orchestrator)
		}
		for phase, assignment := range profile.PhaseAssignments {
			routing[phase] = routingFromAssignment(assignment)
		}
	}

	// Highest precedence: an explicit model assignment always wins.
	for agent, entry := range spec.Models {
		routing[agent] = entry
	}

	var profilesDocument []byte
	if len(spec.Profiles) > 0 {
		encoded, err := marshalProfilesDocument(spec)
		if err != nil {
			return Result{}, err
		}
		profilesDocument = encoded
	}

	var modelRouting map[string]AgentRouting
	if len(routing) > 0 {
		modelRouting = routing
	}

	return Result{
		ProfilesDocument: profilesDocument,
		ModelRouting:     modelRouting,
		SettingsDefaults: settingsDefaults,
	}, nil
}

func orchestratorDefaults(assignment ModelAssignment) map[string]string {
	overlay := map[string]string{}
	if assignment.Provider != "" {
		overlay["defaultProvider"] = assignment.Provider
	}
	if assignment.Model != "" {
		overlay["defaultModel"] = assignment.Model
	}
	if assignment.Effort != "" {
		overlay["defaultThinkingLevel"] = assignment.Effort
	}
	if len(overlay) == 0 {
		return nil
	}
	return overlay
}

// profileEntry is one phase's routing inside the staged profile document,
// mirroring the fork's own piModelEntry.
type profileEntry struct {
	Model    string `json:"model,omitempty"`
	Thinking string `json:"thinking,omitempty"`
}

func entryFromRouting(routing AgentRouting) profileEntry {
	return profileEntry{Model: routing.Model, Thinking: routing.Thinking}
}

// profilesDocument mirrors the fork's own piAgentProfilesDocument: the file
// gentle-pi's own "apply" reads profiles from.
type profilesDocument struct {
	Kind     string                             `json:"kind"`
	Version  int                                `json:"version"`
	Active   string                             `json:"active,omitempty"`
	Profiles map[string]map[string]profileEntry `json:"profiles"`
}

const profilesKind = "gentle-pi.agent_model_profiles"

func marshalProfilesDocument(spec Spec) ([]byte, error) {
	document := profilesDocument{
		Kind:     profilesKind,
		Version:  1,
		Active:   spec.ActiveProfile,
		Profiles: make(map[string]map[string]profileEntry, len(spec.Profiles)),
	}

	for name, profile := range spec.Profiles {
		entries := make(map[string]profileEntry, len(profile.PhaseAssignments)+1)
		if profile.Orchestrator != nil {
			entries[reservedPhaseKey] = entryFromRouting(routingFromAssignment(*profile.Orchestrator))
		}
		for phase, assignment := range profile.PhaseAssignments {
			entries[phase] = entryFromRouting(routingFromAssignment(assignment))
		}
		document.Profiles[name] = entries
	}

	encoded, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("marshal Pi agent profiles: %w", err)
	}
	return append(encoded, '\n'), nil
}

// PresetsDocument is the gentle-ai.model-presets/v1 document `gentle-ai
// config presets --provider <family> --json` prints.
type PresetsDocument struct {
	Schema    string                          `json:"schema"`
	Providers map[string]presetsProviderEntry `json:"providers"`
}

type presetsProviderEntry struct {
	Presets map[string]map[string]presetPhaseEntry `json:"presets"`
}

type presetPhaseEntry struct {
	Model  string `json:"model"`
	Effort string `json:"effort"`
}

// DecodePresets accepts either an embedded gentle-ai.model-presets/v1
// document or a JSON string naming the path to one, exactly as the "presets"
// field of Spec may carry it.
func DecodePresets(raw json.RawMessage) (*PresetsDocument, error) {
	if len(raw) == 0 {
		return nil, nil
	}

	var path string
	if err := json.Unmarshal(raw, &path); err == nil {
		content, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read presets document %q: %w", path, err)
		}
		raw = content
	}

	var document PresetsDocument
	if err := json.Unmarshal(raw, &document); err != nil {
		return nil, fmt.Errorf("decode presets document: %w", err)
	}
	return &document, nil
}

// familyPresetFill mirrors the fork's own PiModelsFromCodexPreset, sourced
// from the flat gentle-ai.model-presets/v1 document instead of the fork's own
// tier-group tables: every phase the preset names becomes a Pi agent entry,
// except "default" (Codex's main session, which Pi has no agent for) and
// renamed through piAgentForPhase the same way the fork does.
func familyPresetFill(family, preset string, document PresetsDocument) (map[string]AgentRouting, error) {
	prefix, ok := familyProviderPrefix[family]
	if !ok {
		return nil, validationErrorf("modelFamily %q is not a provider gentle-nix can fill Pi's routing from", family)
	}

	provider, ok := document.Providers[family]
	if !ok {
		return nil, validationErrorf("presets document has no %q provider", family)
	}
	phases, ok := provider.Presets[preset]
	if !ok {
		return nil, validationErrorf("unsupported %s model preset %q", family, preset)
	}

	routing := make(map[string]AgentRouting, len(phases))
	for phase, entry := range phases {
		if phase == "default" || phase == reservedPhaseKey {
			// Codex routes its main session under "default" and names its
			// orchestrator alongside the phases; Pi has no agent by either
			// name -- its orchestrator is the profile's own entry, not a
			// routed agent -- and inventing one would write an entry
			// gentle-pi discards.
			continue
		}

		agent := phase
		if renamed, ok := piAgentForPhase[phase]; ok {
			agent = renamed
		}

		thinking := entry.Effort
		if !ValidThinking(thinking) {
			thinking = ""
		}

		model := entry.Model
		if model != "" && !strings.Contains(model, "/") {
			model = prefix + model
		}

		routing[agent] = AgentRouting{Model: model, Thinking: thinking}
	}
	return routing, nil
}

// WriteTree writes Build(spec)'s result into tree: profiles.json and
// models.json under .pi/gentle-ai, and the orchestrator defaults merged into
// .pi/agent/settings.json. It runs before gentle-nix settings so a value
// declared through providers.pi.settings keeps winning over a routing
// default at the same key, the same way an operator's own setting always
// wins over what a profile or preset would have written.
func WriteTree(tree string, spec Spec, presets *PresetsDocument) error {
	result, err := Build(spec, presets)
	if err != nil {
		return err
	}

	gentleAIDir := filepath.Join(tree, ".pi", "gentle-ai")

	if result.ProfilesDocument != nil {
		if err := os.MkdirAll(gentleAIDir, 0o755); err != nil {
			return fmt.Errorf("create Pi gentle-ai directory: %w", err)
		}
		if err := os.WriteFile(filepath.Join(gentleAIDir, "profiles.json"), result.ProfilesDocument, 0o644); err != nil {
			return fmt.Errorf("write Pi agent profiles: %w", err)
		}
	}

	if result.ModelRouting != nil {
		encoded, err := json.MarshalIndent(result.ModelRouting, "", "  ")
		if err != nil {
			return fmt.Errorf("marshal Pi model routing: %w", err)
		}
		if err := os.MkdirAll(gentleAIDir, 0o755); err != nil {
			return fmt.Errorf("create Pi gentle-ai directory: %w", err)
		}
		if err := os.WriteFile(filepath.Join(gentleAIDir, "models.json"), append(encoded, '\n'), 0o644); err != nil {
			return fmt.Errorf("write Pi model routing: %w", err)
		}
	}

	if len(result.SettingsDefaults) > 0 {
		block, err := json.Marshal(result.SettingsDefaults)
		if err != nil {
			return fmt.Errorf("marshal Pi active profile defaults: %w", err)
		}
		settingsPath := filepath.Join(tree, ".pi", "agent", "settings.json")
		if err := settings.MergeInto(settingsPath, block); err != nil {
			return err
		}
	}

	return nil
}

// sortedKeys is a small helper kept for callers (and tests) that need
// deterministic iteration over a routing or profile map.
func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}
