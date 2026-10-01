package mcp

// This file carries a host's legacy Pi adapter MCP servers into Pi's own
// native MCP config before the adapter is retired (gentle-nix mcp
// migrate-pi). It is deliberately narrow: it reads
// <agentDir>/mcp-adapter.json, copies only the mcpServers entries that
// <agentDir>/mcp.json does not already have, and writes the merged native
// config back atomically. The legacy adapter file is never written, and the
// adapter itself stays installed until the Nix-side guarded activation
// (T2b) retires it after this helper has succeeded and the native Engram
// plugin is in place.
//
// Failure is closed: a legacy or native file that does not parse as a JSON
// object (an existing zero-byte native config included), a non-object
// mcpServers block, a symlinked native destination, or any write failure
// aborts the migration leaving every participating byte exactly as it was.
// The native config is validated even when the legacy side has nothing to
// copy, so adapter retirement never rides on an unexamined config, and an
// existing native file's mode is preserved while a newly created one gets
// 0600 because migrated server blocks can carry credentials. A missing
// legacy file, a legacy file without mcpServers, or a legacy mcpServers
// block whose entries are all already native is a no-op that touches
// nothing.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

const (
	// legacyPiAdapterRel is the old pi-mcp-adapter's config file inside the
	// Pi agent directory. MigratePi only ever reads it.
	legacyPiAdapterRel = "mcp-adapter.json"

	// nativePiMCPRel is Pi's own native MCP config inside the Pi agent
	// directory, the file Pi's built-in MCP support reads.
	nativePiMCPRel = "mcp.json"
)

// MigratePiResult reports what MigratePi did, with both name lists sorted
// for deterministic reporting.
type MigratePiResult struct {
	// Copied holds the legacy server names MigratePi wrote into the native
	// config this run.
	Copied []string
	// Skipped holds the legacy server names already present in the native
	// config, which always win over the legacy entry of the same name.
	Skipped []string
}

// MigratePi copies the missing mcpServers entries from the legacy Pi
// adapter config in agentDir into Pi's native mcp.json in the same
// directory. Existing native entries win, every unrelated top-level key of
// the native config survives, legacy entries are carried over verbatim, and
// the legacy file itself is never modified. The native config is fully
// validated and its file mode preserved even when the legacy side has
// nothing to copy, so callers that retire the adapter on success never
// retire it on top of a config they never looked at. A newly created
// native config gets 0600, because legacy server blocks routinely carry
// credentials in env and headers. See the file doc for the failure and
// no-op contract.
func MigratePi(agentDir string) (MigratePiResult, error) {
	legacyPath := filepath.Join(agentDir, legacyPiAdapterRel)
	nativePath := filepath.Join(agentDir, nativePiMCPRel)

	// The native destination is validated before the legacy no-op
	// shortcuts: adapter retirement relies on MigratePi's success, so even
	// a run with nothing to copy must reject a symlinked destination and a
	// malformed or zero-byte native config instead of reporting success.
	var nativePerm os.FileMode = 0o600
	if info, err := os.Lstat(nativePath); err == nil {
		if info.Mode()&os.ModeSymlink != 0 {
			// On a Home Manager-managed host that link may project a store
			// path, and silently following it would either fail confusingly
			// or write outside the agent directory.
			return MigratePiResult{}, fmt.Errorf("native Pi MCP config %q is a symlink; refusing to migrate into it", nativePath)
		}
		nativePerm = info.Mode().Perm()
	} else if !os.IsNotExist(err) {
		return MigratePiResult{}, fmt.Errorf("stat native Pi MCP config %q: %w", nativePath, err)
	}

	nativeBytes, err := os.ReadFile(nativePath)
	if err != nil && !os.IsNotExist(err) {
		return MigratePiResult{}, fmt.Errorf("read native Pi MCP config %q: %w", nativePath, err)
	}
	native := map[string]json.RawMessage{}
	if err == nil {
		// An existing zero-byte native config is refused rather than treated
		// as empty: it is indistinguishable from a truncated or racing write
		// and silently recreating it could drop an unseen config.
		decoded, err := decodeJSONObject(nativeBytes)
		if err != nil {
			return MigratePiResult{}, fmt.Errorf("native Pi MCP config %q: %w", nativePath, err)
		}
		native = decoded
		if _, _, err := decodeMCPServers(native); err != nil {
			return MigratePiResult{}, fmt.Errorf("native Pi MCP config %q: %w", nativePath, err)
		}
	}

	legacyBytes, err := os.ReadFile(legacyPath)
	if os.IsNotExist(err) {
		// No legacy adapter config on this host: nothing to carry over.
		return MigratePiResult{}, nil
	}
	if err != nil {
		return MigratePiResult{}, fmt.Errorf("read legacy Pi adapter config %q: %w", legacyPath, err)
	}

	legacy, err := decodeJSONObject(legacyBytes)
	if err != nil {
		return MigratePiResult{}, fmt.Errorf("legacy Pi adapter config %q: %w", legacyPath, err)
	}
	legacyServers, ok, err := decodeMCPServers(legacy)
	if err != nil {
		return MigratePiResult{}, fmt.Errorf("legacy Pi adapter config %q: %w", legacyPath, err)
	}
	if !ok || len(legacyServers) == 0 {
		return MigratePiResult{}, nil
	}

	nativeServers, ok, err := decodeMCPServers(native)
	if err != nil {
		return MigratePiResult{}, fmt.Errorf("native Pi MCP config %q: %w", nativePath, err)
	}

	copied, skipped, merged := mergeMissing(legacyServers, nativeServers)
	if len(copied) == 0 {
		return MigratePiResult{Skipped: skipped}, nil
	}

	output := make(map[string]json.RawMessage, len(native)+1)
	for key, raw := range native {
		output[key] = raw
	}
	mergedServers, err := json.Marshal(merged)
	if err != nil {
		return MigratePiResult{}, fmt.Errorf("encode merged native MCP servers: %w", err)
	}
	output[nativeMCPServersKey] = mergedServers

	encoded, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return MigratePiResult{}, fmt.Errorf("encode native Pi MCP config %q: %w", nativePath, err)
	}
	encoded = append(encoded, '\n')

	if err := writeAtomic(nativePath, encoded, nativePerm); err != nil {
		return MigratePiResult{}, fmt.Errorf("write native Pi MCP config %q: %w", nativePath, err)
	}
	return MigratePiResult{Copied: copied, Skipped: skipped}, nil
}

// nativeMCPServersKey is the top-level key Pi's native MCP config carries
// its servers under.
const nativeMCPServersKey = "mcpServers"

// decodeJSONObject parses data as a JSON object, refusing non-objects (and
// a literal null) so a wrong-shaped file never silently migrates as if it
// were empty.
func decodeJSONObject(data []byte) (map[string]json.RawMessage, error) {
	var decoded map[string]json.RawMessage
	if err := json.Unmarshal(data, &decoded); err != nil {
		return nil, fmt.Errorf("not valid JSON: %w", err)
	}
	if decoded == nil {
		return nil, fmt.Errorf("not a JSON object")
	}
	return decoded, nil
}

// decodeMCPServers extracts the mcpServers block of a decoded object,
// reporting ok=false when the key is absent and refusing a present block
// that is not an object.
func decodeMCPServers(doc map[string]json.RawMessage) (map[string]json.RawMessage, bool, error) {
	raw, ok := doc[nativeMCPServersKey]
	if !ok {
		return nil, false, nil
	}
	var servers map[string]json.RawMessage
	if err := json.Unmarshal(raw, &servers); err != nil || servers == nil {
		return nil, true, fmt.Errorf("%q is not a JSON object", nativeMCPServersKey)
	}
	return servers, true, nil
}

// mergeMissing returns the legacy names that must be copied (sorted), the
// ones the native config already covers (sorted), and the merged server
// block in which every existing native entry is byte-identical to what the
// native file carried.
func mergeMissing(legacy, native map[string]json.RawMessage) (copied, skipped []string, merged map[string]json.RawMessage) {
	merged = make(map[string]json.RawMessage, len(native)+len(legacy))
	for name, raw := range native {
		merged[name] = raw
	}
	for name, raw := range legacy {
		if _, exists := native[name]; exists {
			skipped = append(skipped, name)
			continue
		}
		merged[name] = raw
		copied = append(copied, name)
	}
	sort.Strings(copied)
	sort.Strings(skipped)
	return copied, skipped, merged
}

// writeAtomic replaces the file at path with data via a temporary file in
// the same directory and a rename, so a failure anywhere before the rename
// leaves the previous bytes untouched and no partial file at path. The
// replacement carries perm: an existing file's mode is preserved and a
// newly created config gets the caller's default (0600, since migrated
// server blocks can carry credentials).
func writeAtomic(path string, data []byte, perm os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	cleanup := func() {
		tmp.Close()
		os.Remove(tmpName)
	}

	if _, err := tmp.Write(data); err != nil {
		cleanup()
		return err
	}
	if err := tmp.Chmod(perm); err != nil {
		cleanup()
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		os.Remove(tmpName)
		return err
	}
	return nil
}
