package pimodels

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestValidateStructuralRules(t *testing.T) {
	tests := map[string]struct {
		spec    Spec
		wantErr bool
	}{
		"valid provider": {
			spec: Spec{Providers: map[string]map[string]any{
				"nan": {"baseUrl": "https://api.example.com/v1"},
			}},
		},
		"empty provider id": {
			spec:    Spec{Providers: map[string]map[string]any{"": {"baseUrl": "https://api.example.com/v1"}}},
			wantErr: true,
		},
		"null provider": {
			spec:    Spec{Providers: map[string]map[string]any{"nan": nil}},
			wantErr: true,
		},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			err := Validate(tt.spec)
			if tt.wantErr && err == nil {
				t.Fatalf("expected an error for %q", name)
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("unexpected error for %q: %v", name, err)
			}
		})
	}
}

// A provider whose value is not an object never reaches Validate: the spec's
// own shape is an object of objects, so encoding/json refuses it at decode
// time. The rejection has to stay at decode, not paper over it with `any`.
func TestDecodeRejectsNonObjectProvider(t *testing.T) {
	raw := `{"providers": {"nan": "https://api.example.com/v1"}}`
	var spec Spec
	if err := json.Unmarshal([]byte(raw), &spec); err == nil {
		t.Fatal("expected a non-object provider value to fail decoding")
	}
}

func TestWriteTreePassesProvidersThroughVerbatim(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{Providers: map[string]map[string]any{
		"nan": {
			"baseUrl": "https://api.example.com/v1",
			"api":     "openai-completions",
			"models": map[string]any{
				"deepseek-v4-flash": map[string]any{
					"name":          "DeepSeek V4 Flash",
					"contextWindow": float64(262144),
					"compat":        map[string]any{"reasoning": true},
				},
			},
		},
	}}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree: %v", err)
	}

	raw, err := os.ReadFile(filepath.Join(tree, ".pi", "agent", "models.json"))
	if err != nil {
		t.Fatalf("models.json missing: %v", err)
	}

	var document struct {
		Providers map[string]map[string]any `json:"providers"`
	}
	if err := json.Unmarshal(raw, &document); err != nil {
		t.Fatalf("models.json is not valid JSON: %v\n%s", err, raw)
	}
	if !reflect.DeepEqual(document.Providers, spec.Providers) {
		t.Fatalf("the declared provider did not survive verbatim:\n got %#v\nwant %#v", document.Providers, spec.Providers)
	}
	if !strings.HasSuffix(string(raw), "\n") {
		t.Fatal("models.json must end with a trailing newline")
	}
}

func TestWriteTreeRejectsAnEmptyProviderID(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{Providers: map[string]map[string]any{"": {"baseUrl": "https://api.example.com/v1"}}}
	if err := WriteTree(tree, spec); err == nil {
		t.Fatal("expected an error for an empty provider id")
	}
}

func TestWriteTreeWritesNothingForAnEmptySpec(t *testing.T) {
	tree := t.TempDir()
	if err := WriteTree(tree, Spec{}); err != nil {
		t.Fatalf("WriteTree: %v", err)
	}
	if _, err := os.Stat(filepath.Join(tree, ".pi")); err == nil {
		t.Fatal("expected no .pi directory for an empty spec")
	}
}
