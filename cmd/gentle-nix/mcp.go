package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/0xErwin1/gentle-ai-nix/internal/mcp"
)

// runMCP implements "gentle-nix mcp": it writes every declared
// programs.gentle-ai.mcpServers / providers.<name>.mcpServers entry into
// the rendered tree, exactly the way the pinned Gentle AI fork's own
// internal/components/mcp/declared.go used to render them from the
// document's own "mcpServers" fields -- see internal/mcp for the exact
// formats and per-adapter rules. Codex is left untouched here; the Nix
// module routes it through the existing TOML merger instead.
//
// "gentle-nix mcp migrate-pi" is a bounded runtime helper (see
// runMCPMigratePi) that carries a host's legacy Pi adapter MCP servers into
// Pi's native mcp.json before the adapter is retired.
func runMCP(args []string) (int, error) {
	if len(args) > 0 && args[0] == "migrate-pi" {
		return runMCPMigratePi(args[1:])
	}

	fs := flag.NewFlagSet("mcp", flag.ExitOnError)
	tree := fs.String("tree", "", "rendered tree to write declared MCP servers into")
	specPath := fs.String("spec", "", "JSON file describing the MCP servers to write (see internal/mcp.Spec)")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *tree == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix mcp: --tree is required")
		return 2, nil
	}
	if *specPath == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix mcp: --spec is required")
		return 2, nil
	}

	raw, err := os.ReadFile(*specPath)
	if err != nil {
		return 0, fmt.Errorf("read spec %q: %w", *specPath, err)
	}

	var spec mcp.Spec
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&spec); err != nil {
		fmt.Fprintf(os.Stderr, "gentle-nix mcp: invalid spec %q: %v\n", *specPath, err)
		return 2, nil
	}

	if err := mcp.WriteTree(*tree, spec); err != nil {
		var validationErr mcp.ValidationError
		if errors.As(err, &validationErr) {
			// A mistake in the declared spec, the same way an unsupported
			// role adapter is a configuration mistake for gentle-nix
			// roles: its own exit code, not main's generic
			// "gentle-nix: %v" / 1.
			fmt.Fprintf(os.Stderr, "gentle-nix mcp: %v\n", err)
			return 2, nil
		}
		return 0, err
	}

	return 0, nil
}

// runMCPMigratePi implements "gentle-nix mcp migrate-pi --agent-dir <dir>":
// it copies only the mcpServers entries <agentDir>/mcp-adapter.json declares
// that <agentDir>/mcp.json does not already have, with existing native
// entries winning and every unrelated top-level key surviving. The legacy
// adapter file is read-only here; retiring it is the Nix-side guarded
// activation's job, after this helper has succeeded and the native Engram
// plugin is installed. --agent-dir must be absolute: this runs against the
// host's real Pi agent directory, and a relative path would silently
// resolve against whatever working directory the activation runs from.
func runMCPMigratePi(args []string) (int, error) {
	fs := flag.NewFlagSet("mcp migrate-pi", flag.ExitOnError)
	agentDir := fs.String("agent-dir", "", "absolute path to the Pi agent directory (e.g. /home/user/.pi/agent)")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *agentDir == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix mcp migrate-pi: --agent-dir is required")
		return 2, nil
	}
	if !filepath.IsAbs(*agentDir) {
		fmt.Fprintf(os.Stderr, "gentle-nix mcp migrate-pi: --agent-dir must be an absolute path, got %q\n", *agentDir)
		return 2, nil
	}

	result, err := mcp.MigratePi(*agentDir)
	if err != nil {
		return 0, err
	}

	switch {
	case len(result.Copied) == 0 && len(result.Skipped) == 0:
		fmt.Println("gentle-nix mcp migrate-pi: nothing to migrate")
	case len(result.Copied) == 0:
		fmt.Printf("gentle-nix mcp migrate-pi: nothing to copy; already native: %s\n", strings.Join(result.Skipped, ", "))
	default:
		fmt.Printf("gentle-nix mcp migrate-pi: copied into mcp.json: %s\n", strings.Join(result.Copied, ", "))
		if len(result.Skipped) > 0 {
			fmt.Printf("gentle-nix mcp migrate-pi: kept existing native entries: %s\n", strings.Join(result.Skipped, ", "))
		}
	}
	return 0, nil
}
