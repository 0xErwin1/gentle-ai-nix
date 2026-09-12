// Command gentle-nix is the single binary this module ships in place of
// the five Python helpers lib/*.py used to be wrapped as with
// pkgs.writers.writePython3Bin: provision, retire, merge, rewrite, and
// frontmatter.
//
// This phase ports four of the five subcommands -- provision, retire,
// rewrite, frontmatter -- to Go, argument for argument and exit code for
// exit code. "merge" is deliberately absent: it depends on tomlkit's
// comment- and ordering-preserving TOML editing, which has no dependable
// Go equivalent (see internal/merge's absence, and the phase report, for
// why), so lib/merge.py stays wired as gentle-ai-merge until that gap is
// closed.
//
// "settings" is not a port: it is new in this module's next phase, moving
// two things that used to travel through Gentle AI's own desired-state
// document -- providers.pi.packages (via provision's own --override/--extra
// flags) and providers.<name>.settings (via this subcommand) -- into
// gentle-nix itself, so gentle-ai-nix stays a superset of Gentle AI instead
// of asking the document to carry fields only this flake needs.
//
// "pi routing" continues that move: Pi's model routing and gentle-pi's own
// agent profile store are not Gentle AI features either, so this phase moves
// providers.pi.{models,profiles,activeProfile,modelFamily,modelPreset} out of
// the document too, and writes .pi/gentle-ai/{models,profiles}.json and Pi's
// settings defaults directly -- see internal/pirouting.
package main

import (
	"fmt"
	"os"
)

// version is overwritten at build time via -ldflags "-X main.version=...",
// the same convention packages/gentle-ai.nix and packages/engram.nix use.
var version = "dev"

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: gentle-nix <provision|settings|pi|retire|rewrite|frontmatter> [flags]")
		os.Exit(2)
	}

	var (
		code int
		err  error
	)

	switch os.Args[1] {
	case "provision":
		code, err = runProvision(os.Args[2:])
	case "settings":
		code, err = runSettings(os.Args[2:])
	case "pi":
		code, err = runPi(os.Args[2:])
	case "retire":
		code, err = runRetire(os.Args[2:])
	case "rewrite":
		code, err = runRewrite(os.Args[2:])
	case "frontmatter":
		code, err = runFrontmatter(os.Args[2:])
	case "--version":
		fmt.Println(version)
		return
	default:
		fmt.Fprintf(os.Stderr, "gentle-nix: unknown subcommand %q\n", os.Args[1])
		os.Exit(2)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "gentle-nix: %v\n", err)
		os.Exit(1)
	}
	os.Exit(code)
}
