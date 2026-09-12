package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/frontmatter"
)

func runFrontmatter(args []string) (int, error) {
	fs := flag.NewFlagSet("frontmatter", flag.ExitOnError)
	source := fs.String("source", "", "subtree to copy")
	target := fs.String("target", "", "where the filled copy is written")
	var defaultRaw []string
	fs.Var(repeatableFlag{&defaultRaw}, "default", "frontmatter key filled into markdown files that lack it; repeatable")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *source == "" || *target == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix frontmatter: --source and --target are required")
		return 2, nil
	}

	defaults := make(map[string]string, len(defaultRaw))
	for _, raw := range defaultRaw {
		key, value, err := frontmatter.ParseDefaultArgument(raw)
		if err != nil {
			fmt.Fprintf(os.Stderr, "gentle-ai: %v\n", err)
			return 1, nil
		}
		defaults[key] = value
	}

	if err := frontmatter.CopyTree(*source, *target, defaults); err != nil {
		return 0, err
	}
	return 0, nil
}
