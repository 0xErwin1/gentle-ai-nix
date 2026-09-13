// Package skills renders gentle-ai-nix's own per-client skill scoping onto a
// rendered Gentle AI tree. `providers.<id>.skills` (a per-client override
// that fully replaces the flat list for that client only) and
// `skillExclusions` (names dropped from the flat list everywhere else) are
// not something the document itself resolves per adapter -- Gentle AI's own
// contract only ever carries one flat `skills` list -- so both leave the
// document entirely: this package post-processes the tree "gentle-ai config
// render" already produced, the same way gentle-nix roles, gentle-nix mcp
// and gentle-nix permissions post-process it for their own concerns.
//
// Because the document can only ever declare one flat list, the Nix module
// sends it the UNION of every skill any client needs (see Spec's own doc),
// so the render stages every needed skill into every client's own skills
// directory. This package then prunes each directory back down to what that
// one client actually resolves to, reproducing exactly the per-adapter
// resolution the pinned fork's own skillsForAdapter
// (internal/cli/config_stager.go) used to compute before the fork's
// component render staged only the resolved set to begin with.
//
// Per-adapter skills directories mirror the fork's own adapters'
// SkillsDir(): Pi has none (Pi has no injectable skills concept at all,
// same as internal/mcp's own supportedAgents omits it for MCP -- wait, Pi
// does support MCP; it simply carries no skill files).
//
// Unlike SettingsPath and MCPConfigPath, every one of antigravity's,
// windsurf's and trae-ide's own SkillsDir() is OS-invariant -- none of them
// route through the OS-variant *UserDir helper their settings/MCP paths
// do -- so all three carry a plain entry here, the same as vscode-copilot's
// (which was already OS-invariant). A caller that still wants to redirect
// one (say, to match a real antigravity install that landed in its
// "desktop" variant rather than the "cli" fallback this package assumes)
// can do so through Spec.SkillsDir.
package skills

import (
	"fmt"
	"os"
	"path/filepath"
)

// Spec is gentle-nix skills' own input contract: the clients the document
// enables, the flat skill set that lands in every client's directory during
// render (already the union the Nix module computed -- see the package
// doc), the names `skillExclusions` drops from the flat resolution, and the
// per-client lists that replace the flat resolution outright for their own
// client only.
//
// Flat nil means never declared (Gentle AI's default set survives minus
// Exclusions); non-nil, even `[]string{}`, is an explicit narrowing.
type Spec struct {
	Agents      []string            `json:"agents,omitempty"`
	Flat        []string            `json:"flat,omitempty"`
	Exclusions  []string            `json:"exclusions,omitempty"`
	Assignments map[string][]string `json:"assignments,omitempty"`

	// SkillsDir overrides the directory Prune reads and prunes an agent's
	// skills from, keyed by agent name and holding a path relative to the
	// rendered tree. It always wins over skillsDirs -- see the package doc.
	SkillsDir map[string]string `json:"skillsDir,omitempty"`
}

// skillsDirs are the adapters this package knows how to prune, and the
// directory (relative to the rendered tree) each one reads its skills from.
// Mirrors the fork's own per-adapter SkillsDir() -- see the package doc for
// the adapters deliberately absent.
var skillsDirs = map[string]string{
	"claude-code":    filepath.Join(".claude", "skills"),
	"opencode":       filepath.Join(".config", "opencode", "skills"),
	"kilocode":       filepath.Join(".config", "kilo", "skills"),
	"gemini-cli":     filepath.Join(".gemini", "skills"),
	"qwen-code":      filepath.Join(".qwen", "skills"),
	"vscode-copilot": filepath.Join(".copilot", "skills"),
	"cursor":         filepath.Join(".cursor", "skills"),
	"codex":          filepath.Join(".codex", "skills"),
	"kiro-ide":       filepath.Join(".kiro", "skills"),
	"kimi":           filepath.Join(".config", "agents", "skills"),
	"openclaw":       filepath.Join(".openclaw", "skills"),
	"hermes":         filepath.Join(".hermes", "skills"),

	// OS-invariant despite their settings/MCP paths being OS-variant -- see
	// the package doc.
	"antigravity": filepath.Join(".gemini", "antigravity-cli", "skills"),
	"windsurf":    filepath.Join(".codeium", "windsurf", "skills"),
	"trae-ide":    filepath.Join(".trae", "skills"),
}

// Resolve reports the skill IDs one agent explicitly keeps: its own
// assignment (exclusions not applied), or flat minus Exclusions when Flat
// is declared. explicit is false when neither applies (Flat undeclared) --
// Prune then keeps whatever is already on disk, minus only Exclusions.
func Resolve(spec Spec, agent string) (ids []string, explicit bool) {
	if assigned, ok := spec.Assignments[agent]; ok {
		return assigned, true
	}
	if spec.Flat != nil {
		return without(spec.Flat, spec.Exclusions), true
	}
	return nil, false
}

func without(resolved, excluded []string) []string {
	if len(excluded) == 0 {
		return resolved
	}
	drop := make(map[string]struct{}, len(excluded))
	for _, id := range excluded {
		drop[id] = struct{}{}
	}
	kept := make([]string, 0, len(resolved))
	for _, id := range resolved {
		if _, excludedID := drop[id]; excludedID {
			continue
		}
		kept = append(kept, id)
	}
	return kept
}

// Prune removes every skill directory under each declared agent's own
// skills directory that is not in that agent's resolved set. An agent
// neither spec.SkillsDir nor skillsDirs knows how to express, or whose
// skills directory does not exist in tree, is left untouched. Prune never
// removes anything outside a known adapter's own skills directory. With no
// explicit set, it keeps everything except Exclusions.
func Prune(tree string, spec Spec) error {
	for _, agent := range spec.Agents {
		relDir, ok := spec.SkillsDir[agent]
		if !ok {
			relDir, ok = skillsDirs[agent]
		}
		if !ok {
			continue
		}

		dir := filepath.Join(tree, relDir)
		entries, err := os.ReadDir(dir)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return fmt.Errorf("read skills directory %q: %w", dir, err)
		}

		ids, explicit := Resolve(spec, agent)
		if !explicit {
			names := make([]string, 0, len(entries))
			for _, entry := range entries {
				names = append(names, entry.Name())
			}
			ids = without(names, spec.Exclusions)
		}

		keep := make(map[string]struct{}, len(ids))
		for _, id := range ids {
			keep[id] = struct{}{}
		}

		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}
			if _, kept := keep[entry.Name()]; kept {
				continue
			}
			if err := os.RemoveAll(filepath.Join(dir, entry.Name())); err != nil {
				return fmt.Errorf("prune skill %q from %q: %w", entry.Name(), dir, err)
			}
		}
	}

	return nil
}
