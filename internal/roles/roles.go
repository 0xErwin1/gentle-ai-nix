// Package roles renders gentle-ai-nix's own declared agent roles onto a
// rendered Gentle AI tree. Renaming or defining roles is not something
// Gentle AI does imperatively, so "roles" leave the document entirely --
// this package post-processes the tree "gentle-ai config render" already
// produced, the way gentle-nix pi routing post-processes it for Pi's own
// routing files (see internal/pirouting).
//
// This package reproduces exactly what the pinned Gentle AI fork's own
// internal/render/role_provider.go, internal/render/opencode.go and
// internal/render/provider_registry.go wrote, so the bytes gentle-nix
// writes match what the fork's renderer used to write for the same
// declared roles: a rename index resolves every reference before anything
// is written, a role a client cannot express is refused rather than
// silently dropped, and a field the document left out stays out of the
// rendered agent.
package roles

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/0xErwin1/gentle-ai-nix/internal/settings"
)

// ValidationError marks a problem with the declared spec itself -- an
// unknown reference, an unsupported mode, an adapter that cannot express a
// role -- as opposed to an I/O failure while writing the result. gentle-nix
// roles uses this distinction to exit 2 for the former and 1 for the
// latter, the same split gentle-nix pi routing and gentle-nix settings
// already make.
type ValidationError struct{ msg string }

func (e ValidationError) Error() string { return e.msg }

func validationErrorf(format string, args ...any) error {
	return ValidationError{msg: fmt.Sprintf(format, args...)}
}

// ModelAssignment is the model a role runs on, in the same shape
// modelAssignmentType in modules/home-manager.nix renders it: a provider
// and a model are both required together, effort is optional.
type ModelAssignment struct {
	Provider string `json:"provider"`
	Model    string `json:"model"`
	Effort   string `json:"effort,omitempty"`
}

// Role is one logical agent role, keyed by id in Spec.Roles. It mirrors the
// fork's own config.Role, minus the id and RoleRef indirection: the id is
// the map key, and a reference is just another key into Spec.Roles.
type Role struct {
	RenderedName string           `json:"renderedName,omitempty"`
	References   []string         `json:"references,omitempty"`
	Description  string           `json:"description,omitempty"`
	Prompt       string           `json:"prompt,omitempty"`
	Tools        []string         `json:"tools,omitempty"`
	Model        *ModelAssignment `json:"model,omitempty"`
	Mode         string           `json:"mode,omitempty"`
	Hidden       *bool            `json:"hidden,omitempty"`
}

// Spec is gentle-nix roles' own input contract: the clients the document
// enables (needed to decide which of them can express a role at all) and
// the roles it declared.
type Spec struct {
	Agents []string        `json:"agents,omitempty"`
	Roles  map[string]Role `json:"roles,omitempty"`
}

// fileRoleDirs are the adapters that keep every role as its own frontmatter
// file, and the directory (relative to the rendered tree) each one reads
// them from. Mirrors the fork's own per-adapter SubAgentsDir for the
// adapters whose SupportsSubAgents() is true.
var fileRoleDirs = map[string]string{
	"claude-code": filepath.Join(".claude", "agents"),
	"cursor":      filepath.Join(".cursor", "agents"),
	"kimi":        filepath.Join(".kimi", "agents"),
	"kiro-ide":    filepath.Join(".kiro", "agents"),
}

// openCodeAgent is the one adapter whose roles live inside a composed
// settings file instead of as their own files -- mirrors the fork's own
// bespokeProviders.
const openCodeAgent = "opencode"

// validModes mirrors the fork's own config.RolePrimary / config.RoleSubagent.
var validModes = map[string]bool{"": true, "primary": true, "subagent": true}

// supportsRoles reports whether agent is one of the five adapters that can
// express a declared role, mirroring the fork's own render.ProviderFor:
// every other adapter -- including one gentle-nix otherwise fully supports,
// like gemini-cli or Pi -- has no notion of a role at all.
func supportsRoles(agent string) bool {
	if agent == openCodeAgent {
		return true
	}
	_, ok := fileRoleDirs[agent]
	return ok
}

// Validate reports the first problem found in spec: an unknown reference,
// an unsupported mode, or a declared client that cannot express a role at
// all. An adapter with no notion of roles is only ever a problem when a
// role was actually declared -- mirrors the fork's own
// selectRenderProvider, which lets such an adapter render everything else
// the document declares and refuses only the roles.
func Validate(spec Spec) error {
	if len(spec.Roles) == 0 {
		return nil
	}

	for id, role := range spec.Roles {
		if !validModes[role.Mode] {
			return validationErrorf("roles.%s.mode: unsupported mode %q", id, role.Mode)
		}
		for _, reference := range role.References {
			if _, ok := spec.Roles[reference]; !ok {
				return validationErrorf("roles.%s.references: %q does not name a declared role", id, reference)
			}
		}
	}

	var unsupported []string
	for _, agent := range spec.Agents {
		if !supportsRoles(agent) {
			unsupported = append(unsupported, agent)
		}
	}
	if len(unsupported) > 0 {
		sort.Strings(unsupported)
		return validationErrorf(
			"roles were declared but %s expresses no agent roles; remove the roles from programs.gentle-ai.roles or drop that client, then rebuild",
			strings.Join(unsupported, ", "),
		)
	}

	return nil
}

// renderedNamesFor is the rename index the fork's own renderedRoleNames
// builds: every id maps to the name it is rendered as, its own id when the
// document set no renderedName. It is built once over every declared role,
// and every reference is resolved through it -- never through the id
// directly -- so a rename is one edit.
func renderedNamesFor(roles map[string]Role) map[string]string {
	rendered := make(map[string]string, len(roles))
	for id, role := range roles {
		rendered[id] = renderedName(id, role)
	}
	return rendered
}

func renderedName(id string, role Role) string {
	if role.RenderedName != "" {
		return role.RenderedName
	}
	return id
}

func sortedRoleIDs(roles map[string]Role) []string {
	ids := make([]string, 0, len(roles))
	for id := range roles {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

// WriteTree validates spec and, for every declared role and every adapter
// among spec.Agents that can express one, writes exactly what the fork's
// own renderer used to write for it. A spec with no roles is a no-op: it
// touches nothing in tree.
func WriteTree(tree string, spec Spec) error {
	if err := Validate(spec); err != nil {
		return err
	}
	if len(spec.Roles) == 0 {
		return nil
	}

	rendered := renderedNamesFor(spec.Roles)
	ids := sortedRoleIDs(spec.Roles)

	agents := make([]string, len(spec.Agents))
	copy(agents, spec.Agents)
	sort.Strings(agents)

	for _, agent := range agents {
		if dir, ok := fileRoleDirs[agent]; ok {
			if err := writeFileRoles(tree, dir, spec.Roles, ids, rendered); err != nil {
				return err
			}
		}
	}

	if containsOpenCode(spec.Agents) {
		if err := writeOpenCodeRoles(tree, spec.Roles, ids, rendered); err != nil {
			return err
		}
	}

	return nil
}

func containsOpenCode(agents []string) bool {
	for _, agent := range agents {
		if agent == openCodeAgent {
			return true
		}
	}
	return false
}

// writeFileRoles mirrors the fork's own RoleProvider.Stage: one frontmatter
// file per role, named after its rendered name, in the adapter's own
// sub-agent directory.
func writeFileRoles(tree, relDir string, roles map[string]Role, ids []string, rendered map[string]string) error {
	dir := filepath.Join(tree, relDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create sub-agent directory %q: %w", dir, err)
	}

	for _, id := range ids {
		name := rendered[id]
		path := filepath.Join(dir, name+".md")
		if err := os.WriteFile(path, roleDocument(roles[id], name, rendered), 0o644); err != nil {
			return fmt.Errorf("write sub-agent %q: %w", name, err)
		}
	}

	return nil
}

// roleDocument mirrors the fork's own roleDocument: only what the role
// declared is emitted, in this exact order and with this exact separator,
// so a rebuild never reorders or reformats a file an operator did not
// change the declaration of. name is the rendered name this role's own
// file was written under.
func roleDocument(role Role, name string, rendered map[string]string) []byte {
	lines := []string{"---", "name: " + name}

	if role.Description != "" {
		lines = append(lines, "description: "+role.Description)
	}
	if role.Model != nil {
		lines = append(lines, "model: "+role.Model.Model)
		if role.Model.Effort != "" {
			lines = append(lines, "effort: "+role.Model.Effort)
		}
	}
	if len(role.Tools) > 0 {
		lines = append(lines, "tools: "+strings.Join(role.Tools, ", "))
	}
	if references := referencedNames(role, rendered); len(references) > 0 {
		lines = append(lines, "references: "+strings.Join(references, ", "))
	}
	lines = append(lines, "---", "")

	document := strings.Join(lines, "\n")
	if role.Prompt != "" {
		document += role.Prompt + "\n"
	}

	return []byte(document)
}

// referencedNames resolves each reference to the name it was rendered as,
// sorted for determinism -- mirrors the fork's own referencedNames.
func referencedNames(role Role, rendered map[string]string) []string {
	names := make([]string, 0, len(role.References))
	for _, reference := range role.References {
		name, ok := rendered[reference]
		if !ok {
			name = reference
		}
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// openCodeSettingsPath is where OpenCodeProvider merges every declared
// role: settings.ResolvePath prefers an opencode.jsonc already present in
// the tree, exactly the way the fork's own opencode adapter's SettingsPath
// does.
func openCodeSettingsPath(tree string) (string, error) {
	path, ok := settings.ResolvePath(tree, openCodeAgent)
	if !ok {
		return "", fmt.Errorf("resolve opencode settings path")
	}
	return path, nil
}

// writeOpenCodeRoles mirrors the fork's own OpenCodeProvider.Render +
// Merge: every declared role becomes one agent.<name> entry, merged as a
// single overlay into the client's own settings file.
func writeOpenCodeRoles(tree string, roles map[string]Role, ids []string, rendered map[string]string) error {
	agents := make(map[string]any, len(ids))
	for _, id := range ids {
		entry, err := openCodeAgentEntry(roles[id], rendered)
		if err != nil {
			return err
		}
		agents[rendered[id]] = entry
	}

	overlay, err := json.Marshal(map[string]any{"agent": agents})
	if err != nil {
		return fmt.Errorf("encode OpenCode roles overlay: %w", err)
	}

	path, err := openCodeSettingsPath(tree)
	if err != nil {
		return err
	}

	return settings.MergeInto(path, overlay)
}

// openCodeAgentEntry projects one declared role onto the agent shape
// OpenCode reads -- mirrors the fork's own openCodeAgentEntry exactly,
// including the __replace__ sentinel on tools and delegation so a declared
// toolset or reference list replaces what is already on disk instead of
// merging into it.
func openCodeAgentEntry(role Role, rendered map[string]string) (map[string]any, error) {
	entry := map[string]any{}

	if role.Description != "" {
		entry["description"] = role.Description
	}
	if role.Prompt != "" {
		entry["prompt"] = role.Prompt
	}
	if role.Mode != "" {
		entry["mode"] = role.Mode
	}
	if role.Hidden != nil {
		entry["hidden"] = *role.Hidden
	}
	if role.Model != nil {
		entry["model"] = role.Model.Provider + "/" + role.Model.Model
		if role.Model.Effort != "" {
			entry["variant"] = role.Model.Effort
		}
	}
	if len(role.Tools) > 0 {
		entry["tools"] = map[string]any{settings.ReplaceSentinel: openCodeTools(role.Tools)}
	}

	if len(role.References) == 0 {
		return entry, nil
	}

	delegation := map[string]any{"*": "deny"}
	for _, reference := range role.References {
		name, ok := rendered[reference]
		if !ok {
			return nil, fmt.Errorf("resolve OpenCode role %q", reference)
		}
		delegation[name] = "allow"
	}
	entry["permission"] = map[string]any{"task": map[string]any{settings.ReplaceSentinel: delegation}}

	return entry, nil
}

// openCodeTools turns the declared allow-list into the enable map OpenCode
// reads -- mirrors the fork's own openCodeTools.
func openCodeTools(tools []string) map[string]any {
	enabled := map[string]any{"*": false}
	for _, tool := range tools {
		enabled[strings.ToLower(tool)] = true
	}
	return enabled
}
