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
//
// "roles" moves one more thing out of the document: renaming or defining
// roles is not something Gentle AI does imperatively, so
// programs.gentle-ai.roles no longer travels through the document as
// "roles" either. This subcommand post-processes the tree "gentle-ai config
// render" already produced instead, reproducing exactly what the pinned
// fork's own role renderer wrote for the five adapters that can express a
// role at all -- see internal/roles.
//
// "mcp" moves declared MCP servers out the same way: a user-declared server
// is not something Gentle AI configures imperatively either (it only wires
// its own fixed servers), so programs.gentle-ai.mcpServers and
// providers.<name>.mcpServers no longer travel through the document as
// "mcpServers" at all. This subcommand writes them straight into the
// rendered tree instead, reproducing exactly what the pinned fork's own MCP
// injector wrote for every adapter that can express one -- see
// internal/mcp. Codex is the one exception: its MCP config lives in
// config.toml, so the Nix module routes it through the existing TOML
// merger instead of this subcommand.
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
		fmt.Fprintln(os.Stderr, "usage: gentle-nix <provision|settings|pi|roles|mcp|retire|rewrite|frontmatter> [flags]")
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
	case "roles":
		code, err = runRoles(os.Args[2:])
	case "mcp":
		code, err = runMCP(os.Args[2:])
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
