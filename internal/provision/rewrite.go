package provision

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"
)

// defaultGentleEngramInit is the exact command a declared manifest carries
// for Pi's gentle-engram init step when nothing overrides gentle-engram's
// source -- the one command in Pi's fixed install sequence that is not
// itself an "<tool> install <source>" line, so it needs its own pattern to
// find and its own rewrite rule, mirroring engramInitCommand in the pinned
// fork's Pi adapter (internal/agents/pi/adapter.go).
var defaultGentleEngramInit = []string{"npm", "exec", "--yes", "--package", "gentle-engram@latest", "--", "pi-engram", "init"}

// ParseOverrideArgument splits a "--override name=source" argument into its
// name and source, the way gentle-nix provision's flag parsing does before
// handing the accumulated map to RewriteCommands. The source is validated
// against ValidSource here, at the earliest point gentle-nix sees it, so a
// mistyped source (a bare package name missing its "npm:" prefix, for
// instance) is refused before it can reach a rewritten command Pi's
// installer would only fail on later.
func ParseOverrideArgument(raw string) (name, source string, err error) {
	i := strings.Index(raw, "=")
	if i < 0 {
		return "", "", fmt.Errorf("--override: expected name=source, got %q", raw)
	}
	name, source = raw[:i], raw[i+1:]
	if !ValidSource(source) {
		return "", "", InvalidSourceError(source)
	}
	return name, source, nil
}

// RewriteCommands rewrites a declared command list the same way the pinned
// Gentle AI fork's Pi adapter (InstallCommandWithSources) used to rewrite
// its own fixed sequence when the document still carried
// providers.pi.packages: an "<tool> install npm:<name>" command for a name
// present in overrides has its source replaced in place, the one command
// that is not an install line -- gentle-engram's npm-exec init step -- is
// rewritten to match a gentle-engram override, and every entry in extra is
// appended afterwards as its own "<tool> install <source>" command.
//
// commands is never mutated; RewriteCommands returns a new slice so a
// caller (gentle-nix provision) can still hash and log the original
// declared list if it ever needs to.
func RewriteCommands(commands [][]string, overrides map[string]string, extra []string) ([][]string, error) {
	if len(overrides) == 0 && len(extra) == 0 {
		return commands, nil
	}

	// gentle-engram's source shape is validated up front, exactly like the
	// fork's InstallCommandWithSources: a document (or, here, a manifest)
	// that names an unsupported gentle-engram source is rejected even if
	// this particular command list never carries the init step.
	if source, overridden := overrides["gentle-engram"]; overridden {
		if _, err := gentleEngramInitCommand(source); err != nil {
			return nil, err
		}
	}

	tool := ""
	if len(commands) > 0 && len(commands[0]) > 0 {
		tool = commands[0][0]
	}

	rewritten := make([][]string, len(commands))
	declaredSources := make(map[string]struct{}, len(commands))

	for i, command := range commands {
		switch {
		case isNpmInstall(command):
			name := strings.TrimPrefix(command[2], "npm:")
			source := command[2]
			if overridden, ok := overrides[name]; ok {
				source = overridden
			}
			rewritten[i] = []string{command[0], command[1], source}
			declaredSources[source] = struct{}{}
		case commandEquals(command, defaultGentleEngramInit):
			init, err := gentleEngramInitCommand(overrides["gentle-engram"])
			if err != nil {
				return nil, err
			}
			rewritten[i] = init
		default:
			rewritten[i] = command
			if len(command) == 3 && command[1] == "install" {
				declaredSources[command[2]] = struct{}{}
			}
		}
	}

	sortedExtra := append([]string(nil), extra...)
	sort.Strings(sortedExtra)

	seen := make(map[string]struct{}, len(sortedExtra))
	for _, source := range sortedExtra {
		if _, already := declaredSources[source]; already {
			continue
		}
		if _, dup := seen[source]; dup {
			continue
		}
		seen[source] = struct{}{}
		rewritten = append(rewritten, []string{tool, "install", source})
	}

	return rewritten, nil
}

// isNpmInstall reports whether command is exactly "<tool> install
// npm:<name>", the shape every fixed Pi package renders as until an
// override replaces its third token.
func isNpmInstall(command []string) bool {
	return len(command) == 3 && command[1] == "install" && strings.HasPrefix(command[2], "npm:")
}

func commandEquals(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// gentleEngramInitCommand is engramInitCommand from the pinned fork's Pi
// adapter, ported so a rewritten manifest reaches an identical command
// whether the override was applied by the fork (document-based) or here
// (gentle-nix-based): an npm: source becomes the --package spec with its
// prefix stripped, an absolute local path runs that plugin's own
// bin/pi-engram directly (npm exec cannot work against a read-only Nix
// store path), no override keeps the npm default, and any other shape is
// rejected before it can produce a broken command.
func gentleEngramInitCommand(source string) ([]string, error) {
	switch {
	case source == "":
		return append([]string(nil), defaultGentleEngramInit...), nil
	case strings.HasPrefix(source, "npm:"):
		spec := strings.TrimPrefix(source, "npm:")
		if spec == "" {
			return nil, gentleEngramSourceError(source)
		}
		return []string{"npm", "exec", "--yes", "--package", spec, "--", "pi-engram", "init"}, nil
	case strings.HasPrefix(source, "/"):
		if source == "/" {
			return nil, gentleEngramSourceError(source)
		}
		return []string{filepath.Join(source, "bin", "pi-engram"), "init"}, nil
	default:
		return nil, gentleEngramSourceError(source)
	}
}

func gentleEngramSourceError(source string) error {
	return fmt.Errorf(
		"pi: unsupported gentle-engram source %q; gentle-engram takes an npm:<name>[@version] spec or an absolute local path because its init step runs through npm exec",
		source,
	)
}
