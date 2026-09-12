package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/0xErwin1/gentle-ai-nix/internal/provision"
)

// realRunner is provision.Runner backed by the real OS: PATH lookups
// through exec.LookPath and commands run with their stdio inherited from
// this process, matching subprocess.run(command, check=False)'s default
// of not capturing output.
type realRunner struct{}

func (realRunner) LookPath(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func (realRunner) Run(command []string) int {
	cmd := exec.Command(command[0], command[1:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return exitErr.ExitCode()
		}
		// The command could not even start (not found, not executable,
		// ...): report it the same way a nonzero exit would, since the
		// caller only branches on "zero or not".
		fmt.Fprintf(os.Stderr, "gentle-ai: %v\n", err)
		return 1
	}
	return 0
}

func (realRunner) Printf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
}

func runProvision(args []string) (int, error) {
	fs := flag.NewFlagSet("provision", flag.ExitOnError)
	manifest := fs.String("manifest", "", "rendered manifest.json to read declared commands from")
	agent := fs.String("agent", "", "client whose own tool installs its harness")
	tool := fs.String("tool", "", "community tool that wires itself into the clients")
	stampDir := fs.String("stamp-dir", "", "directory holding the content-addressed stamp files")
	force := fs.Bool("force", false, "run the commands even when the stamp already records them")
	var overrideRaw []string
	fs.Var(repeatableFlag{&overrideRaw}, "override", "name=source: rewrite one declared package's install source in place; repeatable")
	var extra []string
	fs.Var(repeatableFlag{&extra}, "extra", "an additional package source to install after the declared sequence; repeatable")
	print := fs.Bool("print", false, "write the final, rewritten command list to stdout, one per line, and exit without running or stamping anything")
	if err := fs.Parse(args); err != nil {
		return 2, nil
	}

	agentSet := flagWasSet(fs, "agent")
	toolSet := flagWasSet(fs, "tool")
	if agentSet == toolSet {
		fmt.Fprintln(os.Stderr, "gentle-nix provision: exactly one of --agent or --tool is required")
		return 2, nil
	}
	if *manifest == "" || *stampDir == "" {
		fmt.Fprintln(os.Stderr, "gentle-nix provision: --manifest and --stamp-dir are required")
		return 2, nil
	}

	field, name := "tool", *tool
	if agentSet {
		field, name = "agent", *agent
	}

	overrides := make(map[string]string, len(overrideRaw))
	for _, raw := range overrideRaw {
		overrideName, source, err := provision.ParseOverrideArgument(raw)
		if err != nil {
			fmt.Fprintf(os.Stderr, "gentle-nix provision: %v\n", err)
			return 2, nil
		}
		overrides[overrideName] = source
	}

	if *print {
		commands, err := provision.DeclaredCommands(*manifest, field, name)
		if err != nil {
			return 0, err
		}
		rewritten, err := provision.RewriteCommands(commands, overrides, extra)
		if err != nil {
			fmt.Fprintf(os.Stderr, "gentle-nix provision: %v\n", err)
			return 2, nil
		}
		for _, command := range rewritten {
			fmt.Println(strings.Join(command, " "))
		}
		return 0, nil
	}

	code, err := provision.Run(provision.Options{
		Manifest:  *manifest,
		Field:     field,
		Name:      name,
		StampDir:  *stampDir,
		Force:     *force,
		Overrides: overrides,
		Extra:     extra,
	}, realRunner{})
	return code, err
}

// flagWasSet reports whether name was actually given on the command line,
// the presence check argparse's own required=True group performs --
// distinct from the flag merely holding its zero value.
func flagWasSet(fs *flag.FlagSet, name string) bool {
	found := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == name {
			found = true
		}
	})
	return found
}
