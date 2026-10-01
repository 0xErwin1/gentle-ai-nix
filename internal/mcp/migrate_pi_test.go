package mcp

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeMigrateFixture writes content at rel under dir and returns the path.
func writeMigrateFixture(t *testing.T, dir, rel, content string) string {
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

func readMigrateFixture(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestMigratePiCopiesOnlyMissingLegacyServers(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{
	  "mcpServers": {
	    "atlas": {"command": "atlas", "args": ["--stdio"], "env": {"TOKEN": "t"}},
	    "engram": {"command": "legacy-engram"}
	  }
	}`)
	writeMigrateFixture(t, dir, "mcp.json", `{
	  "other": {"nested": true},
	  "mcpServers": {
	    "engram": {"command": "native-engram", "args": ["--native"]},
	    "existing": {"url": "https://example.com"}
	  }
	}`)
	legacyBefore := readMigrateFixture(t, filepath.Join(dir, "mcp-adapter.json"))

	result, err := MigratePi(dir)
	if err != nil {
		t.Fatalf("MigratePi() error = %v", err)
	}
	if strings.Join(result.Copied, ",") != "atlas" {
		t.Errorf("Copied = %v, want [atlas]", result.Copied)
	}
	if strings.Join(result.Skipped, ",") != "engram" {
		t.Errorf("Skipped = %v, want [engram]", result.Skipped)
	}

	var native map[string]json.RawMessage
	data, err := os.ReadFile(filepath.Join(dir, "mcp.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &native); err != nil {
		t.Fatalf("migrated mcp.json is not JSON: %v", err)
	}

	var servers map[string]map[string]any
	if err := json.Unmarshal(native["mcpServers"], &servers); err != nil {
		t.Fatal(err)
	}
	if got, ok := servers["atlas"]["command"].(string); !ok || got != "atlas" {
		t.Errorf("mcpServers.atlas = %#v, want the legacy entry carried over verbatim", servers["atlas"])
	}
	if args, ok := servers["atlas"]["args"].([]any); !ok || len(args) != 1 || args[0] != "--stdio" {
		t.Errorf("mcpServers.atlas.args = %#v, want [\"--stdio\"]", servers["atlas"]["args"])
	}
	if env, ok := servers["atlas"]["env"].(map[string]any); !ok || env["TOKEN"] != "t" {
		t.Errorf("mcpServers.atlas.env = %#v, want the legacy env block", servers["atlas"]["env"])
	}
	if got, ok := servers["engram"]["command"].(string); !ok || got != "native-engram" {
		t.Errorf("mcpServers.engram = %#v, want the existing native entry to win", servers["engram"])
	}
	if _, ok := servers["existing"]; !ok {
		t.Errorf("mcpServers.existing missing: %#v", servers)
	}

	var other map[string]any
	if err := json.Unmarshal(native["other"], &other); err != nil {
		t.Fatalf("unrelated top-level key lost or corrupted: %v", err)
	}

	if after := readMigrateFixture(t, filepath.Join(dir, "mcp-adapter.json")); after != legacyBefore {
		t.Error("legacy mcp-adapter.json bytes changed; the legacy file must stay read-only")
	}
}

func TestMigratePiMissingLegacyIsANoOp(t *testing.T) {
	dir := t.TempDir()
	nativePath := writeMigrateFixture(t, dir, "mcp.json", `{"mcpServers":{"atlas":{"command":"atlas"}}}`)
	before := readMigrateFixture(t, nativePath)

	result, err := MigratePi(dir)
	if err != nil {
		t.Fatalf("MigratePi() error = %v, want a no-op without a legacy adapter config", err)
	}
	if len(result.Copied) != 0 || len(result.Skipped) != 0 {
		t.Errorf("result = %#v, want nothing copied or skipped", result)
	}
	if after := readMigrateFixture(t, nativePath); after != before {
		t.Error("native mcp.json bytes changed without a legacy config to migrate")
	}
}

func TestMigratePiLegacyWithoutMcpServersIsANoOp(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"unrelated": [1, 2, 3]}`)

	result, err := MigratePi(dir)
	if err != nil {
		t.Fatalf("MigratePi() error = %v, want a no-op without legacy mcpServers", err)
	}
	if len(result.Copied) != 0 || len(result.Skipped) != 0 {
		t.Errorf("result = %#v, want nothing copied or skipped", result)
	}
	if _, err := os.Stat(filepath.Join(dir, "mcp.json")); !os.IsNotExist(err) {
		t.Errorf("mcp.json stat error = %v, want the native config left absent", err)
	}
}

func TestMigratePiCreatesNativeConfigWhenAbsent(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas"}}}`)

	if _, err := MigratePi(dir); err != nil {
		t.Fatalf("MigratePi() error = %v", err)
	}

	var servers map[string]map[string]any
	data, err := os.ReadFile(filepath.Join(dir, "mcp.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &struct {
		McpServers *map[string]map[string]any `json:"mcpServers"`
	}{&servers}); err != nil {
		t.Fatal(err)
	}
	if _, ok := servers["atlas"]; !ok {
		t.Errorf("mcpServers.atlas missing from the created native config: %#v", servers)
	}
}

func TestMigratePiAllEntriesAlreadyNativeIsANoOp(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"legacy"}}}`)
	nativePath := writeMigrateFixture(t, dir, "mcp.json", "{\"mcpServers\": {\"atlas\": {\"command\": \"native\"}}}")
	before := readMigrateFixture(t, nativePath)

	result, err := MigratePi(dir)
	if err != nil {
		t.Fatalf("MigratePi() error = %v", err)
	}
	if len(result.Copied) != 0 {
		t.Errorf("Copied = %v, want nothing copied", result.Copied)
	}
	if strings.Join(result.Skipped, ",") != "atlas" {
		t.Errorf("Skipped = %v, want [atlas]", result.Skipped)
	}
	if after := readMigrateFixture(t, nativePath); after != before {
		t.Error("native mcp.json bytes changed although every legacy entry was already present")
	}
}

func TestMigratePiMalformedLegacyFailsClosed(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers": {`)
	nativePath := writeMigrateFixture(t, dir, "mcp.json", `{"mcpServers":{"atlas":{"command":"native"}}}`)
	before := readMigrateFixture(t, nativePath)

	if _, err := MigratePi(dir); err == nil {
		t.Fatal("MigratePi() error = nil, want malformed legacy config refused")
	}
	if after := readMigrateFixture(t, nativePath); after != before {
		t.Error("native mcp.json bytes changed on a malformed legacy config; migration must fail closed")
	}
}

func TestMigratePiNonObjectLegacyFailsClosed(t *testing.T) {
	for _, content := range []string{"[1, 2, 3]", `"mcp"`, "null", "42"} {
		t.Run(content, func(t *testing.T) {
			dir := t.TempDir()
			writeMigrateFixture(t, dir, "mcp-adapter.json", content)

			if _, err := MigratePi(dir); err == nil {
				t.Fatalf("MigratePi() error = nil, want non-object legacy config %q refused", content)
			}
		})
	}
}

func TestMigratePiMalformedNativeFailsClosed(t *testing.T) {
	dir := t.TempDir()
	legacyPath := writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas"}}}`)
	writeMigrateFixture(t, dir, "mcp.json", `not json at all`)
	before := readMigrateFixture(t, legacyPath)

	if _, err := MigratePi(dir); err == nil {
		t.Fatal("MigratePi() error = nil, want malformed native config refused")
	}
	if after := readMigrateFixture(t, legacyPath); after != before {
		t.Error("legacy mcp-adapter.json bytes changed on a malformed native config")
	}
	if _, err := os.Stat(filepath.Join(dir, "mcp.json")); err != nil {
		t.Errorf("mcp.json stat error = %v, want the native file left in place", err)
	}
}

func TestMigratePiNonObjectNativeMcpServersFailsClosed(t *testing.T) {
	for _, content := range []string{`{"mcpServers": []}`, `{"mcpServers": null}`, `{"mcpServers": "atlas"}`} {
		t.Run(content, func(t *testing.T) {
			dir := t.TempDir()
			writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas"}}}`)
			writeMigrateFixture(t, dir, "mcp.json", content)

			if _, err := MigratePi(dir); err == nil {
				t.Fatalf("MigratePi() error = nil, want native mcpServers %q refused", content)
			}
		})
	}
}

func TestMigratePiRejectsSymlinkedDestination(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas"}}}`)
	target := filepath.Join(t.TempDir(), "real-mcp.json")
	writeMigrateFixture(t, t.TempDir(), "ignored", "")
	if err := os.WriteFile(target, []byte(`{"mcpServers":{"native":{"command":"native"}}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(dir, "mcp.json")); err != nil {
		t.Fatal(err)
	}
	targetBefore := readMigrateFixture(t, target)

	if _, err := MigratePi(dir); err == nil {
		t.Fatal("MigratePi() error = nil, want a symlinked native destination refused")
	}
	if after := readMigrateFixture(t, target); after != targetBefore {
		t.Error("the symlink target's bytes changed; a symlinked destination must be rejected, never written through")
	}
}

func TestMigratePiSurvivesADirectoryNamedLikeTheDestination(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas"}}}`)
	if err := os.Mkdir(filepath.Join(dir, "mcp.json"), 0o755); err != nil {
		t.Fatal(err)
	}

	if _, err := MigratePi(dir); err == nil {
		t.Fatal("MigratePi() error = nil, want a directory in the destination's place refused")
	}
}

func TestMigratePiZeroByteNativeFailsClosed(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas","env":{"TOKEN":"secret"}}}}`)
	nativePath := writeMigrateFixture(t, dir, "mcp.json", "")

	if _, err := MigratePi(dir); err == nil {
		t.Fatal("MigratePi() error = nil, want an existing zero-byte native config refused instead of silently recreated")
	}
	if info, err := os.Stat(nativePath); err != nil {
		t.Fatalf("mcp.json stat error = %v, want the zero-byte file preserved", err)
	} else if info.Size() != 0 {
		t.Errorf("mcp.json size = %d, want 0: the zero-byte file's bytes must be preserved on refusal", info.Size())
	}
}

func TestMigratePiRetainsExistingNativeFileMode(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas","env":{"API_KEY":"secret"},"headers":{"Authorization":"Bearer secret"}}}}`)
	nativePath := writeMigrateFixture(t, dir, "mcp.json", `{"mcpServers":{"engram":{"command":"native"}}}`)
	if err := os.Chmod(nativePath, 0o600); err != nil {
		t.Fatal(err)
	}

	if _, err := MigratePi(dir); err != nil {
		t.Fatalf("MigratePi() error = %v", err)
	}
	info, err := os.Stat(nativePath)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o600 {
		t.Errorf("mcp.json mode after merge = %v, want -rw-------: an existing restrictive mode must be preserved", got)
	}
	data, err := os.ReadFile(nativePath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "Bearer secret") {
		t.Error("legacy entry with credentials not carried into the merged config")
	}
}

func TestMigratePiCreatesNativeConfigOwnerOnly(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"mcpServers":{"atlas":{"command":"atlas","env":{"TOKEN":"secret"}}}}`)

	if _, err := MigratePi(dir); err != nil {
		t.Fatalf("MigratePi() error = %v", err)
	}
	info, err := os.Stat(filepath.Join(dir, "mcp.json"))
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got&0o077 != 0 {
		t.Errorf("created mcp.json mode = %v, want no group/other access (e.g. -rw-------): legacy server blocks can carry credentials", got)
	}
}

func TestMigratePiValidatesNativeEvenWhenLegacyHasNoServers(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"unrelated": [1, 2, 3]}`)
	writeMigrateFixture(t, dir, "mcp.json", `not json at all`)

	if _, err := MigratePi(dir); err == nil {
		t.Fatal("MigratePi() error = nil, want a malformed native config refused even when the legacy config has nothing to copy")
	}
}

func TestMigratePiRejectsSymlinkEvenWhenLegacyHasNoServers(t *testing.T) {
	dir := t.TempDir()
	writeMigrateFixture(t, dir, "mcp-adapter.json", `{"unrelated": [1, 2, 3]}`)
	target := filepath.Join(t.TempDir(), "real-mcp.json")
	if err := os.WriteFile(target, []byte(`{"mcpServers":{"native":{"command":"native"}}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(dir, "mcp.json")); err != nil {
		t.Fatal(err)
	}
	targetBefore := readMigrateFixture(t, target)

	if _, err := MigratePi(dir); err == nil {
		t.Fatal("MigratePi() error = nil, want a symlinked native destination refused even when there is nothing to copy")
	}
	if after := readMigrateFixture(t, target); after != targetBefore {
		t.Error("the symlink target's bytes changed although the legacy config had nothing to copy")
	}
}
