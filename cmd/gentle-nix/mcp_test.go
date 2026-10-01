package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func writeMigrateCLIFile(t *testing.T, dir, rel, content string) string {
	t.Helper()
	path := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestRunMCPMigratePiCopiesLegacyServers(t *testing.T) {
	dir := t.TempDir()
	writeMigrateCLIFile(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas"}}}`)
	nativePath := writeMigrateCLIFile(t, dir, "mcp.json", `{"mcpServers":{"native":{"command":"native"}}}`)

	code, err := runMCP([]string{"migrate-pi", "--agent-dir", dir})
	if err != nil {
		t.Fatalf("runMCP(migrate-pi) error = %v", err)
	}
	if code != 0 {
		t.Errorf("runMCP(migrate-pi) code = %d, want 0", code)
	}

	var servers map[string]map[string]any
	data, err := os.ReadFile(nativePath)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &struct {
		McpServers *map[string]map[string]any `json:"mcpServers"`
	}{&servers}); err != nil {
		t.Fatal(err)
	}
	if _, ok := servers["atlas"]; !ok {
		t.Errorf("mcpServers.atlas missing after migrate-pi: %#v", servers)
	}
	if _, ok := servers["native"]; !ok {
		t.Errorf("mcpServers.native missing after migrate-pi: %#v", servers)
	}
}

func TestRunMCPMigratePiRequiresAgentDir(t *testing.T) {
	code, err := runMCP([]string{"migrate-pi"})
	if err != nil {
		t.Fatalf("runMCP(migrate-pi) error = %v, want a usage exit instead", err)
	}
	if code != 2 {
		t.Errorf("runMCP(migrate-pi) code = %d, want 2 without --agent-dir", code)
	}
}

func TestRunMCPMigratePiRequiresAnAbsolutePath(t *testing.T) {
	code, err := runMCP([]string{"migrate-pi", "--agent-dir", "relative/pi/agent"})
	if err != nil {
		t.Fatalf("runMCP(migrate-pi) error = %v, want a usage exit instead", err)
	}
	if code != 2 {
		t.Errorf("runMCP(migrate-pi) code = %d, want 2 for a relative --agent-dir", code)
	}
}

func TestRunMCPMigratePiFailsClosedOnMalformedLegacy(t *testing.T) {
	dir := t.TempDir()
	writeMigrateCLIFile(t, dir, "mcp-adapter.json", `{"mcpServers": {`)
	nativePath := writeMigrateCLIFile(t, dir, "mcp.json", `{"mcpServers":{"native":{"command":"native"}}}`)
	before, err := os.ReadFile(nativePath)
	if err != nil {
		t.Fatal(err)
	}

	code, err := runMCP([]string{"migrate-pi", "--agent-dir", dir})
	if err == nil {
		t.Fatal("runMCP(migrate-pi) error = nil, want malformed legacy config refused")
	}
	if code != 0 {
		t.Errorf("runMCP(migrate-pi) code = %d, want 0 with the error carried in err (main exits 1)", code)
	}
	after, err := os.ReadFile(nativePath)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Error("native mcp.json bytes changed on a malformed legacy config; migration must fail closed")
	}
}
