package permissions

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readSettings(t *testing.T, path string) map[string]any {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var value map[string]any
	if err := json.Unmarshal(raw, &value); err != nil {
		t.Fatal(err)
	}
	return value
}

func stringSlice(t *testing.T, value any) []string {
	t.Helper()
	if value == nil {
		return nil
	}
	raw, ok := value.([]any)
	if !ok {
		t.Fatalf("expected a list, got %T", value)
	}
	out := make([]string, len(raw))
	for i, v := range raw {
		out[i] = v.(string)
	}
	return out
}

func TestRenderNoopWithoutClaudeCodeAgent(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"opencode"},
		Deny:   []string{"Bash(rm -rf /)"},
	}

	if err := Render(tree, spec); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(filepath.Join(tree, ".claude", "settings.json")); !os.IsNotExist(err) {
		t.Fatalf(".claude/settings.json should not have been written, stat err = %v", err)
	}
}

func TestRenderNoopWithNoRules(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{Agents: []string{"claude-code"}}

	if err := Render(tree, spec); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(filepath.Join(tree, ".claude", "settings.json")); !os.IsNotExist(err) {
		t.Fatalf(".claude/settings.json should not have been written, stat err = %v", err)
	}
}

func TestRenderUnionsWithShippedOverlay(t *testing.T) {
	tree := t.TempDir()
	settingsPath := filepath.Join(tree, ".claude", "settings.json")
	writeFile(t, settingsPath, `{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "deny": ["Read(.env)", "Edit(.env)"]
  }
}`)

	spec := Spec{
		Agents: []string{"claude-code"},
		Allow:  []string{"Bash(git *)"},
		Deny:   []string{"Read(.env)", "Read(.ssh/*)"},
		Ask:    []string{"Bash(rm *)"},
	}

	if err := Render(tree, spec); err != nil {
		t.Fatal(err)
	}

	written := readSettings(t, settingsPath)
	permissions, ok := written["permissions"].(map[string]any)
	if !ok {
		t.Fatalf("permissions key missing or not an object: %#v", written)
	}

	if got := permissions["defaultMode"]; got != "bypassPermissions" {
		t.Fatalf("defaultMode = %v, want it preserved from the overlay", got)
	}

	wantDeny := []string{"Read(.env)", "Edit(.env)", "Read(.ssh/*)"}
	if got := stringSlice(t, permissions["deny"]); !equalStrings(got, wantDeny) {
		t.Fatalf("deny = %v, want %v (existing entries first, declared appended, deduped)", got, wantDeny)
	}

	wantAllow := []string{"Bash(git *)"}
	if got := stringSlice(t, permissions["allow"]); !equalStrings(got, wantAllow) {
		t.Fatalf("allow = %v, want %v", got, wantAllow)
	}

	wantAsk := []string{"Bash(rm *)"}
	if got := stringSlice(t, permissions["ask"]); !equalStrings(got, wantAsk) {
		t.Fatalf("ask = %v, want %v", got, wantAsk)
	}
}

func TestRenderCreatesSettingsFileWhenAbsent(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"claude-code"},
		Allow:  []string{"Bash(git *)"},
	}

	if err := Render(tree, spec); err != nil {
		t.Fatal(err)
	}

	written := readSettings(t, filepath.Join(tree, ".claude", "settings.json"))
	permissions := written["permissions"].(map[string]any)
	if got := stringSlice(t, permissions["allow"]); !equalStrings(got, []string{"Bash(git *)"}) {
		t.Fatalf("allow = %v, want [Bash(git *)]", got)
	}
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
