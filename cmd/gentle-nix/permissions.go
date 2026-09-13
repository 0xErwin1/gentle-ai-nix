package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/permissions"
)

// runPermissions implements "gentle-nix permissions": it unions every
// declared programs.gentle-ai.permissions.{allow,deny,ask} rule into
// .claude/settings.json, exactly the way the pinned Gentle AI fork's own
// internal/components/permissions/declared.go used to union them from the
// document's own "permissions" field -- see internal/permissions for the
// exact union semantics and why only Claude Code is supported.
func runPermissions(args []string) (int, error) {
	fs := flag.NewFlagSet("permissions", flag.ExitOnError)
	tree := fs.String("tree", "", "rendered tree to merge declared permission rules into")
	specPath := fs.String("spec", "", "JSON file describing the permission rules to write (see internal/permissions.Spec)")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *tree == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix permissions: --tree is required")
		return 2, nil
	}
	if *specPath == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix permissions: --spec is required")
		return 2, nil
	}

	raw, err := os.ReadFile(*specPath)
	if err != nil {
		return 0, fmt.Errorf("read spec %q: %w", *specPath, err)
	}

	var spec permissions.Spec
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&spec); err != nil {
		fmt.Fprintf(os.Stderr, "gentle-nix permissions: invalid spec %q: %v\n", *specPath, err)
		return 2, nil
	}

	if err := permissions.Render(*tree, spec); err != nil {
		return 0, err
	}

	return 0, nil
}
