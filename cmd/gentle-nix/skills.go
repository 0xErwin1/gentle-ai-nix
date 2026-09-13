package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/skills"
)

// runSkills implements "gentle-nix skills": it prunes every enabled
// adapter's skills directory down to what that adapter actually resolves
// to -- its own providers.<id>.skills assignment when it has one, or the
// flat skills list minus skillExclusions otherwise -- exactly the
// resolution the pinned Gentle AI fork's own skillsForAdapter
// (internal/cli/config_stager.go) used to compute before staging. See
// internal/skills for the exact resolution rule and the per-adapter
// directories.
func runSkills(args []string) (int, error) {
	fs := flag.NewFlagSet("skills", flag.ExitOnError)
	tree := fs.String("tree", "", "rendered tree to prune declared skill scoping in")
	specPath := fs.String("spec", "", "JSON file describing the skill scoping to apply (see internal/skills.Spec)")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *tree == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix skills: --tree is required")
		return 2, nil
	}
	if *specPath == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix skills: --spec is required")
		return 2, nil
	}

	raw, err := os.ReadFile(*specPath)
	if err != nil {
		return 0, fmt.Errorf("read spec %q: %w", *specPath, err)
	}

	var spec skills.Spec
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&spec); err != nil {
		fmt.Fprintf(os.Stderr, "gentle-nix skills: invalid spec %q: %v\n", *specPath, err)
		return 2, nil
	}

	if err := skills.Prune(*tree, spec); err != nil {
		return 0, err
	}

	return 0, nil
}
