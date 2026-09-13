// Package mcp renders gentle-ai-nix's own declared MCP servers onto a
// rendered Gentle AI tree. Declaring, naming, or wiring an MCP server for a
// client is not something Gentle AI does imperatively -- it only wires its
// own fixed servers such as Context7 -- so `mcpServers` and the per-provider
// `providers.<id>.mcpServers` leave the document entirely: this package
// post-processes the tree "gentle-ai config render" already produced, the
// same way gentle-nix roles and gentle-nix pi routing post-process it for
// their own concerns (see internal/roles, internal/pirouting).
//
// This package reproduces exactly what the pinned Gentle AI fork's own
// internal/components/mcp/declared.go wrote for the plain-JSON and
// OpenCode-shaped adapters, so the bytes gentle-nix writes match what the
// fork's renderer used to write for the same declared servers. Codex is
// deliberately absent here: its MCP config lives in config.toml, which this
// package never writes (see the package doc on internal/settings for why
// TOML stays with the existing Python merger) -- the Nix module builds
// Codex's TOML fragment itself with `pkgs.formats.toml` and merges it the
// same way it already merges Codex's other settings.
//
// Hermes and four IDE-style clients (windsurf, trae-ide, vscode-copilot,
// antigravity) are also covered here now, matching the fork's own adapters:
//
//   - windsurf and antigravity write the fork's own plain "mcpServers" JSON
//     shape at a path this package already knows how to compute (see
//     mcp.go's own writeAgent), the same as gemini-cli or cursor.
//   - vscode-copilot and trae-ide write that same shape too, but at a path
//     that differs by OS (the fork's own adapters resolve it from
//     runtime.GOOS) -- gentle-nix has no OS of its own to consult, so the
//     Nix module resolves the OS-variant path itself and supplies it
//     through Spec.Paths (gentle-nix mcp's own --spec paths block); WriteTree
//     refuses either client outright when its own agent has a declared
//     server but no entry in Paths.
//   - hermes writes into a single YAML file (~/.hermes/config.yaml) via a Go
//     port of the pinned fork's own hand-rolled
//     filemerge.UpsertYAMLMCPServerBlock (see yaml.go); it only knows how to
//     express a stdio server (command/args/env), so a declared hermes
//     server with a url is refused, matching the fork's own YAML writer,
//     which never grew a remote-server shape either.
package mcp

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/0xErwin1/gentle-ai-nix/internal/settings"
)

// ValidationError marks a problem with the declared spec itself -- a server
// with neither a command nor a url, an empty name, an adapter that cannot
// express MCP at all -- as opposed to an I/O failure while writing the
// result. gentle-nix mcp uses this distinction to exit 2 for the former and
// 1 for the latter, the same split gentle-nix roles and gentle-nix pi
// routing already make.
type ValidationError struct{ msg string }

func (e ValidationError) Error() string { return e.msg }

func validationErrorf(format string, args ...any) error {
	return ValidationError{msg: fmt.Sprintf(format, args...)}
}

// Server is one MCP server as the document declares it, in the same shape
// mcpServerType in modules/home-manager.nix renders it. Enabled is a
// pointer so an omitted flag stays absent rather than declaring the server
// disabled -- mirrors the pinned fork's own config.MCPServer.
type Server struct {
	Command string            `json:"command,omitempty"`
	Args    []string          `json:"args,omitempty"`
	Env     map[string]string `json:"env,omitempty"`
	URL     string            `json:"url,omitempty"`
	Headers map[string]string `json:"headers,omitempty"`
	Enabled *bool             `json:"enabled,omitempty"`
}

func (s Server) enabled() bool {
	if s.Enabled == nil {
		return true
	}
	return *s.Enabled
}

// Spec is gentle-nix mcp's own input contract: the clients the document
// enables, the flat server set every one of them takes unless overridden,
// and the per-agent overrides that fully replace the flat set for that
// agent only.
type Spec struct {
	Agents      []string                     `json:"agents,omitempty"`
	Servers     map[string]Server            `json:"servers,omitempty"`
	Assignments map[string]map[string]Server `json:"assignments,omitempty"`

	// Paths overrides the destination this package writes an agent's MCP
	// config to, keyed by agent name and holding a path relative to the
	// rendered tree. It always wins over any built-in default (see
	// writeAgent) and is the only way an OS-variant client (vscode-copilot,
	// trae-ide) can be written at all -- this package carries no built-in
	// path for either, unlike windsurf, antigravity and hermes, whose
	// defaults hold for every OS (see the package doc).
	Paths map[string]string `json:"paths,omitempty"`
}

// codexAgent is handled entirely by the Nix module's own TOML merger; this
// package recognizes it as a supported agent (so declaring a server for
// codex alongside another client is never refused) but never writes
// anything for it.
const codexAgent = "codex"

// supportedAgents are every adapter this package (plus the module's own
// Codex TOML path) knows how to express an MCP server for, mirroring the
// pinned fork's own set of adapters whose MCPStrategy is not "unsupported".
var supportedAgents = map[string]bool{
	"claude-code":    true,
	"cursor":         true,
	"kimi":           true,
	"kiro-ide":       true,
	"pi":             true,
	"gemini-cli":     true,
	"qwen-code":      true,
	"openclaw":       true,
	"opencode":       true,
	"kilocode":       true,
	"windsurf":       true,
	"antigravity":    true,
	"vscode-copilot": true,
	"trae-ide":       true,
	"hermes":         true,
	codexAgent:       true,
}

// pathRequiredAgents are the agents supportedAgents carries whose location
// this package cannot compute on its own: the fork's own adapters resolve
// them from runtime.GOOS, which gentle-nix has no equivalent of, so
// Spec.Paths must name them explicitly -- see the package doc.
var pathRequiredAgents = map[string]bool{
	"vscode-copilot": true,
	"trae-ide":       true,
}

// stdioOnlyAgents are agents whose writer here cannot express a remote (url)
// server at all -- hermes' YAML shape mirrors the fork's own hand-rolled
// filemerge.UpsertYAMLMCPServerBlock, which only ever wrote command/args/env.
var stdioOnlyAgents = map[string]bool{
	"hermes": true,
}

func validateServer(path, name string, server Server) error {
	if name == "" {
		return validationErrorf("%s: a server name must not be empty", path)
	}
	if (server.Command == "") == (server.URL == "") {
		return validationErrorf("%s.%s: a server must set exactly one of command or url", path, name)
	}
	return nil
}

// Validate reports the first problem found in spec: a server with neither
// (or both) a command and a url, an empty server name, or a declared client
// that cannot express MCP at all.
func Validate(spec Spec) error {
	for name, server := range spec.Servers {
		if err := validateServer("servers", name, server); err != nil {
			return err
		}
	}
	for agent, servers := range spec.Assignments {
		for name, server := range servers {
			if err := validateServer("assignments."+agent, name, server); err != nil {
				return err
			}
		}
	}

	if len(spec.Servers) == 0 && len(spec.Assignments) == 0 {
		return nil
	}

	var unsupported []string
	for _, agent := range spec.Agents {
		if declaredFor(spec, agent) == nil {
			continue
		}
		if !supportedAgents[agent] {
			unsupported = append(unsupported, agent)
		}
	}
	if len(unsupported) > 0 {
		sort.Strings(unsupported)
		return validationErrorf(
			"MCP servers were declared but %s expresses no MCP servers; remove the servers from programs.gentle-ai.mcpServers/providers.<name>.mcpServers or drop that client, then rebuild",
			strings.Join(unsupported, ", "),
		)
	}

	var missingPaths []string
	for _, agent := range spec.Agents {
		servers := declaredFor(spec, agent)
		if len(servers) == 0 {
			continue
		}
		if pathRequiredAgents[agent] {
			if _, ok := spec.Paths[agent]; !ok {
				missingPaths = append(missingPaths, agent)
			}
		}
		if stdioOnlyAgents[agent] {
			for name, server := range servers {
				if server.URL != "" {
					return validationErrorf(
						"assignments.%[1]s.%[2]s (or servers.%[2]s): %[1]s only expresses a stdio MCP server (command/args/env); a url-based server has no equivalent in its config file",
						agent, name,
					)
				}
			}
		}
	}
	if len(missingPaths) > 0 {
		sort.Strings(missingPaths)
		joined := strings.Join(missingPaths, ", ")
		return validationErrorf(
			"MCP servers were declared for %s, but gentle-nix mcp has no built-in path for it (its config location is OS-variant); pass paths.<agent> in the spec (the Nix module resolves this from clientLocations)",
			joined,
		)
	}

	return nil
}

// declaredFor resolves what one agent receives: its own assignment block
// when it has one (a full replace, never a union with the flat set), the
// flat set otherwise. Mirrors the pinned fork's own mcpServersForAdapter.
func declaredFor(spec Spec, agent string) map[string]Server {
	if assigned, ok := spec.Assignments[agent]; ok {
		return assigned
	}
	return spec.Servers
}

func sortedNames(servers map[string]Server) []string {
	names := make([]string, 0, len(servers))
	for name := range servers {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// WriteTree validates spec and, for every declared agent among spec.Agents,
// writes exactly what the fork's own MCP injector used to write for it. An
// agent with nothing declared for it (an empty flat set and no assignment
// of its own) is left untouched, and codex is always left untouched --
// see the package doc.
func WriteTree(tree string, spec Spec) error {
	if err := Validate(spec); err != nil {
		return err
	}

	for _, agent := range spec.Agents {
		servers := declaredFor(spec, agent)
		if len(servers) == 0 || agent == codexAgent {
			continue
		}

		if err := writeAgent(tree, agent, servers, spec.Paths); err != nil {
			return err
		}
	}

	return nil
}

// windsurfMCPConfigRel and antigravityMCPConfigRel are OS-invariant: both
// adapters resolve their MCPConfigPath under a home-relative directory that
// never varies by runtime.GOOS (windsurf's GlobalConfigDir; antigravity's
// own variant directory -- see hermesMCPConfigRel's sibling doc on
// internal/settings' antigravity fallback for why that one is a run-time,
// not an OS, choice).
const (
	windsurfMCPConfigRel    = ".codeium/windsurf/mcp_config.json"
	antigravityMCPConfigRel = ".gemini/antigravity-cli/mcp_config.json"
	hermesMCPConfigRel      = ".hermes/config.yaml"
)

func writeAgent(tree, agent string, servers map[string]Server, paths map[string]string) error {
	resolve := func(builtinRel string) string {
		if override, ok := paths[agent]; ok {
			return filepath.Join(tree, override)
		}
		return filepath.Join(tree, builtinRel)
	}

	switch agent {
	case "claude-code":
		return writeSeparateFiles(tree, filepath.Join(tree, ".claude", "mcp"), servers)
	case "cursor":
		return mergePlain(filepath.Join(tree, ".cursor", "mcp.json"), servers)
	case "kimi":
		return mergePlain(filepath.Join(tree, ".kimi", "mcp.json"), servers)
	case "kiro-ide":
		return mergePlain(filepath.Join(tree, ".kiro", "settings", "mcp.json"), servers)
	case "pi":
		return mergePlain(filepath.Join(tree, ".pi", "agent", "mcp.json"), servers)
	case "gemini-cli", "qwen-code", "openclaw":
		path, ok := settings.ResolvePath(tree, agent)
		if !ok {
			return fmt.Errorf("resolve MCP settings path for %q", agent)
		}
		return mergePlain(path, servers)
	case "opencode", "kilocode":
		path, ok := settings.ResolvePath(tree, agent)
		if !ok {
			return fmt.Errorf("resolve MCP settings path for %q", agent)
		}
		return mergeOpenCode(path, servers)
	case "windsurf":
		return mergePlain(resolve(windsurfMCPConfigRel), servers)
	case "antigravity":
		return mergePlain(resolve(antigravityMCPConfigRel), servers)
	case "vscode-copilot", "trae-ide":
		// Validate already refused either agent when it has a declared
		// server but no entry in paths -- see pathRequiredAgents. Checked
		// again here rather than trusted, so a caller that skips Validate
		// (e.g. a future direct WriteTree caller) never writes to the tree
		// root instead of failing loudly.
		override, ok := paths[agent]
		if !ok {
			return fmt.Errorf("gentle-nix mcp: no MCP path known for %q; pass paths.%s in the spec", agent, agent)
		}
		return mergePlain(filepath.Join(tree, override), servers)
	case "hermes":
		return mergeYAML(resolve(hermesMCPConfigRel), servers)
	default:
		// Validate already refused an unsupported agent with a declared
		// server; an agent that reaches here with nothing declared for it
		// is already skipped by WriteTree, so this is unreachable in
		// practice and only guards against a future supportedAgents entry
		// that forgets to add its own case.
		return fmt.Errorf("gentle-nix mcp: no writer wired for agent %q", agent)
	}
}

// writeSeparateFiles mirrors the fork's own StrategySeparateMCPFiles: one
// file per server, named after it, each key-preserving-merged with
// {"mcpServers": {<name>: entry}} the same way every other plain target is.
func writeSeparateFiles(tree, dir string, servers map[string]Server) error {
	for _, name := range sortedNames(servers) {
		path := filepath.Join(dir, name+".json")
		overlay, err := json.Marshal(map[string]any{
			"mcpServers": map[string]any{name: plainEntry(servers[name])},
		})
		if err != nil {
			return fmt.Errorf("encode declared MCP server %q: %w", name, err)
		}
		if err := settings.MergeInto(path, overlay); err != nil {
			return err
		}
	}
	return nil
}

// mergePlain mirrors the fork's own plain "mcpServers" shape, merged as one
// overlay carrying every declared server for that target.
func mergePlain(path string, servers map[string]Server) error {
	entries := make(map[string]any, len(servers))
	for name, server := range servers {
		entries[name] = plainEntry(server)
	}
	overlay, err := json.Marshal(map[string]any{"mcpServers": entries})
	if err != nil {
		return fmt.Errorf("encode declared MCP servers: %w", err)
	}
	return settings.MergeInto(path, overlay)
}

// mergeOpenCode mirrors the fork's own OpenCode-shaped "mcp" key, merged as
// one overlay carrying every declared server for that target.
func mergeOpenCode(path string, servers map[string]Server) error {
	entries := make(map[string]any, len(servers))
	for name, server := range servers {
		entries[name] = openCodeEntry(server)
	}
	overlay, err := json.Marshal(map[string]any{"mcp": entries})
	if err != nil {
		return fmt.Errorf("encode declared MCP servers: %w", err)
	}
	return settings.MergeInto(path, overlay)
}

// plainEntry is the shape every adapter outside the OpenCode family uses --
// mirrors the fork's own plainServerEntry exactly, including that it never
// carries an "enabled" field at all: a plain client has no way to express a
// disabled server, so Enabled is silently ignored here the same way the
// fork's own plainServerEntry ignores it.
func plainEntry(server Server) map[string]any {
	entry := map[string]any{}
	if server.URL != "" {
		entry["url"] = server.URL
	} else {
		entry["command"] = server.Command
		if len(server.Args) > 0 {
			entry["args"] = server.Args
		}
	}
	if len(server.Env) > 0 {
		entry["env"] = server.Env
	}
	if len(server.Headers) > 0 {
		entry["headers"] = server.Headers
	}
	return entry
}

// openCodeEntry mirrors the fork's own declaredServerOverlay for OpenCode
// and Kilocode: a combined command list instead of command+args, "environment"
// instead of "env", and an "enabled" field that is always present.
func openCodeEntry(server Server) map[string]any {
	entry := map[string]any{}
	if server.URL != "" {
		entry["type"] = "remote"
		entry["url"] = server.URL
	} else {
		entry["type"] = "local"
		entry["command"] = append([]string{server.Command}, server.Args...)
	}
	if len(server.Env) > 0 {
		entry["environment"] = server.Env
	}
	if len(server.Headers) > 0 {
		entry["headers"] = server.Headers
	}
	entry["enabled"] = server.enabled()
	return entry
}

// mergeYAML mirrors the fork's own hand-rolled YAML MCP writer for hermes
// (filemerge.UpsertYAMLMCPServerBlock, ported in yaml.go): every declared
// server is upserted, one at a time in name order for determinism, into the
// mcp_servers: block of the YAML file at path, creating it if absent.
// Validate already refused a url-based server for a stdio-only agent before
// this runs.
func mergeYAML(path string, servers map[string]Server) error {
	existing, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("read YAML config %q: %w", path, err)
	}

	content := string(existing)
	for _, name := range sortedNames(servers) {
		server := servers[name]
		content = upsertYAMLMCPServerBlock(content, name, server.Command, server.Args, server.Env)
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create YAML config directory for %q: %w", path, err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		return fmt.Errorf("write YAML config %q: %w", path, err)
	}
	return nil
}
