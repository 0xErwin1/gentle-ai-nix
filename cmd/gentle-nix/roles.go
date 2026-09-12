package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/roles"
)

// runRoles implements "gentle-nix roles": it writes every declared
// programs.gentle-ai.roles entry into the rendered tree, exactly the way
// the pinned Gentle AI fork's own internal/render/role_provider.go and
// internal/render/opencode.go used to render them from the document's own
// "roles" field -- see internal/roles for the exact formats and per-adapter
// rules.
func runRoles(args []string) (int, error) {
	fs := flag.NewFlagSet("roles", flag.ExitOnError)
	tree := fs.String("tree", "", "rendered tree to write declared roles into")
	specPath := fs.String("spec", "", "JSON file describing the roles to write (see internal/roles.Spec)")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *tree == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix roles: --tree is required")
		return 2, nil
	}
	if *specPath == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix roles: --spec is required")
		return 2, nil
	}

	raw, err := os.ReadFile(*specPath)
	if err != nil {
		return 0, fmt.Errorf("read spec %q: %w", *specPath, err)
	}

	var spec roles.Spec
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&spec); err != nil {
		fmt.Fprintf(os.Stderr, "gentle-nix roles: invalid spec %q: %v\n", *specPath, err)
		return 2, nil
	}

	if err := roles.WriteTree(*tree, spec); err != nil {
		var validationErr roles.ValidationError
		if errors.As(err, &validationErr) {
			// A mistake in the declared spec, the same way an unknown
			// provider is a configuration mistake for gentle-nix settings:
			// its own exit code, not main's generic "gentle-nix: %v" / 1.
			fmt.Fprintf(os.Stderr, "gentle-nix roles: %v\n", err)
			return 2, nil
		}
		return 0, err
	}

	return 0, nil
}
