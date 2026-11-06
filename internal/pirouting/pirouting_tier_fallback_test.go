package pirouting

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBuildCarriesTierIntoProfilesAndRouting(t *testing.T) {
	orchestrator := assignment("openai", "gpt-5.6-codex", "high")
	orchestrator.Tier = "fast"
	spec := Spec{
		ActiveProfile: "quick",
		Profiles: map[string]Profile{
			"quick": {
				Orchestrator: orchestrator,
				PhaseAssignments: map[string]ModelAssignment{
					"sdd-apply": {Provider: "openai", Model: "gpt-5.6", Tier: "standard"},
				},
			},
		},
		Models: map[string]AgentRouting{
			"sdd-verify": {Model: "openai/gpt-5.6", Tier: "fast"},
		},
	}

	result, err := Build(spec, nil)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}

	var document struct {
		Profiles map[string]map[string]map[string]any `json:"profiles"`
	}
	if err := json.Unmarshal(result.ProfilesDocument, &document); err != nil {
		t.Fatalf("profiles.json is not valid JSON: %v", err)
	}
	quick := document.Profiles["quick"]
	if quick["orchestrator"]["tier"] != "fast" {
		t.Fatalf("orchestrator.tier = %v, want fast", quick["orchestrator"]["tier"])
	}
	if quick["sdd-apply"]["tier"] != "standard" {
		t.Fatalf("sdd-apply.tier = %v, want standard", quick["sdd-apply"]["tier"])
	}

	if got := result.ModelRouting["orchestrator"].Tier; got != "fast" {
		t.Fatalf("models.json orchestrator tier = %q, want fast", got)
	}
	if got := result.ModelRouting["sdd-verify"].Tier; got != "fast" {
		t.Fatalf("models.json sdd-verify tier = %q, want fast", got)
	}
	if _, settingsTier := result.SettingsDefaults["tier"]; settingsTier {
		t.Fatal("tier has no settings.json key and must not be merged there")
	}
}

func TestBuildOmitsTierWhenUnset(t *testing.T) {
	spec := Spec{
		Profiles: map[string]Profile{"cheap": {Orchestrator: assignment("anthropic", "claude-haiku", "")}},
	}
	result, err := Build(spec, nil)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if strings.Contains(string(result.ProfilesDocument), "tier") {
		t.Fatalf("an unset tier must be omitted:\n%s", result.ProfilesDocument)
	}
}

func TestValidateRejectsUnknownTier(t *testing.T) {
	cases := map[string]Spec{
		"models": {Models: map[string]AgentRouting{"sdd-apply": {Tier: "turbo"}}},
		"assignment": {Profiles: map[string]Profile{"cheap": {
			Orchestrator: &ModelAssignment{Provider: "openai", Model: "gpt-5.6", Tier: "priority"},
		}}},
	}
	for name, spec := range cases {
		t.Run(name, func(t *testing.T) {
			err := Validate(spec)
			if err == nil || !strings.Contains(err.Error(), "unsupported tier") {
				t.Fatalf("Validate = %v, want an unsupported tier error", err)
			}
			if _, ok := err.(ValidationError); !ok {
				t.Fatalf("error %T is not a ValidationError", err)
			}
		})
	}
}

func TestBuildFallbacksDocumentFormat(t *testing.T) {
	spec := Spec{
		Profiles: map[string]Profile{
			"daily": {
				Orchestrator: assignment("anthropic", "claude-opus-5-5", "high"),
				Fallbacks: map[string][]ModelAssignment{
					"orchestrator": {
						{Provider: "openai", Model: "gpt-5.6", Effort: "high"},
						{Provider: "anthropic", Model: "claude-sonnet-5-5"},
					},
					"*": {{Provider: "openai", Model: "gpt-5.6-mini"}},
				},
			},
			"plain": {Orchestrator: assignment("anthropic", "claude-haiku", "")},
		},
	}

	result, err := Build(spec, nil)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if strings.Contains(string(result.ProfilesDocument), "openai/gpt-5.6") {
		t.Fatal("fallback chains belong in profile-fallbacks.json, never in profiles.json")
	}

	want := `{
  "kind": "gentle-pi.profile_model_fallbacks",
  "version": 1,
  "profiles": {
    "daily": {
      "*": [
        {
          "model": "openai/gpt-5.6-mini"
        }
      ],
      "orchestrator": [
        {
          "model": "openai/gpt-5.6",
          "thinking": "high"
        },
        {
          "model": "anthropic/claude-sonnet-5-5"
        }
      ]
    }
  }
}
`
	if got := string(result.FallbacksDocument); got != want {
		t.Fatalf("profile-fallbacks.json =\n%s\nwant\n%s", got, want)
	}
}

func TestBuildWritesNoFallbacksDocumentWithoutChains(t *testing.T) {
	spec := Spec{Profiles: map[string]Profile{"cheap": {Orchestrator: assignment("anthropic", "claude-haiku", "")}}}
	result, err := Build(spec, nil)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if result.FallbacksDocument != nil {
		t.Fatalf("expected no fallbacks document, got:\n%s", result.FallbacksDocument)
	}
}

func TestValidateFallbackChains(t *testing.T) {
	step := func(provider, model string) ModelAssignment { return ModelAssignment{Provider: provider, Model: model} }
	tooLong := make([]ModelAssignment, 0, 9)
	for i := range 9 {
		tooLong = append(tooLong, step("openai", "gpt-"+string(rune('a'+i))))
	}
	cases := map[string]struct {
		chains map[string][]ModelAssignment
		want   string
	}{
		"tier on a step": {
			chains: map[string][]ModelAssignment{"*": {{Provider: "openai", Model: "gpt-5.6", Tier: "fast"}}},
			want:   "a fallback step takes no tier",
		},
		"incomplete step": {
			chains: map[string][]ModelAssignment{"*": {{Model: "gpt-5.6"}}},
			want:   "requires both provider and model",
		},
		"bad effort": {
			chains: map[string][]ModelAssignment{"*": {{Provider: "openai", Model: "gpt-5.6", Effort: "huge"}}},
			want:   "unsupported reasoning level",
		},
		"unsafe model id": {
			chains: map[string][]ModelAssignment{"*": {step("openai", "gpt 5")}},
			want:   "not a model id gentle-pi accepts",
		},
		"too long": {
			chains: map[string][]ModelAssignment{"*": tooLong},
			want:   "at most 8 steps",
		},
		"duplicate model": {
			chains: map[string][]ModelAssignment{"*": {step("openai", "gpt-5.6"), step("openai", "gpt-5.6")}},
			want:   "appears more than once",
		},
		"bad agent key": {
			chains: map[string][]ModelAssignment{"sdd apply": {step("openai", "gpt-5.6")}},
			want:   "invalid agent name",
		},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			err := Validate(Spec{Profiles: map[string]Profile{"daily": {Fallbacks: tc.chains}}})
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("Validate = %v, want an error containing %q", err, tc.want)
			}
			if !strings.Contains(err.Error(), "profiles.daily.fallbacks.") {
				t.Fatalf("error %q does not name the failing path", err)
			}
			if _, ok := err.(ValidationError); !ok {
				t.Fatalf("error %T is not a ValidationError", err)
			}
		})
	}
}

func TestWriteTreeWritesFallbacksDocument(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Profiles: map[string]Profile{
			"daily": {Fallbacks: map[string][]ModelAssignment{"*": {{Provider: "openai", Model: "gpt-5.6"}}}},
		},
	}
	if err := WriteTree(tree, spec, nil); err != nil {
		t.Fatalf("WriteTree: %v", err)
	}
	content, err := os.ReadFile(filepath.Join(tree, ".pi", "gentle-ai", "profile-fallbacks.json"))
	if err != nil {
		t.Fatalf("profile-fallbacks.json was not written: %v", err)
	}
	if !strings.Contains(string(content), `"kind": "gentle-pi.profile_model_fallbacks"`) {
		t.Fatalf("unexpected profile-fallbacks.json:\n%s", content)
	}
}

func TestBuildRenamesFallbackPhaseKeysToPiAgents(t *testing.T) {
	spec := Spec{Profiles: map[string]Profile{"daily": {Fallbacks: map[string][]ModelAssignment{
		"sdd-propose": {{Provider: "openai", Model: "gpt-5.6"}},
	}}}}
	result, err := Build(spec, nil)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if !strings.Contains(string(result.FallbacksDocument), `"sdd-proposal": [`) || strings.Contains(string(result.FallbacksDocument), `"sdd-propose":`) {
		t.Fatalf("sdd-propose must be written under gentle-pi's sdd-proposal agent:\n%s", result.FallbacksDocument)
	}
}

func TestValidateRejectsFallbackKeysNamingTheSameAgent(t *testing.T) {
	step := []ModelAssignment{{Provider: "openai", Model: "gpt-5.6"}}
	err := Validate(Spec{Profiles: map[string]Profile{"daily": {Fallbacks: map[string][]ModelAssignment{
		"sdd-propose": step, "sdd-proposal": step,
	}}}})
	if err == nil || !strings.Contains(err.Error(), "same gentle-pi agent") {
		t.Fatalf("Validate = %v, want a same-agent collision error", err)
	}
}
