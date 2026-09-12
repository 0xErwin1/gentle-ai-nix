package mcp

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func boolPtr(b bool) *bool { return &b }

func TestValidateRejectsServerWithNeitherCommandNorURL(t *testing.T) {
	spec := Spec{
		Agents:  []string{"claude-code"},
		Servers: map[string]Server{"atlas": {}},
	}

	err := Validate(spec)
	if err == nil {
		t.Fatal("Validate() error = nil, want a command/url error")
	}
	if _, ok := err.(ValidationError); !ok {
		t.Errorf("Validate() error type = %T, want ValidationError", err)
	}
}

func TestValidateRejectsServerWithBothCommandAndURL(t *testing.T) {
	spec := Spec{
		Agents: []string{"claude-code"},
		Servers: map[string]Server{
			"atlas": {Command: "atlas", URL: "https://example.com"},
		},
	}

	if err := Validate(spec); err == nil {
		t.Fatal("Validate() error = nil, want a command/url error")
	}
}

func TestValidateRejectsEmptyServerName(t *testing.T) {
	spec := Spec{
		Agents:  []string{"claude-code"},
		Servers: map[string]Server{"": {Command: "atlas"}},
	}

	if err := Validate(spec); err == nil {
		t.Fatal("Validate() error = nil, want an empty-name error")
	}
}

func TestValidateRejectsAnAdapterThatCannotExpressMCP(t *testing.T) {
	spec := Spec{
		Agents:  []string{"claude-code", "hermes"},
		Servers: map[string]Server{"atlas": {Command: "atlas"}},
	}

	err := Validate(spec)
	if err == nil {
		t.Fatal("Validate() error = nil, want hermes refused")
	}
	if !strings.Contains(err.Error(), "hermes") {
		t.Errorf("Validate() error = %v, want it to name hermes", err)
	}
}

func TestValidateAllowsAnAdapterWithNoServersDeclared(t *testing.T) {
	spec := Spec{
		Agents:  []string{"claude-code", "hermes"},
		Servers: map[string]Server{},
	}

	if err := Validate(spec); err != nil {
		t.Fatalf("Validate() error = %v, want nil when no servers are declared", err)
	}
}

func TestValidateChecksPerAgentAssignments(t *testing.T) {
	spec := Spec{
		Agents: []string{"claude-code"},
		Assignments: map[string]map[string]Server{
			"claude-code": {"atlas": {}},
		},
	}

	if err := Validate(spec); err == nil {
		t.Fatal("Validate() error = nil, want a command/url error from the assignment override")
	}
}

func readJSON(t *testing.T, path string) map[string]any {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %q: %v", path, err)
	}
	var value map[string]any
	if err := json.Unmarshal(raw, &value); err != nil {
		t.Fatalf("decode %q: %v", path, err)
	}
	return value
}

func TestWriteTreeClaudeCodeWritesOneFilePerServer(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"claude-code"},
		Servers: map[string]Server{
			"atlas": {Command: "atlas", Args: []string{"serve"}, Env: map[string]string{"TOKEN": "@TOKEN@"}},
		},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	path := filepath.Join(tree, ".claude", "mcp", "atlas.json")
	got := readJSON(t, path)
	servers, ok := got["mcpServers"].(map[string]any)
	if !ok {
		t.Fatalf("mcpServers missing or wrong shape: %#v", got)
	}
	entry, ok := servers["atlas"].(map[string]any)
	if !ok {
		t.Fatalf("atlas entry missing: %#v", servers)
	}
	if entry["command"] != "atlas" {
		t.Errorf("command = %v, want atlas", entry["command"])
	}
	if _, hasEnabled := entry["enabled"]; hasEnabled {
		t.Errorf("plain entry must not carry an enabled field, got %#v", entry)
	}
}

func TestWriteTreeClaudeCodeMergesIntoExistingFile(t *testing.T) {
	tree := t.TempDir()
	dir := filepath.Join(tree, ".claude", "mcp")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "atlas.json"), []byte(`{"mcpServers":{"atlas":{"command":"old"}},"extra":true}`), 0o644); err != nil {
		t.Fatal(err)
	}

	spec := Spec{
		Agents:  []string{"claude-code"},
		Servers: map[string]Server{"atlas": {Command: "atlas"}},
	}
	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	got := readJSON(t, filepath.Join(dir, "atlas.json"))
	if got["extra"] != true {
		t.Errorf("merge dropped an existing unrelated key: %#v", got)
	}
}

func TestWriteTreeSharedPlainFileMergesEveryServer(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"cursor"},
		Servers: map[string]Server{
			"atlas": {Command: "atlas"},
			"b":     {URL: "https://example.com/mcp"},
		},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	got := readJSON(t, filepath.Join(tree, ".cursor", "mcp.json"))
	servers := got["mcpServers"].(map[string]any)
	if len(servers) != 2 {
		t.Fatalf("mcpServers = %#v, want 2 entries", servers)
	}
	b := servers["b"].(map[string]any)
	if b["url"] != "https://example.com/mcp" {
		t.Errorf("b.url = %v", b["url"])
	}
	if _, hasCommand := b["command"]; hasCommand {
		t.Errorf("a remote entry must not carry command: %#v", b)
	}
}

func TestWriteTreeSettingsPlainMergesUnderSettingsPath(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents:  []string{"gemini-cli"},
		Servers: map[string]Server{"atlas": {Command: "atlas"}},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	got := readJSON(t, filepath.Join(tree, ".gemini", "settings.json"))
	if _, ok := got["mcpServers"]; !ok {
		t.Fatalf("mcpServers missing: %#v", got)
	}
}

func TestWriteTreeOpenCodeShapeAndEnabledField(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"opencode"},
		Servers: map[string]Server{
			"atlas": {Command: "atlas", Args: []string{"serve"}, Enabled: boolPtr(false)},
			"b":     {URL: "https://example.com/mcp"},
		},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	got := readJSON(t, filepath.Join(tree, ".config", "opencode", "opencode.json"))
	mcp := got["mcp"].(map[string]any)

	atlas := mcp["atlas"].(map[string]any)
	if atlas["type"] != "local" {
		t.Errorf("atlas.type = %v, want local", atlas["type"])
	}
	command, ok := atlas["command"].([]any)
	if !ok || len(command) != 2 || command[0] != "atlas" || command[1] != "serve" {
		t.Errorf("atlas.command = %#v, want [atlas serve]", atlas["command"])
	}
	if atlas["enabled"] != false {
		t.Errorf("atlas.enabled = %v, want false", atlas["enabled"])
	}

	b := mcp["b"].(map[string]any)
	if b["type"] != "remote" || b["url"] != "https://example.com/mcp" {
		t.Errorf("b entry = %#v", b)
	}
	if b["enabled"] != true {
		t.Errorf("b.enabled = %v, want true (default)", b["enabled"])
	}
}

func TestWriteTreeOpenCodePrefersExistingJSONC(t *testing.T) {
	tree := t.TempDir()
	dir := filepath.Join(tree, ".config", "opencode")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "opencode.jsonc"), []byte(`{}`), 0o644); err != nil {
		t.Fatal(err)
	}

	spec := Spec{
		Agents:  []string{"opencode"},
		Servers: map[string]Server{"atlas": {Command: "atlas"}},
	}
	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	if _, err := os.Stat(filepath.Join(dir, "opencode.json")); err == nil {
		t.Fatal("wrote opencode.json even though opencode.jsonc already existed")
	}
	got := readJSON(t, filepath.Join(dir, "opencode.jsonc"))
	if _, ok := got["mcp"]; !ok {
		t.Fatalf("mcp missing from opencode.jsonc: %#v", got)
	}
}

func TestWriteTreeKilocodeSharesOpenCodeShape(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents:  []string{"kilocode"},
		Servers: map[string]Server{"atlas": {Command: "atlas"}},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	got := readJSON(t, filepath.Join(tree, ".config", "kilo", "opencode.json"))
	mcp := got["mcp"].(map[string]any)
	atlas := mcp["atlas"].(map[string]any)
	if atlas["type"] != "local" {
		t.Errorf("atlas.type = %v, want local", atlas["type"])
	}
}

func TestWriteTreePerAgentAssignmentReplacesFlatSet(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"claude-code", "cursor"},
		Servers: map[string]Server{
			"atlas": {Command: "atlas"},
		},
		Assignments: map[string]map[string]Server{
			"cursor": {"only-cursor": {Command: "cursor-tool"}},
		},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	// claude-code keeps the flat set.
	claude := readJSON(t, filepath.Join(tree, ".claude", "mcp", "atlas.json"))
	if _, ok := claude["mcpServers"].(map[string]any)["atlas"]; !ok {
		t.Fatalf("claude-code should keep the flat set: %#v", claude)
	}

	// cursor's own block fully replaces the flat set: "atlas" must be absent.
	cursor := readJSON(t, filepath.Join(tree, ".cursor", "mcp.json"))
	servers := cursor["mcpServers"].(map[string]any)
	if _, ok := servers["atlas"]; ok {
		t.Errorf("cursor's override should replace the flat set, but atlas leaked through: %#v", servers)
	}
	if _, ok := servers["only-cursor"]; !ok {
		t.Errorf("cursor's own server is missing: %#v", servers)
	}
}

func TestWriteTreeSkipsCodexEntirely(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents:  []string{"codex"},
		Servers: map[string]Server{"atlas": {Command: "atlas"}},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	if _, err := os.Stat(filepath.Join(tree, ".codex")); err == nil {
		t.Fatal("gentle-nix mcp must not write anything for codex; the module routes it through the TOML merger instead")
	}
}

func TestWriteTreeNoServersIsANoOp(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{Agents: []string{"claude-code", "hermes"}}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v, want nil for an empty spec even with an unsupported agent listed", err)
	}

	entries, err := os.ReadDir(tree)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Errorf("tree = %v, want untouched", entries)
	}
}

func TestWriteTreeKiroIDEAndPiAndKimiSharedPlainFiles(t *testing.T) {
	cases := []struct {
		agent string
		want  string
	}{
		{"kiro-ide", filepath.Join(".kiro", "settings", "mcp.json")},
		{"pi", filepath.Join(".pi", "agent", "mcp.json")},
		{"kimi", filepath.Join(".kimi", "mcp.json")},
	}

	for _, tc := range cases {
		t.Run(tc.agent, func(t *testing.T) {
			tree := t.TempDir()
			spec := Spec{
				Agents:  []string{tc.agent},
				Servers: map[string]Server{"atlas": {Command: "atlas"}},
			}
			if err := WriteTree(tree, spec); err != nil {
				t.Fatalf("WriteTree() error = %v", err)
			}
			got := readJSON(t, filepath.Join(tree, tc.want))
			if _, ok := got["mcpServers"].(map[string]any)["atlas"]; !ok {
				t.Fatalf("%s: mcpServers.atlas missing: %#v", tc.agent, got)
			}
		})
	}
}
