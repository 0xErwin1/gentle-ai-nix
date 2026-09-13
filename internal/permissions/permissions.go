// Package permissions renders gentle-ai-nix's own declared user permission
// rules onto a rendered Gentle AI tree. Declaring an allow/deny/ask rule for
// a client is not something Gentle AI does imperatively for every adapter --
// only Claude Code expresses permissions as the rule-list shape a document
// can add to, the rest either have no injectable permission overlay at all
// or key it a different way entirely (OpenCode's tool-and-glob permission
// map, say) -- so `permissions` leaves the document entirely: this package
// post-processes the tree "gentle-ai config render" already produced, the
// same way gentle-nix roles, gentle-nix mcp and gentle-nix pi routing
// post-process it for their own concerns (see internal/roles, internal/mcp,
// internal/pirouting).
//
// This package reproduces exactly what the pinned Gentle AI fork's own
// internal/components/permissions/declared.go
// (InjectDeclared/unionedWith/unionStrings) used to write for Claude Code:
// declared rules are UNIONED into whatever the settings file already carries
// at permissions.allow/deny/ask -- existing entries first, in their existing
// order, then declared entries appended, both deduplicated -- rather than
// replacing the shipped guardrails outright. A rule list a document never
// mentions survives untouched.
//
// No other adapter is supported here, matching the fork exactly: the fork's
// own SupportsDeclaredRules only ever returns true for Claude Code among the
// adapters gentle-nix knows (OpenCode and Kilocode's shipped overlay keys
// permissions per tool and glob, not as allow/deny/ask string lists; Cursor,
// Antigravity, Codex and Hermes carry no injectable permission overlay at
// all). A document declaring rules while Claude Code is not enabled is not
// an error -- the fork's own InjectDeclared silently takes no adapters
// either -- so this package is a plain no-op rather than a validated one.
package permissions

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/0xErwin1/gentle-ai-nix/internal/settings"
)

// Spec is gentle-nix permissions' own input contract: the clients the
// document enables (used only to decide whether Claude Code is among them)
// and the declared rule lists.
type Spec struct {
	Agents []string `json:"agents,omitempty"`
	Allow  []string `json:"allow,omitempty"`
	Deny   []string `json:"deny,omitempty"`
	Ask    []string `json:"ask,omitempty"`
}

func (spec Spec) empty() bool {
	return len(spec.Allow) == 0 && len(spec.Deny) == 0 && len(spec.Ask) == 0
}

func (spec Spec) claudeCodeEnabled() bool {
	for _, agent := range spec.Agents {
		if agent == "claude-code" {
			return true
		}
	}
	return false
}

// Render unions spec's declared rules into .claude/settings.json's
// permissions.allow/deny/ask, creating the file if Claude Code is enabled
// and no such file exists yet. It is a no-op when Claude Code is not among
// spec.Agents, or when spec declares no rules at all.
func Render(tree string, spec Spec) error {
	if spec.empty() || !spec.claudeCodeEnabled() {
		return nil
	}

	settingsPath := filepath.Join(tree, ".claude", "settings.json")

	existing, err := existingRules(settingsPath)
	if err != nil {
		return err
	}

	rules := map[string]any{}
	for key, declared := range map[string][]string{"allow": spec.Allow, "deny": spec.Deny, "ask": spec.Ask} {
		if union := unionStrings(existing[key], declared); len(union) > 0 {
			rules[key] = union
		}
	}
	if len(rules) == 0 {
		return nil
	}

	overlay, err := json.Marshal(map[string]any{"permissions": rules})
	if err != nil {
		return fmt.Errorf("encode declared permissions: %w", err)
	}

	return settings.MergeInto(settingsPath, overlay)
}

// existingRules reads the current permissions.allow/deny/ask arrays out of
// settingsPath, the same way the fork's own unionedWith does: the shipped
// block mixes types (defaultMode is a string alongside the rule arrays), so
// only the three rule keys are decoded and anything else -- including a
// missing or unparsable file -- reads back empty rather than failing the
// render.
func existingRules(settingsPath string) (map[string][]string, error) {
	raw, err := os.ReadFile(settingsPath)
	if err != nil {
		if os.IsNotExist(err) {
			return map[string][]string{}, nil
		}
		return nil, fmt.Errorf("read settings %q: %w", settingsPath, err)
	}

	var document struct {
		Permissions map[string]json.RawMessage `json:"permissions"`
	}
	if json.Unmarshal(raw, &document) != nil {
		return map[string][]string{}, nil
	}

	current := make(map[string][]string, len(document.Permissions))
	for key, value := range document.Permissions {
		var values []string
		if json.Unmarshal(value, &values) == nil {
			current[key] = values
		}
	}
	return current, nil
}

// unionStrings merges declared into shipped, keeping shipped's own order,
// then appending every declared entry shipped does not already carry --
// mirrors the fork's own unionStrings exactly.
func unionStrings(shipped, declared []string) []string {
	seen := make(map[string]struct{}, len(shipped)+len(declared))
	union := make([]string, 0, len(shipped)+len(declared))

	for _, group := range [][]string{shipped, declared} {
		for _, value := range group {
			if _, repeated := seen[value]; repeated {
				continue
			}
			seen[value] = struct{}{}
			union = append(union, value)
		}
	}

	return union
}
