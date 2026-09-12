// Package settings ports the one piece of the pinned Gentle AI fork's
// stageDeclaredExtensions/mergeExtensionBlock (internal/cli/config_stager.go)
// that gentle-nix now has to do itself: deep-merging a provider's declared
// settings block into that client's own settings file inside the rendered
// tree, now that the document no longer carries providers.<name>.settings
// as `extensions`.
package settings

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
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

func TestResolvePathKnownProviders(t *testing.T) {
	tree := t.TempDir()
	tests := map[string]string{
		"claude-code": ".claude/settings.json",
		"pi":          ".pi/agent/settings.json",
		"gemini-cli":  ".gemini/settings.json",
		"cursor":      ".cursor/settings.json",
		"qwen-code":   ".qwen/settings.json",
		"kilocode":    ".config/kilo/opencode.json",
		"openclaw":    ".config/openclaw/openclaw.json",
	}
	for provider, rel := range tests {
		path, ok := ResolvePath(tree, provider)
		if !ok {
			t.Fatalf("ResolvePath(%q): not found", provider)
		}
		want := filepath.Join(tree, rel)
		if path != want {
			t.Fatalf("ResolvePath(%q) = %q, want %q", provider, path, want)
		}
	}
}

func TestResolvePathUnknownProvider(t *testing.T) {
	if _, ok := ResolvePath(t.TempDir(), "not-a-real-provider"); ok {
		t.Fatal("expected an unknown provider to report ok=false")
	}
}

func TestResolvePathOpenCodePrefersExistingJsonc(t *testing.T) {
	tree := t.TempDir()

	// With neither file present, opencode.json is the target -- a fresh
	// write always lands in the plain-JSON form.
	path, ok := ResolvePath(tree, "opencode")
	if !ok || path != filepath.Join(tree, ".config/opencode/opencode.json") {
		t.Fatalf("ResolvePath(opencode) with no existing file = %q, %v", path, ok)
	}

	writeFile(t, filepath.Join(tree, ".config/opencode/opencode.jsonc"), "{}")

	path, ok = ResolvePath(tree, "opencode")
	if !ok || path != filepath.Join(tree, ".config/opencode/opencode.jsonc") {
		t.Fatalf("ResolvePath(opencode) with an existing opencode.jsonc = %q, %v", path, ok)
	}
}

func TestKnownProvidersDoesNotIncludeTomlOrUnmodeledClients(t *testing.T) {
	for _, unsupported := range []string{"codex", "kimi", "hermes", "vscode-copilot", "antigravity", "windsurf", "trae-ide", "kiro-ide"} {
		if _, ok := ResolvePath(t.TempDir(), unsupported); ok {
			t.Fatalf("%s should not be a Go-mergeable JSON settings path (routed through gentle-ai-merge instead)", unsupported)
		}
	}
}

func TestMergeIntoCreatesFileWhenAbsent(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "nested", "settings.json")

	if err := MergeInto(target, []byte(`{"a":"b"}`)); err != nil {
		t.Fatalf("MergeInto: %v", err)
	}

	raw, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != "{\n  \"a\": \"b\"\n}\n" {
		t.Fatalf("unexpected content: %q", raw)
	}
}

func TestMergeIntoMergesNestedObjectsReplacesListsDeclaredWins(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "settings.json")
	writeFile(t, target, `{
  "oauthAccount": {"id": "me"},
  "nested": {"providerOnly": "keep", "shared": "client", "list": ["client-item"]},
  "providerOnly": "provider-only"
}`)

	err := MergeInto(target, []byte(`{
  "nested": {"shared": "provider", "list": ["provider-list"]}
}`))
	if err != nil {
		t.Fatalf("MergeInto: %v", err)
	}

	raw, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("merged file is not valid JSON: %v\n%s", err, raw)
	}

	if got["oauthAccount"].(map[string]any)["id"] != "me" {
		t.Fatalf("the merge dropped the client's own state: %v", got)
	}
	if got["providerOnly"] != "provider-only" {
		t.Fatalf("the merge dropped an untouched top-level key: %v", got)
	}
	nested := got["nested"].(map[string]any)
	if nested["providerOnly"] != "keep" {
		t.Fatalf("the merge dropped a nested key the overlay never mentioned: %v", nested)
	}
	if nested["shared"] != "provider" {
		t.Fatalf("the declared value did not win at a shared leaf: %v", nested)
	}
	list, ok := nested["list"].([]any)
	if !ok || len(list) != 1 || list[0] != "provider-list" {
		t.Fatalf("a list was not replaced wholesale: %v", nested["list"])
	}
}

func TestMergeIntoIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "settings.json")
	block := []byte(`{"a": {"b": "c"}}`)

	if err := MergeInto(target, block); err != nil {
		t.Fatal(err)
	}
	once, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}

	if err := MergeInto(target, block); err != nil {
		t.Fatal(err)
	}
	twice, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}

	if string(once) != string(twice) {
		t.Fatalf("merging the same block twice changed the file:\nonce: %s\ntwice: %s", once, twice)
	}
}

func TestMergeIntoRejectsInvalidOverlayJSON(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "settings.json")
	if err := MergeInto(target, []byte("not json")); err == nil {
		t.Fatal("expected an error for invalid overlay JSON")
	}
}

func TestMergeIntoToleratesAnUnparsableExistingFile(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "settings.json")
	writeFile(t, target, "not json at all")

	if err := MergeInto(target, []byte(`{"a":"b"}`)); err != nil {
		t.Fatalf("MergeInto: %v", err)
	}

	var got map[string]any
	raw, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("result is not valid JSON: %v", err)
	}
	if got["a"] != "b" {
		t.Fatalf("the declared block was not written: %v", got)
	}
}

func TestRunMergesEachDeclaredProviderIntoItsOwnFile(t *testing.T) {
	tree := t.TempDir()
	claudeBlock := filepath.Join(t.TempDir(), "claude.json")
	writeFile(t, claudeBlock, `{"providerOnly": "provider-only"}`)
	opencodeBlock := filepath.Join(t.TempDir(), "opencode.json")
	writeFile(t, opencodeBlock, `{"providerOnly": "other-provider"}`)

	code, err := Run(Options{
		Tree: tree,
		Providers: []ProviderBlock{
			{Name: "claude-code", BlockPath: claudeBlock},
			{Name: "opencode", BlockPath: opencodeBlock},
		},
	})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if code != 0 {
		t.Fatalf("code = %d, want 0", code)
	}

	claudeSettings, err := os.ReadFile(filepath.Join(tree, ".claude", "settings.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(claudeSettings), `"provider-only"`) {
		t.Fatalf("claude-code settings missing the declared value: %s", claudeSettings)
	}

	opencodeSettings, err := os.ReadFile(filepath.Join(tree, ".config", "opencode", "opencode.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(opencodeSettings), `"other-provider"`) {
		t.Fatalf("opencode settings missing the declared value: %s", opencodeSettings)
	}
}

func TestMergeIntoReplaceSentinelReplacesNestedObjectWholesale(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "settings.json")
	writeFile(t, target, `{"agent":{"worker":{"tools":{"bash":true},"kept":"value"}}}`)

	err := MergeInto(target, []byte(`{"agent":{"worker":{"tools":{"__replace__":{"read":true}}}}}`))
	if err != nil {
		t.Fatalf("MergeInto: %v", err)
	}

	raw, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("merged file is not valid JSON: %v\n%s", err, raw)
	}

	worker := got["agent"].(map[string]any)["worker"].(map[string]any)
	if worker["kept"] != "value" {
		t.Fatalf("the merge dropped an untouched sibling key: %v", worker)
	}
	tools, ok := worker["tools"].(map[string]any)
	if !ok {
		t.Fatalf("tools was not written: %v", worker)
	}
	if _, stale := tools["bash"]; stale {
		t.Fatalf("tools = %v, want the stale entry replaced rather than merged", tools)
	}
	if tools["read"] != true {
		t.Fatalf("tools = %v, want the declared entry present", tools)
	}
	if _, sentinelLeaked := tools[ReplaceSentinel]; sentinelLeaked {
		t.Fatalf("tools = %v, want the sentinel unwrapped rather than written verbatim", tools)
	}
}

func TestMergeIntoReplaceSentinelWorksWithNoBaseValue(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "settings.json")
	writeFile(t, target, `{}`)

	err := MergeInto(target, []byte(`{"agent":{"worker":{"tools":{"__replace__":{"read":true}}}}}`))
	if err != nil {
		t.Fatalf("MergeInto: %v", err)
	}

	raw, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("merged file is not valid JSON: %v\n%s", err, raw)
	}
	tools := got["agent"].(map[string]any)["worker"].(map[string]any)["tools"].(map[string]any)
	if tools["read"] != true {
		t.Fatalf("tools = %v, want the declared entry present", tools)
	}
}

func TestRunRejectsAnUnknownProvider(t *testing.T) {
	tree := t.TempDir()
	blockPath := filepath.Join(t.TempDir(), "block.json")
	writeFile(t, blockPath, `{}`)

	code, err := Run(Options{
		Tree:      tree,
		Providers: []ProviderBlock{{Name: "not-a-real-provider", BlockPath: blockPath}},
	})
	if err == nil {
		t.Fatal("expected an error for an unknown provider")
	}
	if code != 2 {
		t.Fatalf("code = %d, want 2", code)
	}
}
