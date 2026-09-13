package skills

import (
	"os"
	"path/filepath"
	"testing"
)

func mkSkill(t *testing.T, dir, id string) {
	t.Helper()
	skillDir := filepath.Join(dir, id)
	if err := os.MkdirAll(skillDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte("# "+id), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertExists(t *testing.T, dir, id string) {
	t.Helper()
	if _, err := os.Stat(filepath.Join(dir, id)); err != nil {
		t.Fatalf("expected %q to exist in %q: %v", id, dir, err)
	}
}

func assertGone(t *testing.T, dir, id string) {
	t.Helper()
	if _, err := os.Stat(filepath.Join(dir, id)); !os.IsNotExist(err) {
		t.Fatalf("expected %q pruned from %q", id, dir)
	}
}

func TestResolveFlatMinusExclusions(t *testing.T) {
	spec := Spec{
		Flat:       []string{"a", "b", "c"},
		Exclusions: []string{"b"},
	}

	got, _ := Resolve(spec, "claude-code")
	want := []string{"a", "c"}
	if !equalStrings(got, want) {
		t.Fatalf("Resolve() = %v, want %v", got, want)
	}
}

func TestResolveAssignmentReplacesFlatEntirely(t *testing.T) {
	spec := Spec{
		Flat:       []string{"a", "b", "c"},
		Exclusions: []string{"b"},
		Assignments: map[string][]string{
			"opencode": {"b", "z"},
		},
	}

	// Own assignment: exclusions are NOT applied to it.
	got, _ := Resolve(spec, "opencode")
	want := []string{"b", "z"}
	if !equalStrings(got, want) {
		t.Fatalf("Resolve(opencode) = %v, want %v", got, want)
	}

	// Untouched adapter still gets flat minus exclusions.
	got, _ = Resolve(spec, "claude-code")
	want = []string{"a", "c"}
	if !equalStrings(got, want) {
		t.Fatalf("Resolve(claude-code) = %v, want %v", got, want)
	}
}

// Flat nil (never declared) with no assignment: nothing explicit to resolve.
func TestResolveDefaultSetWhenFlatNotDeclared(t *testing.T) {
	spec := Spec{Exclusions: []string{"b"}}

	_, explicit := Resolve(spec, "claude-code")
	if explicit {
		t.Fatal("Resolve() explicit = true, want false: flat was never declared")
	}
}

func equalStrings(a, b []string) bool {
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

func TestPruneRemovesSkillsOutsideResolvedSet(t *testing.T) {
	tree := t.TempDir()
	claudeSkills := filepath.Join(tree, ".claude", "skills")
	mkSkill(t, claudeSkills, "a")
	mkSkill(t, claudeSkills, "b")
	mkSkill(t, claudeSkills, "c")

	spec := Spec{
		Agents:     []string{"claude-code"},
		Flat:       []string{"a", "b", "c"},
		Exclusions: []string{"b"},
	}

	if err := Prune(tree, spec); err != nil {
		t.Fatal(err)
	}

	for _, want := range []string{"a", "c"} {
		if _, err := os.Stat(filepath.Join(claudeSkills, want)); err != nil {
			t.Fatalf("expected %q to survive pruning: %v", want, err)
		}
	}
	if _, err := os.Stat(filepath.Join(claudeSkills, "b")); !os.IsNotExist(err) {
		t.Fatalf("expected excluded skill %q to be pruned, stat err = %v", "b", err)
	}
}

func TestPruneKeepsPerClientAssignmentAndFlatSetSeparate(t *testing.T) {
	tree := t.TempDir()
	claudeSkills := filepath.Join(tree, ".claude", "skills")
	opencodeSkills := filepath.Join(tree, ".config", "opencode", "skills")
	for _, dir := range []string{claudeSkills, opencodeSkills} {
		mkSkill(t, dir, "a")
		mkSkill(t, dir, "b")
		mkSkill(t, dir, "c")
	}

	spec := Spec{
		Agents:     []string{"claude-code", "opencode"},
		Flat:       []string{"a", "b", "c"},
		Exclusions: []string{"b"},
		Assignments: map[string][]string{
			"opencode": {"c"},
		},
	}

	if err := Prune(tree, spec); err != nil {
		t.Fatal(err)
	}

	// claude-code: flat minus exclusions -> a, c survive; b pruned.
	if _, err := os.Stat(filepath.Join(claudeSkills, "b")); !os.IsNotExist(err) {
		t.Fatal("expected b pruned from claude-code")
	}
	if _, err := os.Stat(filepath.Join(claudeSkills, "a")); err != nil {
		t.Fatal("expected a to survive for claude-code")
	}

	// opencode: its own assignment -> only c survives.
	if _, err := os.Stat(filepath.Join(opencodeSkills, "a")); !os.IsNotExist(err) {
		t.Fatal("expected a pruned from opencode (its own assignment excludes it)")
	}
	if _, err := os.Stat(filepath.Join(opencodeSkills, "b")); !os.IsNotExist(err) {
		t.Fatal("expected b pruned from opencode")
	}
	if _, err := os.Stat(filepath.Join(opencodeSkills, "c")); err != nil {
		t.Fatal("expected c to survive for opencode")
	}
}

// Two regressions in one: Flat undeclared must never read as "empty", or a
// client with no assignment of its own gets wiped to nothing instead of
// keeping its default set.
func TestPruneKeepsDefaultSetWhenFlatUndeclared(t *testing.T) {
	newTree := func() (tree, claude, opencode string) {
		tree = t.TempDir()
		claude = filepath.Join(tree, ".claude", "skills")
		opencode = filepath.Join(tree, ".config", "opencode", "skills")
		for _, dir := range []string{claude, opencode} {
			mkSkill(t, dir, "a")
			mkSkill(t, dir, "b")
			mkSkill(t, dir, "c")
		}
		return
	}

	t.Run("exclusionsOnly", func(t *testing.T) {
		tree, claude, _ := newTree()
		spec := Spec{Agents: []string{"claude-code"}, Exclusions: []string{"b"}}
		if err := Prune(tree, spec); err != nil {
			t.Fatal(err)
		}
		assertExists(t, claude, "a")
		assertExists(t, claude, "c")
		assertGone(t, claude, "b")
	})

	t.Run("assignmentOnly", func(t *testing.T) {
		tree, claude, opencode := newTree()
		spec := Spec{
			Agents:      []string{"claude-code", "opencode"},
			Assignments: map[string][]string{"opencode": {"c"}},
		}
		if err := Prune(tree, spec); err != nil {
			t.Fatal(err)
		}
		assertExists(t, claude, "a")
		assertExists(t, claude, "b")
		assertExists(t, claude, "c")
		assertExists(t, opencode, "c")
		assertGone(t, opencode, "a")
		assertGone(t, opencode, "b")
	})
}

func TestPruneNoopWhenSkillsDirAbsent(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{Agents: []string{"claude-code"}, Flat: []string{"a"}}

	if err := Prune(tree, spec); err != nil {
		t.Fatalf("Prune() with no skills dir on disk should be a no-op, got %v", err)
	}
}

func TestPruneSkipsAgentWithNoSkillsDirectory(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{Agents: []string{"pi"}, Flat: []string{"a"}}

	if err := Prune(tree, spec); err != nil {
		t.Fatalf("Prune() for an agent with no skills concept should be a no-op, got %v", err)
	}
}

func TestPruneNeverTouchesPathsOutsideSkillsDirectories(t *testing.T) {
	tree := t.TempDir()
	sentinel := filepath.Join(tree, ".claude", "settings.json")
	if err := os.MkdirAll(filepath.Dir(sentinel), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sentinel, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}

	spec := Spec{Agents: []string{"claude-code"}, Flat: []string{}}
	if err := Prune(tree, spec); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(sentinel); err != nil {
		t.Fatalf("Prune() must never touch files outside a skills directory: %v", err)
	}
}
