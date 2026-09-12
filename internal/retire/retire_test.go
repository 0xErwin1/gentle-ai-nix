package retire

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"testing"
)

func writeSettings(t *testing.T, dir string, packages []string) string {
	t.Helper()
	path := filepath.Join(dir, ".pi", "agent", "settings.json")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	doc := map[string][]string{"packages": packages}
	raw, err := json.Marshal(doc)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// fakeRemover records every "pi remove <entry>" it was asked to run and
// fails the entries named in failing, the same way checks/default.nix's
// fake `pi` binary does.
type fakeRemover struct {
	present bool
	failing map[string]bool
	removed []string
}

func (f *fakeRemover) LookPath(name string) bool { return f.present }

func (f *fakeRemover) Remove(entry string) bool {
	if f.failing[entry] {
		return false
	}
	f.removed = append(f.removed, entry)
	return true
}

func (f *fakeRemover) Printf(format string, args ...any) {}

func sortedCopy(entries []string) []string {
	out := append([]string(nil), entries...)
	sort.Strings(out)
	return out
}

func assertEntries(t *testing.T, got, want []string) {
	t.Helper()
	gotSorted, wantSorted := sortedCopy(got), sortedCopy(want)
	if len(gotSorted) != len(wantSorted) {
		t.Fatalf("removed %v, want %v", gotSorted, wantSorted)
	}
	for i := range gotSorted {
		if gotSorted[i] != wantSorted[i] {
			t.Fatalf("removed %v, want %v", gotSorted, wantSorted)
		}
	}
}

// TestMainChannelScenario mirrors the "main" scenario in
// checks/default.nix's retireDisplacedPiPackagesRemovesExactlyTheDisplacedEntries:
// off stable, gentle-pi installs from git so every npm gentle-pi entry is
// displaced, and gentle-engram installs from npm so every local entry is
// displaced except the plugin path this generation still wants.
func TestMainChannelScenario(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{
		"npm:gentle-pi",
		"npm:gentle-pi@2.4.0",
		"git:github.com/Gentleman-Programming/gentle-pi@abc123",
		"npm:gentle-engram",
		"npm:gentle-engram@0.1.12",
		"../../../../nix/store/xyz-gentle-engram-pi-2.0.0-rc.9",
		"../gentle-ai/plugins/gentle-engram",
		"npm:pi-mcp-adapter",
	})

	currentPlugin := filepath.Join(dir, ".pi", "gentle-ai", "plugins", "gentle-engram")
	rules := []Rule{
		{Type: "npm", Name: "gentle-pi"},
		{Type: "npm", Name: "gentle-engram"},
		{Type: "package", Keep: "git:github.com/Gentleman-Programming/gentle-pi@def456"},
		{
			Type:     "local",
			Patterns: []string{"-gentle-engram-pi-[^/]*$", "/gentle-engram$"},
			Except:   ptr(currentPlugin),
		},
	}

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{Settings: settings, Rules: rules}, remover); err != nil {
		t.Fatal(err)
	}

	assertEntries(t, remover.removed, []string{
		"npm:gentle-pi",
		"npm:gentle-pi@2.4.0",
		"git:github.com/Gentleman-Programming/gentle-pi@abc123",
		"npm:gentle-engram",
		"npm:gentle-engram@0.1.12",
		"../../../../nix/store/xyz-gentle-engram-pi-2.0.0-rc.9",
	})
}

// TestStableChannelScenario mirrors the "stable" scenario: gentle-pi
// installs from npm so every git gentle-pi entry is displaced, and
// gentle-engram installs from npm too so every local entry is displaced,
// the current plugin path included -- stable has no local plugin left to
// except.
func TestStableChannelScenario(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{
		"npm:gentle-pi",
		"npm:gentle-pi@2.4.0",
		"git:github.com/Gentleman-Programming/gentle-pi@abc123",
		"npm:gentle-engram",
		"npm:gentle-engram@0.1.12",
		"../../../../nix/store/xyz-gentle-engram-pi-2.0.0-rc.9",
		"../gentle-ai/plugins/gentle-engram",
		"npm:pi-mcp-adapter",
	})

	rules := []Rule{
		{Type: "git", Name: "gentle-pi"},
		{Type: "local", Patterns: []string{"-gentle-engram-pi-[^/]*$", "/gentle-engram$"}},
	}

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{Settings: settings, Rules: rules}, remover); err != nil {
		t.Fatal(err)
	}

	assertEntries(t, remover.removed, []string{
		"git:github.com/Gentleman-Programming/gentle-pi@abc123",
		"../../../../nix/store/xyz-gentle-engram-pi-2.0.0-rc.9",
		"../gentle-ai/plugins/gentle-engram",
	})
}

func TestConvergedSettingsRemoveNothing(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{
		"git:github.com/Gentleman-Programming/gentle-pi@abc123",
		"../gentle-ai/plugins/gentle-engram",
		"npm:pi-mcp-adapter",
	})

	rules := []Rule{
		{Type: "npm", Name: "gentle-pi"},
		{Type: "npm", Name: "gentle-engram"},
		{Type: "package", Keep: "git:github.com/Gentleman-Programming/gentle-pi@abc123"},
	}

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{Settings: settings, Rules: rules}, remover); err != nil {
		t.Fatal(err)
	}
	if len(remover.removed) != 0 {
		t.Fatalf("a converged settings file was touched: %v", remover.removed)
	}
}

// TestPackageRuleMatchesBySourceIdentityNotAttributeKey exercises
// matches_package: the source's own repository name is what a "package"
// rule matches, never the attribute key a Nix document declared it under
// -- this test only sees the settings.json shape, so the key never
// appears at all.
func TestPackageRuleMatchesBySourceIdentityNotAttributeKey(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{
		"git:github.com/x/y@rev1",
		"git:github.com/x/y@rev2",
		"npm:unrelated",
	})

	rules := []Rule{{Type: "package", Keep: "git:github.com/x/y@rev2"}}

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{Settings: settings, Rules: rules}, remover); err != nil {
		t.Fatal(err)
	}
	assertEntries(t, remover.removed, []string{"git:github.com/x/y@rev1"})
}

func TestPinnedFixedPackageKeepsThePinnedSpelling(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:pi-btw", "npm:pi-btw@1.2.3"})

	rules := []Rule{{Type: "package", Keep: "npm:pi-btw@1.2.3"}}

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{Settings: settings, Rules: rules}, remover); err != nil {
		t.Fatal(err)
	}
	assertEntries(t, remover.removed, []string{"npm:pi-btw"})
}

func TestUnparsableSettingsDegradeToNoPackagesRatherThanFailing(t *testing.T) {
	for _, shape := range []string{"{ invalid json", "[]"} {
		dir := t.TempDir()
		path := filepath.Join(dir, ".pi", "agent", "settings.json")
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(shape), 0o644); err != nil {
			t.Fatal(err)
		}

		remover := &fakeRemover{present: true}
		code, err := Run(Options{
			Settings: path,
			Rules:    []Rule{{Type: "npm", Name: "gentle-pi"}},
		}, remover)
		if err != nil {
			t.Fatalf("shape %q: Run returned an error instead of degrading: %v", shape, err)
		}
		if code != 0 {
			t.Fatalf("shape %q: code = %d, want 0", shape, code)
		}
	}
}

func TestOneFailedRemovalStillAttemptsTheRest(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:gentle-pi@2.4.0", "npm:gentle-pi"})

	remover := &fakeRemover{present: true, failing: map[string]bool{"npm:gentle-pi@2.4.0": true}}
	code, err := Run(Options{Settings: settings, Rules: []Rule{{Type: "npm", Name: "gentle-pi"}}}, remover)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 {
		t.Fatalf("code = %d, want 0 even after a failed pi remove", code)
	}
	assertEntries(t, remover.removed, []string{"npm:gentle-pi"})
}

func TestRuleWithoutItsReplacementInstalledRetiresNothing(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:gentle-pi"})

	remover := &fakeRemover{present: true}
	rules := []Rule{{
		Type:   "npm",
		Name:   "gentle-pi",
		Wanted: ptr("git:github.com/Gentleman-Programming/gentle-pi@newrev"),
	}}
	if _, err := Run(Options{Settings: settings, Rules: rules}, remover); err != nil {
		t.Fatal(err)
	}
	if len(remover.removed) != 0 {
		t.Fatalf("retired an entry without its replacement present: %v", remover.removed)
	}
}

func TestRuleWithItsReplacementInstalledRetiresTheDisplacedEntry(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{
		"npm:gentle-pi",
		"git:github.com/Gentleman-Programming/gentle-pi@newrev",
	})

	remover := &fakeRemover{present: true}
	rules := []Rule{{
		Type:   "npm",
		Name:   "gentle-pi",
		Wanted: ptr("git:github.com/Gentleman-Programming/gentle-pi@newrev"),
	}}
	if _, err := Run(Options{Settings: settings, Rules: rules}, remover); err != nil {
		t.Fatal(err)
	}
	assertEntries(t, remover.removed, []string{"npm:gentle-pi"})
}

func TestPiNotOnPathSkipsWithoutFailing(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:gentle-pi"})

	remover := &fakeRemover{present: false}
	code, err := Run(Options{Settings: settings, Rules: []Rule{{Type: "npm", Name: "gentle-pi"}}}, remover)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 || len(remover.removed) != 0 {
		t.Fatalf("code=%d removed=%v, want 0 and none", code, remover.removed)
	}
}

func TestNoRulesOrNoPackagesIsANoop(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:gentle-pi"})
	remover := &fakeRemover{present: true}
	if _, err := Run(Options{Settings: settings, Rules: nil}, remover); err != nil {
		t.Fatal(err)
	}
	if len(remover.removed) != 0 {
		t.Fatal("no rules must retire nothing")
	}

	dir2 := t.TempDir()
	settings2 := writeSettings(t, dir2, nil)
	if _, err := Run(Options{Settings: settings2, Rules: []Rule{{Type: "npm", Name: "gentle-pi"}}}, remover); err != nil {
		t.Fatal(err)
	}
	if len(remover.removed) != 0 {
		t.Fatal("no installed packages must retire nothing")
	}
}

func ptr(s string) *string { return &s }
