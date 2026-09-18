package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/pimodels"
)

// runPiModels implements "gentle-nix pi models": it writes Pi's own
// custom-provider overlay, .pi/agent/models.json, exactly as the declared
// providers.pi.modelProviders spell it -- see internal/pimodels for why the
// file exists (the --no-extensions reviewer path) and why nothing here
// validates Pi's own provider schema.
func runPiModels(args []string) (int, error) {
	fs := flag.NewFlagSet("pi models", flag.ExitOnError)
	tree := fs.String("tree", "", "rendered tree to write Pi's custom providers into")
	specPath := fs.String("spec", "", "JSON file describing the providers to write (see internal/pimodels.Spec)")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *tree == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix pi models: --tree is required")
		return 2, nil
	}
	if *specPath == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix pi models: --spec is required")
		return 2, nil
	}

	raw, err := os.ReadFile(*specPath)
	if err != nil {
		return 0, fmt.Errorf("read spec %q: %w", *specPath, err)
	}

	var spec pimodels.Spec
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&spec); err != nil {
		fmt.Fprintf(os.Stderr, "gentle-nix pi models: invalid spec %q: %v\n", *specPath, err)
		return 2, nil
	}

	if err := pimodels.WriteTree(*tree, spec); err != nil {
		var validationErr pimodels.ValidationError
		if errors.As(err, &validationErr) {
			// A mistake in the declared spec, the same way a bad profile
			// name is a configuration mistake for gentle-nix pi routing:
			// its own exit code, not main's generic "gentle-nix: %v" / 1.
			fmt.Fprintf(os.Stderr, "gentle-nix pi models: %v\n", err)
			return 2, nil
		}
		return 0, err
	}

	return 0, nil
}
