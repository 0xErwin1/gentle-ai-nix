// Package settings deep-merges a provider's declared settings block into
// that client's own settings file inside a rendered Gentle AI tree.
//
// This is gentle-nix's own replacement for the one thing
// providers.<name>.settings used to do by traveling through the document as
// `extensions`, decoded and merged by the pinned Gentle AI fork's
// stageDeclaredExtensions/mergeExtensionBlock
// (internal/cli/config_stager.go). Now that gentle-nix stops emitting
// `extensions` in the document, it has to reach the same client files
// itself, at exactly the paths those adapters used
// (internal/agents/*/adapter.go's own SettingsPath), with the same deep-merge
// semantics: a nested object is merged key by key, any other value --
// including a list -- is replaced wholesale, and the declared (overlay)
// value always wins at a leaf.
//
// Only clients whose settings file is a plain JSON object at a fixed,
// non-OS-variant path are modeled here. Codex and Kimi keep their settings
// in TOML (config.toml) and are routed through the existing Python
// gentle-ai-merge (lib/merge.py) instead, in the same Nix overlay step that
// calls this package for everyone else -- see modules/home-manager.nix. A
// handful of IDE-style clients (VS Code, Antigravity, Windsurf, Trae, Kiro)
// resolve their settings path from OS-specific state the fork's own Go code
// inspects at run time; reproducing that from a Nix module is out of scope
// for this phase, so declaring providers.<name>.settings for one of them is
// not supported here (ResolvePath reports them as unknown, the same as any
// other unrecognized provider name).
package settings

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// settingsPaths is gentle-nix's own copy of the pinned fork's per-provider
// SettingsPath, relative to the tree root ResolvePath is given.
var settingsPaths = map[string]string{
	"claude-code": filepath.Join(".claude", "settings.json"),
	"pi":          filepath.Join(".pi", "agent", "settings.json"),
	"gemini-cli":  filepath.Join(".gemini", "settings.json"),
	"cursor":      filepath.Join(".cursor", "settings.json"),
	"qwen-code":   filepath.Join(".qwen", "settings.json"),
	"kilocode":    filepath.Join(".config", "kilo", "opencode.json"),
	"openclaw":    filepath.Join(".config", "openclaw", "openclaw.json"),
}

// ResolvePath is the fork's opencode adapter's own SettingsPath, ported: it
// prefers an opencode.jsonc that already exists in the tree, and otherwise
// (including provider != "opencode") looks the provider up in
// settingsPaths. ok is false for any provider this package does not know
// how to merge into.
func ResolvePath(tree, provider string) (string, bool) {
	if provider == "opencode" {
		jsoncPath := filepath.Join(tree, ".config", "opencode", "opencode.jsonc")
		if info, err := os.Stat(jsoncPath); err == nil && info.Mode().IsRegular() {
			return jsoncPath, true
		}
		return filepath.Join(tree, ".config", "opencode", "opencode.json"), true
	}

	rel, ok := settingsPaths[provider]
	if !ok {
		return "", false
	}
	return filepath.Join(tree, rel), true
}

// mergeObjects is mergeObjects/mergeObjectScope from the fork's
// internal/components/filemerge/json_merge.go, minus the permission-scalar
// protection that package also carries -- irrelevant here, since a plain
// provider settings block is never the "permission" component's own state.
func mergeObjects(base, overlay map[string]any) map[string]any {
	result := make(map[string]any, len(base)+len(overlay))
	for key, value := range base {
		result[key] = value
	}
	for key, overlayValue := range overlay {
		baseValue, exists := result[key]
		if exists {
			if baseMap, baseIsMap := baseValue.(map[string]any); baseIsMap {
				if overlayMap, overlayIsMap := overlayValue.(map[string]any); overlayIsMap {
					result[key] = mergeObjects(baseMap, overlayMap)
					continue
				}
			}
		}
		result[key] = overlayValue
	}
	return result
}

// MergeInto deep-merges block (a JSON object) into the JSON object at
// settingsPath, creating the file (and its parent directories) if absent.
// An existing file this cannot parse as a JSON object is treated the same
// way the fork's MergeJSONObjects treats it: as an empty object, so a
// corrupt or genuinely-absent client file never blocks a declared setting
// from landing. block itself must be a valid JSON object -- that one is the
// declaration, and a typo there is worth failing loudly for.
func MergeInto(settingsPath string, block []byte) error {
	overlay, err := unmarshalObject(block)
	if err != nil {
		return fmt.Errorf("settings block for %q: %w", settingsPath, err)
	}

	base := map[string]any{}
	if existing, err := os.ReadFile(settingsPath); err == nil {
		if decoded, decodeErr := unmarshalObject(existing); decodeErr == nil {
			base = decoded
		}
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("read settings %q: %w", settingsPath, err)
	}

	merged := mergeObjects(base, overlay)

	encoded, err := json.MarshalIndent(merged, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal merged settings %q: %w", settingsPath, err)
	}
	encoded = append(encoded, '\n')

	if err := os.MkdirAll(filepath.Dir(settingsPath), 0o755); err != nil {
		return fmt.Errorf("create settings directory for %q: %w", settingsPath, err)
	}
	if err := os.WriteFile(settingsPath, encoded, 0o644); err != nil {
		return fmt.Errorf("write settings %q: %w", settingsPath, err)
	}
	return nil
}

func unmarshalObject(data []byte) (map[string]any, error) {
	var value map[string]any
	if err := json.Unmarshal(data, &value); err != nil {
		return nil, err
	}
	if value == nil {
		value = map[string]any{}
	}
	return value, nil
}

// ProviderBlock is one --provider name=path argument, already split: Name
// is the provider id (e.g. "claude-code"), BlockPath is where its declared
// settings JSON lives on disk.
type ProviderBlock struct {
	Name      string
	BlockPath string
}

// Options mirrors gentle-nix settings' CLI contract.
type Options struct {
	Tree      string
	Providers []ProviderBlock
}

// Run merges every declared provider block into its own settings file
// inside opts.Tree. It stops at the first provider ResolvePath does not
// recognize -- gentle-nix settings has no partial-apply story, since a
// misspelled provider name is a configuration mistake worth failing the
// whole activation over, the same way an unknown provider or skill already
// is elsewhere in this flake.
func Run(opts Options) (int, error) {
	for _, provider := range opts.Providers {
		path, ok := ResolvePath(opts.Tree, provider.Name)
		if !ok {
			return 2, fmt.Errorf("gentle-nix settings: unknown provider %q", provider.Name)
		}

		block, err := os.ReadFile(provider.BlockPath)
		if err != nil {
			return 0, fmt.Errorf("read settings block for %q: %w", provider.Name, err)
		}

		if err := MergeInto(path, block); err != nil {
			return 0, err
		}
	}
	return 0, nil
}
