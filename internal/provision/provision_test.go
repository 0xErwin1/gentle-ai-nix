package provision

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const manifestFixture = `{"manifest":{"resources":[
  {"path":".pi/agent/settings.json","selector":"file","digest":"abc"},
  {"path":"engram","selector":"provision","digest":"present","component":"engram"},
  {"path":"pi","selector":"provision","digest":"present","agent":"pi",
   "commands":[["fake-pi","install","npm:gentle-pi"],["fake-pi","install","npm:gentle-engram"]]}
]}}`

func writeManifest(t *testing.T, dir, content string) string {
	t.Helper()
	path := filepath.Join(dir, "manifest.json")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestDeclaredCommands(t *testing.T) {
	dir := t.TempDir()
	manifest := writeManifest(t, dir, manifestFixture)

	tests := []struct {
		name  string
		field string
		value string
		want  int
	}{
		{"agent pi has two commands", "agent", "pi", 2},
		{"component engram is not an agent", "agent", "engram", 0},
		{"unknown agent has no commands", "agent", "nope", 0},
		{"tool field never matches an agent resource", "tool", "pi", 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			commands, err := DeclaredCommands(manifest, tt.field, tt.value)
			if err != nil {
				t.Fatalf("DeclaredCommands: %v", err)
			}
			if len(commands) != tt.want {
				t.Fatalf("len(commands) = %d, want %d", len(commands), tt.want)
			}
		})
	}
}

func TestDeclaredCommandsToolResource(t *testing.T) {
	dir := t.TempDir()
	manifest := writeManifest(t, dir, `{"manifest":{"resources":[
		{"path":"codegraph","selector":"provision","digest":"present","tool":"codegraph",
		 "commands":[["fake-pi","install","--target","claude"]]}
	]}}`)

	commands, err := DeclaredCommands(manifest, "tool", "codegraph")
	if err != nil {
		t.Fatal(err)
	}
	if len(commands) != 1 || strings.Join(commands[0], " ") != "fake-pi install --target claude" {
		t.Fatalf("unexpected commands: %v", commands)
	}

	// A tool's own commands must never surface under the agent field, and an
	// agent's commands must never surface under the tool field: provision.py
	// checks the exact field the resource was declared under (line 48:
	// `if resource.get(field) != value`), never assumes agent and tool share
	// a namespace.
	asAgent, err := DeclaredCommands(manifest, "agent", "codegraph")
	if err != nil {
		t.Fatal(err)
	}
	if len(asAgent) != 0 {
		t.Fatalf("a tool resource leaked into the agent field: %v", asAgent)
	}
}

func TestReadWriteStamp(t *testing.T) {
	dir := t.TempDir()
	stampPath := filepath.Join(dir, "nested", "pi.provisioned")

	if got := ReadStamp(stampPath); got != "" {
		t.Fatalf("ReadStamp on a missing file = %q, want empty", got)
	}

	if err := WriteStamp(stampPath, "deadbeef"); err != nil {
		t.Fatalf("WriteStamp: %v", err)
	}

	if got := ReadStamp(stampPath); got != "deadbeef" {
		t.Fatalf("ReadStamp after write = %q, want deadbeef", got)
	}

	raw, err := os.ReadFile(stampPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != "deadbeef\n" {
		t.Fatalf("stamp file contents = %q, want a trailing newline", raw)
	}
}

func TestDigestOfIsStableAndOrderSensitive(t *testing.T) {
	a := DigestOf([][]string{{"pi", "install", "x"}})
	b := DigestOf([][]string{{"pi", "install", "x"}})
	if a != b {
		t.Fatalf("DigestOf is not deterministic: %s != %s", a, b)
	}

	c := DigestOf([][]string{{"pi", "install", "y"}})
	if a == c {
		t.Fatalf("DigestOf did not change for a different command")
	}
}

// fakeRunner records every command it was asked to run and looks up its
// canned exit code by the joined command line, defaulting to success. It
// stands in for subprocess.run(command, check=False) without touching a
// real process, per the go-testing skill's guidance to keep process
// execution behind a small interface.
type fakeRunner struct {
	which   map[string]bool
	exit    map[string]int
	ran     [][]string
	printed []string
}

func (f *fakeRunner) LookPath(name string) bool {
	return f.which[name]
}

func (f *fakeRunner) Run(command []string) int {
	f.ran = append(f.ran, command)
	if code, ok := f.exit[strings.Join(command, " ")]; ok {
		return code
	}
	return 0
}

func (f *fakeRunner) Printf(format string, args ...any) {
	f.printed = append(f.printed, fmt.Sprintf(format, args...))
}

func TestRunSkipsWhenClientNotOnPath(t *testing.T) {
	dir := t.TempDir()
	manifest := writeManifest(t, dir, manifestFixture)
	stampDir := filepath.Join(dir, "stamps")

	runner := &fakeRunner{which: map[string]bool{}}
	code, err := Run(Options{
		Manifest: manifest,
		Field:    "agent",
		Name:     "pi",
		StampDir: stampDir,
	}, runner)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if code != 0 {
		t.Fatalf("code = %d, want 0", code)
	}
	if len(runner.ran) != 0 {
		t.Fatalf("commands ran without the client installed: %v", runner.ran)
	}
	if _, statErr := os.Stat(filepath.Join(stampDir, "agent-pi.provisioned")); statErr == nil {
		t.Fatalf("a skipped run recorded a stamp")
	}
}

func TestRunExecutesEachDeclaredCommandOnce(t *testing.T) {
	dir := t.TempDir()
	manifest := writeManifest(t, dir, manifestFixture)
	stampDir := filepath.Join(dir, "stamps")

	runner := &fakeRunner{which: map[string]bool{"fake-pi": true}}
	code, err := Run(Options{Manifest: manifest, Field: "agent", Name: "pi", StampDir: stampDir}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 {
		t.Fatalf("code = %d, want 0", code)
	}
	if len(runner.ran) != 2 {
		t.Fatalf("ran %d commands, want 2: %v", len(runner.ran), runner.ran)
	}

	// A second run against the same manifest must not repeat the commands:
	// the stamp already records their digest.
	runner.ran = nil
	code, err = Run(Options{Manifest: manifest, Field: "agent", Name: "pi", StampDir: stampDir}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 || len(runner.ran) != 0 {
		t.Fatalf("an unchanged command list ran again: code=%d ran=%v", code, runner.ran)
	}

	// --force re-runs even though the stamp still matches.
	code, err = Run(Options{Manifest: manifest, Field: "agent", Name: "pi", StampDir: stampDir, Force: true}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 || len(runner.ran) != 2 {
		t.Fatalf("--force did not re-run the declared commands: code=%d ran=%v", code, runner.ran)
	}
}

func TestRunStopsAtTheFirstFailingCommandAndPropagatesItsExitCode(t *testing.T) {
	dir := t.TempDir()
	manifest := writeManifest(t, dir, manifestFixture)
	stampDir := filepath.Join(dir, "stamps")

	runner := &fakeRunner{
		which: map[string]bool{"fake-pi": true},
		exit:  map[string]int{"fake-pi install npm:gentle-pi": 3},
	}
	code, err := Run(Options{Manifest: manifest, Field: "agent", Name: "pi", StampDir: stampDir}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 3 {
		t.Fatalf("code = %d, want 3 (the failing command's own exit code)", code)
	}
	if len(runner.ran) != 1 {
		t.Fatalf("ran %d commands, want exactly the one that failed: %v", len(runner.ran), runner.ran)
	}
	if _, statErr := os.Stat(filepath.Join(stampDir, "agent-pi.provisioned")); statErr == nil {
		t.Fatalf("a failed run recorded a stamp")
	}
}

func TestRunWithNoDeclaredCommandsIsANoop(t *testing.T) {
	dir := t.TempDir()
	manifest := writeManifest(t, dir, manifestFixture)
	stampDir := filepath.Join(dir, "stamps")

	runner := &fakeRunner{which: map[string]bool{"fake-pi": true}}
	code, err := Run(Options{Manifest: manifest, Field: "agent", Name: "engram", StampDir: stampDir}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 || len(runner.ran) != 0 {
		t.Fatalf("a component with no declared agent commands ran something: code=%d ran=%v", code, runner.ran)
	}
}

func TestRunAppliesOverridesBeforeExecutingAndStamping(t *testing.T) {
	dir := t.TempDir()
	manifest := writeManifest(t, dir, manifestFixture)
	stampDir := filepath.Join(dir, "stamps")

	runner := &fakeRunner{which: map[string]bool{"fake-pi": true}}
	code, err := Run(Options{
		Manifest:  manifest,
		Field:     "agent",
		Name:      "pi",
		StampDir:  stampDir,
		Overrides: map[string]string{"gentle-pi": "git:github.com/x/y@rev"},
	}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 {
		t.Fatalf("code = %d, want 0", code)
	}
	if len(runner.ran) != 2 || strings.Join(runner.ran[0], " ") != "fake-pi install git:github.com/x/y@rev" {
		t.Fatalf("the override was not applied before executing: %v", runner.ran)
	}

	// A second run with the SAME override still matches the stamp: the
	// digest was computed over the rewritten list, so nothing reruns.
	runner.ran = nil
	code, err = Run(Options{
		Manifest:  manifest,
		Field:     "agent",
		Name:      "pi",
		StampDir:  stampDir,
		Overrides: map[string]string{"gentle-pi": "git:github.com/x/y@rev"},
	}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 || len(runner.ran) != 0 {
		t.Fatalf("an unchanged overridden command list ran again: code=%d ran=%v", code, runner.ran)
	}

	// Dropping the override changes the digest, so it runs again with the
	// plain declared command.
	runner.ran = nil
	code, err = Run(Options{Manifest: manifest, Field: "agent", Name: "pi", StampDir: stampDir}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 || len(runner.ran) != 2 || strings.Join(runner.ran[0], " ") != "fake-pi install npm:gentle-pi" {
		t.Fatalf("changing the override did not invalidate the stamp: code=%d ran=%v", code, runner.ran)
	}
}

func TestRunRejectsAnUnsupportedGentleEngramOverride(t *testing.T) {
	dir := t.TempDir()
	manifest := writeManifest(t, dir, manifestFixture)
	stampDir := filepath.Join(dir, "stamps")

	runner := &fakeRunner{which: map[string]bool{"fake-pi": true}}
	code, err := Run(Options{
		Manifest:  manifest,
		Field:     "agent",
		Name:      "pi",
		StampDir:  stampDir,
		Overrides: map[string]string{"gentle-engram": "git:github.com/x/gentle-engram@rev"},
	}, runner)
	if err != nil {
		t.Fatal(err)
	}
	if code != 2 {
		t.Fatalf("code = %d, want 2", code)
	}
	if len(runner.ran) != 0 {
		t.Fatalf("commands ran despite the rejected override: %v", runner.ran)
	}
}
