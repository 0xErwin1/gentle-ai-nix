package provision

import (
	"strings"
	"testing"
)

// piFixedSequence is the fixed, unoverridden Pi install sequence exactly as
// InstallCommandWithSources (the fork's pi adapter) renders it with no
// sources at all -- i.e. exactly what a manifest looks like now that the
// document no longer carries providers.pi.packages. RewriteCommands is what
// turns this back into the sequence an override/extra would have produced
// when the document still carried them.
func piFixedSequence() [][]string {
	return [][]string{
		{"pi", "install", "npm:gentle-pi"},
		{"pi", "install", "npm:gentle-engram"},
		{"pi", "install", "npm:pi-mcp-adapter"},
		{"npm", "exec", "--yes", "--package", "gentle-engram@latest", "--", "pi-engram", "init"},
		{"pi", "install", "npm:@juicesharp/rpiv-ask-user-question"},
		{"pi", "install", "npm:pi-web-access"},
		{"pi", "install", "npm:pi-btw"},
	}
}

func joinAll(commands [][]string) []string {
	out := make([]string, len(commands))
	for i, c := range commands {
		out[i] = strings.Join(c, " ")
	}
	return out
}

func TestRewriteCommandsNoOverridesOrExtrasIsANoop(t *testing.T) {
	commands := piFixedSequence()
	rewritten, err := RewriteCommands(commands, nil, nil)
	if err != nil {
		t.Fatalf("RewriteCommands: %v", err)
	}
	if strings.Join(joinAll(rewritten), "\n") != strings.Join(joinAll(commands), "\n") {
		t.Fatalf("unexpected rewrite with no overrides/extras: %v", rewritten)
	}
}

func TestRewriteCommandsOverridesThirdToken(t *testing.T) {
	commands := piFixedSequence()
	overrides := map[string]string{
		"gentle-pi": "git:github.com/Gentleman-Programming/gentle-pi@6e4478c04615b0c013a017178dcfefa51579982d",
	}
	rewritten, err := RewriteCommands(commands, overrides, nil)
	if err != nil {
		t.Fatalf("RewriteCommands: %v", err)
	}
	want := "pi install git:github.com/Gentleman-Programming/gentle-pi@6e4478c04615b0c013a017178dcfefa51579982d"
	if strings.Join(rewritten[0], " ") != want {
		t.Fatalf("gentle-pi command = %q, want %q", strings.Join(rewritten[0], " "), want)
	}
	// Unrelated commands are untouched.
	if strings.Join(rewritten[1], " ") != "pi install npm:gentle-engram" {
		t.Fatalf("unrelated command changed: %v", rewritten[1])
	}
}

func TestRewriteCommandsGentleEngramNpmOverrideRewritesInitCommandToo(t *testing.T) {
	commands := piFixedSequence()
	overrides := map[string]string{"gentle-engram": "npm:gentle-engram@2.0.0"}
	rewritten, err := RewriteCommands(commands, overrides, nil)
	if err != nil {
		t.Fatalf("RewriteCommands: %v", err)
	}
	if strings.Join(rewritten[1], " ") != "pi install npm:gentle-engram@2.0.0" {
		t.Fatalf("install command = %v", rewritten[1])
	}
	wantInit := "npm exec --yes --package gentle-engram@2.0.0 -- pi-engram init"
	if strings.Join(rewritten[3], " ") != wantInit {
		t.Fatalf("init command = %q, want %q", strings.Join(rewritten[3], " "), wantInit)
	}
}

func TestRewriteCommandsGentleEngramLocalPathOverrideUsesLocalBinary(t *testing.T) {
	commands := piFixedSequence()
	overrides := map[string]string{"gentle-engram": "/nix/store/abc-gentle-engram-pi"}
	rewritten, err := RewriteCommands(commands, overrides, nil)
	if err != nil {
		t.Fatalf("RewriteCommands: %v", err)
	}
	if strings.Join(rewritten[1], " ") != "pi install /nix/store/abc-gentle-engram-pi" {
		t.Fatalf("install command = %v", rewritten[1])
	}
	wantInit := "/nix/store/abc-gentle-engram-pi/bin/pi-engram init"
	if strings.Join(rewritten[3], " ") != wantInit {
		t.Fatalf("init command = %q, want %q", strings.Join(rewritten[3], " "), wantInit)
	}
}

func TestRewriteCommandsGentleEngramInvalidOverrideShapeIsAnError(t *testing.T) {
	commands := piFixedSequence()
	overrides := map[string]string{"gentle-engram": "git:github.com/x/gentle-engram@rev"}
	_, err := RewriteCommands(commands, overrides, nil)
	if err == nil {
		t.Fatal("expected an error for an unsupported gentle-engram override shape")
	}
	if !strings.Contains(err.Error(), "npm:<name>") || !strings.Contains(err.Error(), "local path") {
		t.Fatalf("error does not name the two accepted shapes: %v", err)
	}
}

func TestRewriteCommandsPinnedFixedPackageReplacesInPlace(t *testing.T) {
	commands := piFixedSequence()
	overrides := map[string]string{"pi-btw": "npm:pi-btw@1.2.3"}
	rewritten, err := RewriteCommands(commands, overrides, nil)
	if err != nil {
		t.Fatalf("RewriteCommands: %v", err)
	}
	if len(rewritten) != 7 {
		t.Fatalf("pinning a fixed package changed the command count to %d", len(rewritten))
	}
	joined := joinAll(rewritten)
	found := false
	for _, c := range joined {
		if c == "pi install npm:pi-btw@1.2.3" {
			found = true
		}
		if c == "pi install npm:pi-btw" {
			t.Fatalf("the bare fixed command still ran alongside the pinned one: %v", joined)
		}
	}
	if !found {
		t.Fatalf("the pinned source did not replace the fixed command: %v", joined)
	}
}

func TestRewriteCommandsExtraAppendsAfterFixedSequenceSorted(t *testing.T) {
	commands := piFixedSequence()
	rewritten, err := RewriteCommands(commands, nil, []string{
		"git:github.com/x/y@rev",
		"npm:another-extra",
	})
	if err != nil {
		t.Fatalf("RewriteCommands: %v", err)
	}
	if len(rewritten) != 9 {
		t.Fatalf("expected the fixed 7-command sequence plus 2 extras, got %d: %v", len(rewritten), joinAll(rewritten))
	}
	tail := joinAll(rewritten)[7:]
	want := []string{"pi install git:github.com/x/y@rev", "pi install npm:another-extra"}
	if strings.Join(tail, "\n") != strings.Join(want, "\n") {
		t.Fatalf("extras did not append in sorted order: %v", tail)
	}
}

func TestRewriteCommandsExtraDedupedAgainstFixedList(t *testing.T) {
	commands := piFixedSequence()
	rewritten, err := RewriteCommands(commands, nil, []string{"npm:pi-btw"})
	if err != nil {
		t.Fatalf("RewriteCommands: %v", err)
	}
	if len(rewritten) != 7 {
		t.Fatalf("an extra matching an already-declared source was not deduplicated: %v", joinAll(rewritten))
	}
}

func TestRewriteCommandsExtrasAreDedupedAmongThemselves(t *testing.T) {
	commands := piFixedSequence()
	rewritten, err := RewriteCommands(commands, nil, []string{"git:github.com/x/y@rev", "git:github.com/x/y@rev"})
	if err != nil {
		t.Fatalf("RewriteCommands: %v", err)
	}
	if len(rewritten) != 8 {
		t.Fatalf("a duplicated extra was appended twice: %v", joinAll(rewritten))
	}
}

func TestParseOverrideArgument(t *testing.T) {
	name, source, err := ParseOverrideArgument("gentle-pi=git:github.com/x/y@rev")
	if err != nil {
		t.Fatalf("ParseOverrideArgument: %v", err)
	}
	if name != "gentle-pi" || source != "git:github.com/x/y@rev" {
		t.Fatalf("name=%q source=%q", name, source)
	}

	if _, _, err := ParseOverrideArgument("no-equals-sign"); err == nil {
		t.Fatal("expected an error for an argument with no '='")
	}
}
