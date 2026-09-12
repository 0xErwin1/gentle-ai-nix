package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/pirouting"
)

// runPi dispatches "gentle-nix pi <subcommand>". "routing" is the only
// subcommand today; the nesting exists so a later Pi-only concern (packages
// already live under gentle-nix provision's own flags) has somewhere to go
// without a new top-level verb.
func runPi(args []string) (int, error) {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "usage: gentle-nix pi routing [flags]")
		return 2, nil
	}

	switch args[0] {
	case "routing":
		return runPiRouting(args[1:])
	default:
		fmt.Fprintf(os.Stderr, "gentle-nix pi: unknown subcommand %q\n", args[0])
		return 2, nil
	}
}

// runPiRouting implements "gentle-nix pi routing": it writes
// .pi/gentle-ai/profiles.json, .pi/gentle-ai/models.json, and the
// orchestrator defaults merged into .pi/agent/settings.json, exactly the
// files the pinned Gentle AI fork used to render from the document's
// providers.pi block -- see internal/pirouting for the exact formats and
// precedence.
func runPiRouting(args []string) (int, error) {
	fs := flag.NewFlagSet("pi routing", flag.ExitOnError)
	tree := fs.String("tree", "", "rendered tree to write Pi's routing into")
	specPath := fs.String("spec", "", "JSON file describing the routing to write (see internal/pirouting.Spec)")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *tree == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix pi routing: --tree is required")
		return 2, nil
	}
	if *specPath == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix pi routing: --spec is required")
		return 2, nil
	}

	raw, err := os.ReadFile(*specPath)
	if err != nil {
		return 0, fmt.Errorf("read spec %q: %w", *specPath, err)
	}

	var spec pirouting.Spec
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&spec); err != nil {
		fmt.Fprintf(os.Stderr, "gentle-nix pi routing: invalid spec %q: %v\n", *specPath, err)
		return 2, nil
	}

	presets, err := pirouting.DecodePresets(spec.Presets)
	if err != nil {
		fmt.Fprintf(os.Stderr, "gentle-nix pi routing: %v\n", err)
		return 2, nil
	}

	if err := pirouting.WriteTree(*tree, spec, presets); err != nil {
		var validationErr pirouting.ValidationError
		if errors.As(err, &validationErr) {
			// A mistake in the declared spec, the same way an unknown
			// provider is a configuration mistake for gentle-nix settings:
			// its own exit code, not main's generic "gentle-nix: %v" / 1.
			fmt.Fprintf(os.Stderr, "gentle-nix pi routing: %v\n", err)
			return 2, nil
		}
		return 0, err
	}

	return 0, nil
}
