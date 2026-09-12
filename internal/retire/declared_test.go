package retire

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeDeclaredJSON(t *testing.T, path string, declared DeclaredPackages) {
	t.Helper()
	raw, err := json.Marshal(declared)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatal(err)
	}
}

// containsLine reports whether any of lines contains substr, so a test can
// assert a specific line was logged without pinning the exact wording.
func containsLine(lines []string, substr string) bool {
	for _, line := range lines {
		if strings.Contains(line, substr) {
			return true
		}
	}
	return false
}

func TestDroppedDeclaredNames(t *testing.T) {
	tests := []struct {
		name     string
		previous DeclaredPackages
		current  DeclaredPackages
		want     []string
	}{
		{
			name:     "added package is never dropped",
			previous: DeclaredPackages{"pi-foo": "npm:pi-foo"},
			current:  DeclaredPackages{"pi-foo": "npm:pi-foo", "pi-bar": "npm:pi-bar"},
			want:     nil,
		},
		{
			name:     "removed package is dropped",
			previous: DeclaredPackages{"pi-foo": "npm:pi-foo"},
			current:  DeclaredPackages{},
			want:     []string{"pi-foo"},
		},
		{
			name:     "source change without a key change is not dropped",
			previous: DeclaredPackages{"pi-foo": "npm:pi-foo@1.0.0"},
			current:  DeclaredPackages{"pi-foo": "npm:pi-foo@2.0.0"},
			want:     nil,
		},
		{
			name:     "a fixed harness name is excluded even when dropped",
			previous: DeclaredPackages{"pi-btw": "npm:pi-btw@1.2.3", "gentle-pi": "git:example.com/x@rev"},
			current:  DeclaredPackages{},
			want:     nil,
		},
		{
			name:     "first run has no previous record at all",
			previous: nil,
			current:  DeclaredPackages{"pi-foo": "npm:pi-foo"},
			want:     nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := droppedDeclaredNames(tt.previous, tt.current)
			assertEntries(t, got, tt.want)
		})
	}
}

func TestEntriesForDroppedNames(t *testing.T) {
	packages := []string{
		"npm:pi-foo",
		"npm:pi-foo@1.0.0",
		"git:github.com/x/pi-bar@abc",
		"npm:pi-btw",
	}

	tests := []struct {
		name  string
		names []string
		want  []string
	}{
		{name: "no dropped names retires nothing", names: nil, want: nil},
		{
			name:  "matches every installed entry sharing the dropped name",
			names: []string{"pi-foo"},
			want:  []string{"npm:pi-foo", "npm:pi-foo@1.0.0"},
		},
		{
			name:  "matches a git entry by its repository name",
			names: []string{"pi-bar"},
			want:  []string{"git:github.com/x/pi-bar@abc"},
		},
		{
			name:  "a name absent from the installed set matches nothing",
			names: []string{"pi-nonexistent"},
			want:  nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := entriesForDroppedNames(packages, tt.names)
			assertEntries(t, got, tt.want)
		})
	}
}

func TestRunRetiresAPackageDroppedFromTheDeclaredSet(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:pi-foo", "npm:unrelated"})

	declaredPath := filepath.Join(dir, "declared.json")
	writeDeclaredJSON(t, declaredPath, DeclaredPackages{})

	recordPath := filepath.Join(dir, "state", "pi-declared-packages.json")
	writeDeclaredJSON(t, recordPath, DeclaredPackages{"pi-foo": "npm:pi-foo"})

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{
		Settings:       settings,
		Declared:       declaredPath,
		DeclaredRecord: recordPath,
	}, remover); err != nil {
		t.Fatal(err)
	}

	assertEntries(t, remover.removed, []string{"npm:pi-foo"})
}

func TestRunKeepsAPackageStillDeclared(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:pi-foo"})

	declaredPath := filepath.Join(dir, "declared.json")
	writeDeclaredJSON(t, declaredPath, DeclaredPackages{"pi-foo": "npm:pi-foo"})

	recordPath := filepath.Join(dir, "state", "pi-declared-packages.json")
	writeDeclaredJSON(t, recordPath, DeclaredPackages{"pi-foo": "npm:pi-foo"})

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{
		Settings:       settings,
		Declared:       declaredPath,
		DeclaredRecord: recordPath,
	}, remover); err != nil {
		t.Fatal(err)
	}

	if len(remover.removed) != 0 {
		t.Fatalf("a still-declared package was retired: %v", remover.removed)
	}
}

func TestRunRetiresOnlyTheDroppedSourceNotTheStillWantedOne(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:pi-foo@1.0.0", "npm:pi-foo@2.0.0"})

	declaredPath := filepath.Join(dir, "declared.json")
	writeDeclaredJSON(t, declaredPath, DeclaredPackages{"pi-foo": "npm:pi-foo@2.0.0"})

	recordPath := filepath.Join(dir, "state", "pi-declared-packages.json")
	writeDeclaredJSON(t, recordPath, DeclaredPackages{"pi-foo": "npm:pi-foo@1.0.0"})

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{
		Settings:       settings,
		Declared:       declaredPath,
		DeclaredRecord: recordPath,
	}, remover); err != nil {
		t.Fatal(err)
	}

	// A source change for the same declared name is not a drop -- the key
	// "pi-foo" is in both records -- so nothing here is retired by the
	// declared-set diff (a displaced "package" Rule is what a channel or a
	// document uses to retire a source change instead).
	if len(remover.removed) != 0 {
		t.Fatalf("a source change was treated as a removal: %v", remover.removed)
	}
}

func TestRunExcludesAFixedHarnessNameFromDeclaredSetRetirement(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:pi-btw@1.2.3"})

	declaredPath := filepath.Join(dir, "declared.json")
	writeDeclaredJSON(t, declaredPath, DeclaredPackages{})

	recordPath := filepath.Join(dir, "state", "pi-declared-packages.json")
	writeDeclaredJSON(t, recordPath, DeclaredPackages{"pi-btw": "npm:pi-btw@1.2.3"})

	remover := &fakeRemover{present: true}
	if _, err := Run(Options{
		Settings:       settings,
		Declared:       declaredPath,
		DeclaredRecord: recordPath,
	}, remover); err != nil {
		t.Fatal(err)
	}

	if len(remover.removed) != 0 {
		t.Fatalf("dropping a fixed-name override retired the harness default: %v", remover.removed)
	}
}

func TestRunFirstRunOnlyRecordsAndRetiresNothing(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:pi-foo"})

	declaredPath := filepath.Join(dir, "declared.json")
	writeDeclaredJSON(t, declaredPath, DeclaredPackages{"pi-foo": "npm:pi-foo"})

	recordPath := filepath.Join(dir, "state", "pi-declared-packages.json")

	remover := &recordingRemover{fakeRemover: fakeRemover{present: true}}
	if _, err := Run(Options{
		Settings:       settings,
		Declared:       declaredPath,
		DeclaredRecord: recordPath,
	}, remover); err != nil {
		t.Fatal(err)
	}

	if len(remover.removed) != 0 {
		t.Fatalf("a first run retired something: %v", remover.removed)
	}
	if !containsLine(remover.lines, "no declared Pi packages record yet") {
		t.Fatalf("no first-run line was logged, got: %v", remover.lines)
	}

	raw, err := os.ReadFile(recordPath)
	if err != nil {
		t.Fatalf("the record was never written: %v", err)
	}
	var written DeclaredPackages
	if err := json.Unmarshal(raw, &written); err != nil {
		t.Fatal(err)
	}
	if written["pi-foo"] != "npm:pi-foo" {
		t.Fatalf("record = %v, want the current declared set", written)
	}
}

func TestRunMalformedPreviousRecordIsTreatedAsEmpty(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:pi-foo"})

	declaredPath := filepath.Join(dir, "declared.json")
	writeDeclaredJSON(t, declaredPath, DeclaredPackages{"pi-foo": "npm:pi-foo"})

	recordPath := filepath.Join(dir, "state", "pi-declared-packages.json")
	if err := os.MkdirAll(filepath.Dir(recordPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(recordPath, []byte("{ not json"), 0o644); err != nil {
		t.Fatal(err)
	}

	remover := &recordingRemover{fakeRemover: fakeRemover{present: true}}
	if _, err := Run(Options{
		Settings:       settings,
		Declared:       declaredPath,
		DeclaredRecord: recordPath,
	}, remover); err != nil {
		t.Fatal(err)
	}

	if len(remover.removed) != 0 {
		t.Fatalf("a malformed previous record retired something: %v", remover.removed)
	}
	if !containsLine(remover.lines, "malformed") {
		t.Fatalf("no malformed-record line was logged, got: %v", remover.lines)
	}
}

func TestRunRecordsTheCurrentSetEvenWhenARemovalFails(t *testing.T) {
	dir := t.TempDir()
	settings := writeSettings(t, dir, []string{"npm:pi-foo"})

	declaredPath := filepath.Join(dir, "declared.json")
	writeDeclaredJSON(t, declaredPath, DeclaredPackages{})

	recordPath := filepath.Join(dir, "state", "pi-declared-packages.json")
	writeDeclaredJSON(t, recordPath, DeclaredPackages{"pi-foo": "npm:pi-foo"})

	remover := &fakeRemover{present: true, failing: map[string]bool{"npm:pi-foo": true}}
	code, err := Run(Options{
		Settings:       settings,
		Declared:       declaredPath,
		DeclaredRecord: recordPath,
	}, remover)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 {
		t.Fatalf("code = %d, want 0 even after a failed pi remove", code)
	}

	raw, err := os.ReadFile(recordPath)
	if err != nil {
		t.Fatalf("the record was never written after a failed removal: %v", err)
	}
	var written DeclaredPackages
	if err := json.Unmarshal(raw, &written); err != nil {
		t.Fatal(err)
	}
	if len(written) != 0 {
		t.Fatalf("record = %v, want the empty current declared set", written)
	}
}

// recordingRemover is fakeRemover with a Printf that keeps every line, for
// the tests above that assert a specific line was logged.
type recordingRemover struct {
	fakeRemover
	lines []string
}

func (r *recordingRemover) Printf(format string, args ...any) {
	r.lines = append(r.lines, fmt.Sprintf(format, args...))
}
