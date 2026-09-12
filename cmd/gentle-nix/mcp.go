package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/mcp"
)

// runMCP implements "gentle-nix mcp": it writes every declared
// programs.gentle-ai.mcpServers / providers.<name>.mcpServers entry into
// the rendered tree, exactly the way the pinned Gentle AI fork's own
// internal/components/mcp/declared.go used to render them from the
// document's own "mcpServers" fields -- see internal/mcp for the exact
// formats and per-adapter rules. Codex is left untouched here; the Nix
// module routes it through the existing TOML merger instead.
func runMCP(args []string) (int, error) {
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
