// Package provision runs the package-installation commands a rendered
// Gentle AI manifest declares for one agent or community tool, gated by a
// content-addressed stamp so an unchanged command list is never repeated.
//
// This is a line-for-line port of lib/provision.py's behavior: the same
// stamp-file layout, the same "client not on PATH" degrade-to-success
// path, and the same "stop at the first failing command and propagate its
// exit code" contract, so an existing installation's stamps and activation
// scripts keep working unchanged once gentle-nix replaces the Python
// helper.
package provision

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/0xErwin1/gentle-ai-nix/internal/jsonutil"
)

// Runner is the process-execution boundary provision.Run depends on,
// narrow enough that tests can fake it without spawning a real process.
type Runner interface {
	// LookPath reports whether name resolves on PATH, the same question
	// shutil.which(tool) answers in the Python original.
	LookPath(name string) bool
	// Run executes command (argv[0] plus its arguments), connecting the
	// child's stdio to this process's own -- matching subprocess.run's
	// default of inheriting stdin/stdout/stderr -- and returns its exit
	// code.
	Run(command []string) int
	// Printf writes one line to stderr, mirroring every
	// print(..., file=sys.stderr) call in provision.py.
	Printf(format string, args ...any)
}

// Options mirrors provision.py's argparse contract. Field is "agent" or
// "tool" and Name is the value that field must carry on a manifest
// resource; Run's caller is responsible for having enforced that exactly
// one of --agent/--tool was given, the way argparse's mutually exclusive
// group does.
type Options struct {
	Manifest string
	Field    string // "agent" or "tool"
	Name     string
	StampDir string
	Force    bool
}

type manifestDocument struct {
	Manifest struct {
		Resources []json.RawMessage `json:"resources"`
	} `json:"manifest"`
}

type resource struct {
	Selector string     `json:"selector"`
	Agent    *string    `json:"agent"`
	Tool     *string    `json:"tool"`
	Commands [][]string `json:"commands"`
}

// DeclaredCommands is the Go equivalent of declared_commands in
// provision.py: every "commands" array from a "provision" resource whose
// field (agent or tool) equals value, concatenated in manifest order.
func DeclaredCommands(manifestPath, field, value string) ([][]string, error) {
	raw, err := os.ReadFile(manifestPath)
	if err != nil {
		return nil, err
	}

	var doc manifestDocument
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, err
	}

	var commands [][]string
	for _, rawResource := range doc.Manifest.Resources {
		var res resource
		if err := json.Unmarshal(rawResource, &res); err != nil {
			return nil, err
		}
		if res.Selector != "provision" {
			continue
		}

		var actual *string
		switch field {
		case "agent":
			actual = res.Agent
		case "tool":
			actual = res.Tool
		}
		if actual == nil || *actual != value {
			continue
		}

		commands = append(commands, res.Commands...)
	}

	return commands, nil
}

// DigestOf is digest_of from provision.py: a sha256 hex digest of the
// command list, encoded the way Python's json.dumps(commands,
// sort_keys=True) encodes it -- see internal/jsonutil for why that has to
// be reproduced byte for byte rather than left to encoding/json.
func DigestOf(commands [][]string) string {
	return jsonutil.SHA256Hex(jsonutil.EncodeCommands(commands))
}

// ReadStamp is read_stamp: the trimmed contents of path, or "" when the
// file does not exist. Any other read error is also treated as "no
// stamp", matching the Python original's narrow except clause only for
// FileNotFoundError in spirit -- provisioning must never fail a switch
// over a stamp file it cannot read.
func ReadStamp(path string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(raw))
}

// WriteStamp is write_stamp: write digest through a temporary file in the
// same directory and rename it into place, so a run interrupted mid-write
// can never leave a truncated, falsely-matching stamp behind.
func WriteStamp(path, digest string) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o777); err != nil {
		return err
	}

	temp, err := os.CreateTemp(dir, "")
	if err != nil {
		return err
	}
	tempName := temp.Name()

	if _, err := temp.WriteString(digest + "\n"); err != nil {
		temp.Close()
		os.Remove(tempName)
		return err
	}
	if err := temp.Close(); err != nil {
		os.Remove(tempName)
		return err
	}

	return os.Rename(tempName, path)
}

// Run is main() from provision.py, minus argument parsing: it always
// returns a nil error for the paths the Python original also always
// succeeds on (an I/O or JSON error reading the manifest is the one case
// that maps to a real Go error, where Python would have let the exception
// propagate and exit nonzero with a traceback -- gentle-nix's cmd layer
// turns that into the same nonzero exit, just without the traceback).
func Run(opts Options, runner Runner) (int, error) {
	commands, err := DeclaredCommands(opts.Manifest, opts.Field, opts.Name)
	if err != nil {
		return 0, err
	}
	if len(commands) == 0 {
		return 0, nil
	}

	stampPath := filepath.Join(opts.StampDir, fmt.Sprintf("%s-%s.provisioned", opts.Field, opts.Name))
	digest := DigestOf(commands)
	if !opts.Force && ReadStamp(stampPath) == digest {
		return 0, nil
	}

	// The client's own binary is a precondition, not something this
	// installs. Failing activation over a client the user has not
	// installed yet would block every unrelated change in the same
	// switch.
	tool := commands[0][0]
	if !runner.LookPath(tool) {
		runner.Printf("gentle-ai: %s not provisioned: %s is not on PATH", opts.Name, tool)
		return 0, nil
	}

	for _, command := range commands {
		runner.Printf("gentle-ai: %s", strings.Join(command, " "))
		code := runner.Run(command)
		if code != 0 {
			runner.Printf("gentle-ai: %s provisioning failed: %s", opts.Name, strings.Join(command, " "))
			return code, nil
		}
	}

	if err := WriteStamp(stampPath, digest); err != nil {
		return 0, err
	}

	return 0, nil
}
