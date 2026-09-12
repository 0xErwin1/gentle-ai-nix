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
// A handful of clients the fork itself never wired an MCP strategy for at
// all -- hermes and the OS-variant IDE clients (windsurf, trae-ide,
// vscode-copilot, antigravity) -- are refused here rather than silently
// dropped, the same way an adapter that cannot express a role is refused by
// internal/roles.
package mcp

import (
	"encoding/json"
	"fmt"
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
}

// codexAgent is handled entirely by the Nix module's own TOML merger; this
// package recognizes it as a supported agent (so declaring a server for
// codex alongside another client is never refused) but never writes
// anything for it.
const codexAgent = "codex"

// supportedAgents are every adapter this package (plus the module's own
// Codex TOML path) knows how to express an MCP server for, mirroring the
// pinned fork's own set of adapters whose MCPStrategy is not "unsupported".
// hermes and the OS-variant IDE clients (windsurf, trae-ide, vscode-copilot,
// antigravity) are deliberately absent: the fork never wired an MCP
// strategy for them either.
var supportedAgents = map[string]bool{
	"claude-code": true,
	"cursor":      true,
	"kimi":        true,
	"kiro-ide":    true,
	"pi":          true,
	"gemini-cli":  true,
	"qwen-code":   true,
	"openclaw":    true,
	"opencode":    true,
	"kilocode":    true,
	codexAgent:    true,
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

		if err := writeAgent(tree, agent, servers); err != nil {
			return err
		}
	}

	return nil
}

func writeAgent(tree, agent string, servers map[string]Server) error {
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
