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
		fmt.Fprintln(os.Stderr, "usage: gentle-nix <provision|retire|rewrite|frontmatter> [flags]")
		os.Exit(2)
	}

	var (
		code int
		err  error
	)

	switch os.Args[1] {
	case "provision":
		code, err = runProvision(os.Args[2:])
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
