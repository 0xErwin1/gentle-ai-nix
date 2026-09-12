package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"

	"github.com/0xErwin1/gentle-ai-nix/internal/retire"
)

// realRemover is retire.Remover backed by the real `pi` binary on PATH.
type realRemover struct{}

func (realRemover) LookPath(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func (realRemover) Remove(entry string) bool {
	cmd := exec.Command("pi", "remove", entry)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run() == nil
}

func (realRemover) Printf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
}

func runRetire(args []string) (int, error) {
	fs := flag.NewFlagSet("retire", flag.ExitOnError)
	settings := fs.String("settings", "", "Pi's settings.json")
	var displacedRaw []string
	fs.Var(repeatableFlag{&displacedRaw}, "displaced", "a JSON identity rule naming entries this generation no longer wants")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	if *settings == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix retire: --settings is required")
		return 2, nil
	}

	rules := make([]retire.Rule, 0, len(displacedRaw))
	for _, raw := range displacedRaw {
		var rule retire.Rule
		if err := json.Unmarshal([]byte(raw), &rule); err != nil {
			return 0, fmt.Errorf("--displaced: invalid JSON rule %q: %w", raw, err)
		}
		rules = append(rules, rule)
	}

	code, err := retire.Run(retire.Options{Settings: *settings, Rules: rules}, realRemover{})
	return code, err
}
