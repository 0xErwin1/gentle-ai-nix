package pirouting

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func assignment(provider, model, effort string) *ModelAssignment {
	return &ModelAssignment{Provider: provider, Model: model, Effort: effort}
}

func TestValidateProfileNameRules(t *testing.T) {
	tests := map[string]struct {
		name    string
		wantErr bool
	}{
		"valid":                {"cheap-1.tier", false},
		"starts with dot":      {".cheap", true},
		"starts with dash":     {"-cheap", true},
		"too long":             {strings.Repeat("a", 65), true},
		"reserved proto":       {"__proto__", true},
		"reserved constructor": {"constructor", true},
		"reserved prototype":   {"prototype", true},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			spec := Spec{Profiles: map[string]Profile{tt.name: {}}}
			err := Validate(spec)
			if tt.wantErr && err == nil {
				t.Fatalf("expected an error for profile name %q", tt.name)
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("unexpected error for profile name %q: %v", tt.name, err)
			}
		})
	}
}

func TestValidateNoPhaseNamedOrchestrator(t *testing.T) {
	spec := Spec{
		Profiles: map[string]Profile{
			"cheap": {
				PhaseAssignments: map[string]ModelAssignment{
					"orchestrator": {Provider: "anthropic", Model: "claude-haiku"},
				},
			},
		},
	}
	if err := Validate(spec); err == nil {
		t.Fatal("expected an error for a phase literally named orchestrator")
	}
}

func TestValidateAssignmentRequiresProviderAndModel(t *testing.T) {
	tests := []ModelAssignment{
		{Provider: "", Model: "claude-haiku"},
		{Provider: "anthropic", Model: ""},
	}
	for _, a := range tests {
		spec := Spec{Profiles: map[string]Profile{"cheap": {Orchestrator: &a}}}
		if err := Validate(spec); err == nil {
			t.Fatalf("expected an error for incomplete assignment %+v", a)
		}
	}
}

func TestValidateThinkingLevelEnumForModels(t *testing.T) {
	spec := Spec{Models: map[string]AgentRouting{"sdd-apply": {Thinking: "extreme"}}}
	if err := Validate(spec); err == nil {
		t.Fatal("expected an error for an unsupported reasoning level")
	}

	spec = Spec{Models: map[string]AgentRouting{"sdd-apply": {Thinking: "high"}}}
	if err := Validate(spec); err != nil {
		t.Fatalf("unexpected error for a valid reasoning level: %v", err)
	}
}

func TestValidateThinkingLevelEnumForProfileAssignments(t *testing.T) {
	spec := Spec{
		Profiles: map[string]Profile{
			"cheap": {Orchestrator: assignment("anthropic", "claude-haiku", "extreme")},
		},
	}
	if err := Validate(spec); err == nil {
		t.Fatal("expected an error for an unsupported profile effort")
	}
}

func TestValidateActiveProfileMustBeDeclared(t *testing.T) {
	spec := Spec{ActiveProfile: "missing"}
	if err := Validate(spec); err == nil {
		t.Fatal("expected an error for an undeclared active profile")
	}

	spec = Spec{
		ActiveProfile: "cheap",
		Profiles:      map[string]Profile{"cheap": {}},
	}
	if err := Validate(spec); err != nil {
		t.Fatalf("unexpected error for a declared active profile: %v", err)
	}
}

func TestValidateModelPresetRequiresModelFamily(t *testing.T) {
	spec := Spec{ModelPreset: "recommended"}
	if err := Validate(spec); err == nil {
		t.Fatal("expected an error for modelPreset without modelFamily")
	}
}

func TestValidateUnknownModelFamily(t *testing.T) {
	spec := Spec{ModelFamily: "gemini-cli"}
	if err := Validate(spec); err == nil {
		t.Fatal("expected an error for an unsupported model family")
	}
}

func fixturePresets() PresetsDocument {
	return PresetsDocument{
		Schema: "gentle-ai.model-presets/v1",
		Providers: map[string]presetsProviderEntry{
			"codex": {
				Presets: map[string]map[string]presetPhaseEntry{
					"recommended": {
						"default":      {Model: "gpt-5.6-sol", Effort: "medium"},
						"orchestrator": {Model: "gpt-5.6-sol", Effort: "medium"},
						"sdd-explore":  {Model: "gpt-5.6-sol", Effort: "medium"},
						"sdd-propose":  {Model: "gpt-5.6-sol", Effort: "medium"},
						"sdd-apply":    {Model: "gpt-5.6-terra", Effort: "high"},
						"sdd-spec":     {Model: "gpt-5.6-luna", Effort: "high"},
					},
				},
			},
		},
	}
}

func TestBuildFamilyPresetFillAgentSetAndProviderPrefix(t *testing.T) {
	presets := fixturePresets()
	spec := Spec{ModelFamily: "codex", ModelPreset: "recommended"}

	result, err := Build(spec, &presets)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}

	if _, ok := result.ModelRouting["orchestrator"]; ok {
		t.Fatalf("the preset's orchestrator entry must not become a routed Pi agent")
	}
	if _, ok := result.ModelRouting["default"]; ok {
		t.Fatal("the family fill must skip the \"default\" phase, Pi has no such agent")
	}
	if _, ok := result.ModelRouting["sdd-propose"]; ok {
		t.Fatal("sdd-propose must be renamed to sdd-proposal")
	}
	proposal, ok := result.ModelRouting["sdd-proposal"]
	if !ok {
		t.Fatal("sdd-propose was not renamed to sdd-proposal")
	}
	if proposal.Model != "openai-codex/gpt-5.6-sol" {
		t.Fatalf("model = %q, want openai-codex/gpt-5.6-sol prefix", proposal.Model)
	}
	if proposal.Thinking != "medium" {
		t.Fatalf("thinking = %q, want medium", proposal.Thinking)
	}

	apply, ok := result.ModelRouting["sdd-apply"]
	if !ok || apply.Model != "openai-codex/gpt-5.6-terra" || apply.Thinking != "high" {
		t.Fatalf("sdd-apply routing = %+v", apply)
	}
}

func TestBuildUnknownPresetNameIsAnError(t *testing.T) {
	presets := fixturePresets()
	spec := Spec{ModelFamily: "codex", ModelPreset: "does-not-exist"}
	if _, err := Build(spec, &presets); err == nil {
		t.Fatal("expected an error for an unknown preset name")
	}
}

func TestBuildMissingPresetsDocumentIsAnError(t *testing.T) {
	spec := Spec{ModelFamily: "codex", ModelPreset: "recommended"}
	if _, err := Build(spec, nil); err == nil {
		t.Fatal("expected an error when modelFamily/modelPreset are set but no presets document was given")
	}
}

func TestBuildPrecedenceExplicitOverProfileOverFamilyFill(t *testing.T) {
	presets := fixturePresets()
	spec := Spec{
		ModelFamily:   "codex",
		ModelPreset:   "recommended",
		ActiveProfile: "cheap",
		Profiles: map[string]Profile{
			"cheap": {
				Orchestrator: assignment("anthropic", "claude-haiku", "low"),
				PhaseAssignments: map[string]ModelAssignment{
					"sdd-apply": {Provider: "anthropic", Model: "claude-sonnet-5", Effort: "medium"},
				},
			},
		},
		Models: map[string]AgentRouting{
			"sdd-apply": {Thinking: "xhigh"},
		},
	}

	result, err := Build(spec, &presets)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}

	// The explicit model wins over both the profile and the family fill.
	if got := result.ModelRouting["sdd-apply"]; got != (AgentRouting{Thinking: "xhigh"}) {
		t.Fatalf("sdd-apply = %+v, want the explicit model to win", got)
	}

	// The profile's orchestrator wins over nothing else naming it, and
	// lands under the reserved key.
	if got := result.ModelRouting["orchestrator"]; got.Model != "anthropic/claude-haiku" || got.Thinking != "low" {
		t.Fatalf("orchestrator = %+v", got)
	}

	// A phase the profile and explicit models both leave alone still gets
	// the family fill.
	if got := result.ModelRouting["sdd-explore"]; got.Model != "openai-codex/gpt-5.6-sol" {
		t.Fatalf("sdd-explore = %+v, want the family fill to apply", got)
	}

	if result.SettingsDefaults["defaultProvider"] != "anthropic" ||
		result.SettingsDefaults["defaultModel"] != "claude-haiku" ||
		result.SettingsDefaults["defaultThinkingLevel"] != "low" {
		t.Fatalf("SettingsDefaults = %+v", result.SettingsDefaults)
	}
}

func TestBuildProfilesDocumentFormat(t *testing.T) {
	spec := Spec{
		ActiveProfile: "cheap",
		Profiles: map[string]Profile{
			"cheap": {
				Orchestrator: assignment("anthropic", "claude-haiku", ""),
				PhaseAssignments: map[string]ModelAssignment{
					"sdd-apply": {Provider: "anthropic", Model: "claude-sonnet-5", Effort: "medium"},
				},
			},
		},
	}

	result, err := Build(spec, nil)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}

	var document map[string]any
	if err := json.Unmarshal(result.ProfilesDocument, &document); err != nil {
		t.Fatalf("profiles.json is not valid JSON: %v\n%s", err, result.ProfilesDocument)
	}

	if document["kind"] != profilesKind {
		t.Fatalf("kind = %v, want %q", document["kind"], profilesKind)
	}
	if document["version"] != float64(1) {
		t.Fatalf("version = %v, want 1", document["version"])
	}
	if document["active"] != "cheap" {
		t.Fatalf("active = %v, want cheap", document["active"])
	}

	profiles := document["profiles"].(map[string]any)
	cheap := profiles["cheap"].(map[string]any)
	orchestrator := cheap["orchestrator"].(map[string]any)
	if orchestrator["model"] != "anthropic/claude-haiku" {
		t.Fatalf("orchestrator.model = %v", orchestrator["model"])
	}
	if _, hasThinking := orchestrator["thinking"]; hasThinking {
		t.Fatal("thinking must be omitted when the effort is empty")
	}

	apply := cheap["sdd-apply"].(map[string]any)
	if apply["thinking"] != "medium" {
		t.Fatalf("sdd-apply.thinking = %v, want medium", apply["thinking"])
	}

	if !strings.HasSuffix(string(result.ProfilesDocument), "\n") {
		t.Fatal("profiles.json must end with a trailing newline")
	}
}

func TestBuildWritesNothingForAnEmptySpec(t *testing.T) {
	result, err := Build(Spec{}, nil)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if result.ProfilesDocument != nil || result.ModelRouting != nil || result.SettingsDefaults != nil {
		t.Fatalf("expected an empty result, got %+v", result)
	}
}

func TestDecodePresetsAcceptsEmbeddedDocument(t *testing.T) {
	embedded, err := json.Marshal(fixturePresets())
	if err != nil {
		t.Fatal(err)
	}
	document, err := DecodePresets(embedded)
	if err != nil {
		t.Fatalf("DecodePresets: %v", err)
	}
	if document.Schema != "gentle-ai.model-presets/v1" {
		t.Fatalf("schema = %q", document.Schema)
	}
}

func TestDecodePresetsAcceptsPathToDocument(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "presets.json")
	encoded, err := json.Marshal(fixturePresets())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, encoded, 0o644); err != nil {
		t.Fatal(err)
	}

	quotedPath, err := json.Marshal(path)
	if err != nil {
		t.Fatal(err)
	}

	document, err := DecodePresets(quotedPath)
	if err != nil {
		t.Fatalf("DecodePresets: %v", err)
	}
	if document.Schema != "gentle-ai.model-presets/v1" {
		t.Fatalf("schema = %q", document.Schema)
	}
}

func TestWriteTreeWritesExpectedFiles(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		ActiveProfile: "cheap",
		Profiles: map[string]Profile{
			"cheap": {
				Orchestrator: assignment("anthropic", "claude-haiku", "low"),
			},
		},
		Models: map[string]AgentRouting{
			"sdd-verify": {Thinking: "high"},
		},
	}

	if err := WriteTree(tree, spec, nil); err != nil {
		t.Fatalf("WriteTree: %v", err)
	}

	profilesPath := filepath.Join(tree, ".pi", "gentle-ai", "profiles.json")
	if _, err := os.Stat(profilesPath); err != nil {
		t.Fatalf("profiles.json missing: %v", err)
	}

	modelsPath := filepath.Join(tree, ".pi", "gentle-ai", "models.json")
	modelsRaw, err := os.ReadFile(modelsPath)
	if err != nil {
		t.Fatalf("models.json missing: %v", err)
	}
	var models map[string]AgentRouting
	if err := json.Unmarshal(modelsRaw, &models); err != nil {
		t.Fatalf("models.json is not valid JSON: %v", err)
	}
	if models["sdd-verify"].Thinking != "high" {
		t.Fatalf("sdd-verify = %+v", models["sdd-verify"])
	}
	if models["orchestrator"].Model != "anthropic/claude-haiku" {
		t.Fatalf("orchestrator = %+v", models["orchestrator"])
	}

	settingsPath := filepath.Join(tree, ".pi", "agent", "settings.json")
	settingsRaw, err := os.ReadFile(settingsPath)
	if err != nil {
		t.Fatalf("settings.json missing: %v", err)
	}
	var settings map[string]any
	if err := json.Unmarshal(settingsRaw, &settings); err != nil {
		t.Fatalf("settings.json is not valid JSON: %v", err)
	}
	if settings["defaultProvider"] != "anthropic" || settings["defaultModel"] != "claude-haiku" || settings["defaultThinkingLevel"] != "low" {
		t.Fatalf("settings = %v", settings)
	}
}

func TestWriteTreePreservesAnExistingSettingsValue(t *testing.T) {
	tree := t.TempDir()
	settingsPath := filepath.Join(tree, ".pi", "agent", "settings.json")
	if err := os.MkdirAll(filepath.Dir(settingsPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(settingsPath, []byte(`{"defaultProvider":"declared-by-provider-settings","keepMe":true}`), 0o644); err != nil {
		t.Fatal(err)
	}

	spec := Spec{
		ActiveProfile: "cheap",
		Profiles: map[string]Profile{
			"cheap": {Orchestrator: assignment("anthropic", "claude-haiku", "low")},
		},
	}

	// WriteTree merges rather than overwrites, so a value written by a step
	// that runs after it (gentle-nix settings, from providers.pi.settings)
	// keeps its later write winning; here we assert WriteTree itself never
	// clobbers an existing key it did not come to set, which is what makes
	// running it before gentle-nix settings safe.
	if err := WriteTree(tree, spec, nil); err != nil {
		t.Fatalf("WriteTree: %v", err)
	}

	raw, err := os.ReadFile(settingsPath)
	if err != nil {
		t.Fatal(err)
	}
	var settings map[string]any
	if err := json.Unmarshal(raw, &settings); err != nil {
		t.Fatal(err)
	}
	if settings["keepMe"] != true {
		t.Fatalf("an untouched key was dropped: %v", settings)
	}
}

func TestWriteTreeWritesNothingForAnEmptySpec(t *testing.T) {
	tree := t.TempDir()
	if err := WriteTree(tree, Spec{}, nil); err != nil {
		t.Fatalf("WriteTree: %v", err)
	}
	if _, err := os.Stat(filepath.Join(tree, ".pi")); err == nil {
		t.Fatal("expected no .pi directory for an empty spec")
	}
}
