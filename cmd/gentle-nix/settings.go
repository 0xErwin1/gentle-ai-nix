package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/0xErwin1/gentle-ai-nix/internal/settings"
)

func runSettings(args []string) (int, error) {
	fs := flag.NewFlagSet("settings", flag.ExitOnError)
	tree := fs.String("tree", "", "rendered tree to merge provider settings blocks into")
	var providerRaw []string
	fs.Var(repeatableFlag{&providerRaw}, "provider", "name=path: a provider id and the JSON file holding its declared settings block; repeatable")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *tree == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix settings: --tree is required")
		return 2, nil
	}

	providers := make([]settings.ProviderBlock, 0, len(providerRaw))
	for _, raw := range providerRaw {
		name, path, err := parseProviderArgument(raw)
		if err != nil {
			fmt.Fprintf(os.Stderr, "gentle-nix settings: %v\n", err)
			return 2, nil
		}
		providers = append(providers, settings.ProviderBlock{Name: name, BlockPath: path})
	}

	code, err := settings.Run(settings.Options{Tree: *tree, Providers: providers})
	if err != nil && code == 2 {
		// An unknown provider is a configuration mistake, not an
		// unexpected failure: report it here, with its own exit code,
		// rather than through main's generic "gentle-nix: %v" / exit 1
		// path.
		fmt.Fprintf(os.Stderr, "gentle-nix settings: %v\n", err)
		return 2, nil
	}
	return code, err
}

// parseProviderArgument splits a "--provider name=path" argument the same
// way ParseOverrideArgument splits "--override name=source" for
// gentle-nix provision.
func parseProviderArgument(raw string) (name, path string, err error) {
	for i := 0; i < len(raw); i++ {
		if raw[i] == '=' {
			return raw[:i], raw[i+1:], nil
		}
	}
	return "", "", fmt.Errorf("--provider: expected name=path, got %q", raw)
}
