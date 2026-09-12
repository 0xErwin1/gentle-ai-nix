package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/rewrite"
)

func runRewrite(args []string) (int, error) {
	fs := flag.NewFlagSet("rewrite", flag.ExitOnError)
	source := fs.String("source", "", "rendered subtree to copy")
	target := fs.String("target", "", "where the rewritten copy is written")
	var replaceRaw []string
	fs.Var(repeatableFlag{&replaceRaw}, "replace", "reference to rewrite, most specific applied first; repeatable")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *source == "" || *target == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix rewrite: --source and --target are required")
		return 2, nil
	}

	pairs := make([][2]string, 0, len(replaceRaw))
	for _, raw := range replaceRaw {
		from, to, err := rewrite.ParseReplaceArgument(raw)
		if err != nil {
			fmt.Fprintf(os.Stderr, "gentle-ai: %v\n", err)
			return 1, nil
		}
		pairs = append(pairs, [2]string{from, to})
	}

	pattern, table := rewrite.CompileReplacements(pairs)
	if err := rewrite.CopyTree(*source, *target, pattern, table); err != nil {
		return 0, err
	}
	return 0, nil
}
