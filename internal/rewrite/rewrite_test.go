package rewrite

import (
	"os"
	"path/filepath"
	"testing"
)

// TestRewriteBytes exercises the pure substitution rewrite.py's rewrite()
// performs: a single alternation pass, most specific (longest) pattern
// first so a position is never rewritten twice, and invalid UTF-8 left
// untouched byte for byte.
func TestRewriteBytes(t *testing.T) {
	tests := []struct {
		name     string
		data     []byte
		replace  map[string]string
		wantText string
		wantSame bool // when true, data must come back unchanged (invalid UTF-8)
	}{
		{
			name:     "no replacements configured leaves text untouched",
			data:     []byte("~/.claude/skills/_shared/x.md"),
			replace:  map[string]string{},
			wantText: "~/.claude/skills/_shared/x.md",
		},
		{
			name: "most specific pattern wins over a shorter prefix",
			data: []byte("See ~/.claude/skills/_shared/x.md and .claude/CLAUDE.md itself."),
			replace: map[string]string{
				".claude/CLAUDE.md": "AGENTS.md",
				".claude/":          "agents-root/",
			},
			wantText: "See ~/agents-root/skills/_shared/x.md and AGENTS.md itself.",
		},
		{
			name:     "invalid utf-8 is copied byte for byte",
			data:     []byte{0x00, 0x01, 0xff, '.', 'c', 'l', 'a', 'u', 'd', 'e', '/'},
			replace:  map[string]string{".claude/": "agents-root/"},
			wantSame: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pattern, table := CompileReplacements(pairsOf(tt.replace))
			got := Rewrite(tt.data, pattern, table)
			if tt.wantSame {
				if string(got) != string(tt.data) {
					t.Fatalf("Rewrite(%q) = %q, want unchanged", tt.data, got)
				}
				return
			}
			if string(got) != tt.wantText {
				t.Fatalf("Rewrite(%q) = %q, want %q", tt.data, got, tt.wantText)
			}
		})
	}
}

func pairsOf(m map[string]string) [][2]string {
	var pairs [][2]string
	for from, to := range m {
		pairs = append(pairs, [2]string{from, to})
	}
	return pairs
}

// TestCopyTree is a filesystem-level test matching a golden run of
// lib/rewrite.py against the same fixture: two replacement rules, a plain
// file whose text names both the file being rewritten and the shared
// skills file, and a binary file whose bytes happen to contain a matching
// substring but must be copied unchanged because it does not decode as
// UTF-8.
//
// Expected outputs below were captured by running:
//
//	python3 lib/rewrite.py --source <fixture> --target <out> \
//	  --replace ".claude/CLAUDE.md=AGENTS.md" --replace ".claude/=agents-root/"
func TestCopyTree(t *testing.T) {
	src := t.TempDir()
	mustWriteFile(t, filepath.Join(src, ".claude", "CLAUDE.md"),
		"See ~/.claude/skills/_shared/sdd-orchestrator-workflow.md for details.\nAlso check .claude/CLAUDE.md itself.\n", 0o644)
	mustWriteFile(t, filepath.Join(src, ".claude", "skills", "_shared", "sdd-orchestrator-workflow.md"),
		"Shared workflow. References .claude/CLAUDE.md and .claude/skills/_shared/sdd-orchestrator-workflow.md.\n", 0o644)
	binary := []byte("\x00\x01binary\xffdata.claude/CLAUDE.md")
	mustWriteFile(t, filepath.Join(src, ".claude", "binary.bin"), string(binary), 0o644)

	target := filepath.Join(t.TempDir(), "out")
	pattern, table := CompileReplacements([][2]string{
		{".claude/CLAUDE.md", "AGENTS.md"},
		{".claude/", "agents-root/"},
	})

	if err := CopyTree(src, target, pattern, table); err != nil {
		t.Fatal(err)
	}

	assertFileContent(t, filepath.Join(target, ".claude", "CLAUDE.md"),
		"See ~/agents-root/skills/_shared/sdd-orchestrator-workflow.md for details.\nAlso check AGENTS.md itself.\n")
	assertFileContent(t, filepath.Join(target, ".claude", "skills", "_shared", "sdd-orchestrator-workflow.md"),
		"Shared workflow. References AGENTS.md and agents-root/skills/_shared/sdd-orchestrator-workflow.md.\n")

	gotBinary, err := os.ReadFile(filepath.Join(target, ".claude", "binary.bin"))
	if err != nil {
		t.Fatal(err)
	}
	if string(gotBinary) != string(binary) {
		t.Fatalf("binary file was rewritten: got %q, want %q (byte-for-byte, since it is not valid UTF-8)", gotBinary, binary)
	}
}

// TestCopyTreeFollowsSymlinksAndBumpsOwnerWriteBit matches a second golden
// run: a symlinked file and a symlinked directory in the source tree are
// both dereferenced (the source is a store tree of symlinks, per
// rewrite.py's own copy_tree docstring), and a read-only source file
// arrives writable by its owner, since the store's read-only bit would
// otherwise make the delivered copy unremovable by a later activation.
func TestCopyTreeFollowsSymlinksAndBumpsOwnerWriteBit(t *testing.T) {
	if os.Getuid() == 0 {
		t.Skip("permission bits are not enforced for root")
	}

	real := t.TempDir()
	realFile := filepath.Join(real, "real.md")
	mustWriteFile(t, realFile, "real content .claude/CLAUDE.md\n", 0o400)

	src := t.TempDir()
	if err := os.Symlink(realFile, filepath.Join(src, "linked.md")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real, filepath.Join(src, "linkeddir")); err != nil {
		t.Fatal(err)
	}

	target := filepath.Join(t.TempDir(), "out")
	pattern, table := CompileReplacements([][2]string{{".claude/CLAUDE.md", "AGENTS.md"}})

	if err := CopyTree(src, target, pattern, table); err != nil {
		t.Fatal(err)
	}

	for _, rel := range []string{"linked.md", filepath.Join("linkeddir", "real.md")} {
		path := filepath.Join(target, rel)
		assertFileContent(t, path, "real content AGENTS.md\n")

		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm()&0o200 == 0 {
			t.Fatalf("%s is not owner-writable: mode %o", rel, info.Mode().Perm())
		}
	}
}

func mustWriteFile(t *testing.T, path, content string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), mode); err != nil {
		t.Fatal(err)
	}
}

func assertFileContent(t *testing.T, path, want string) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}
	if string(got) != want {
		t.Fatalf("%s = %q, want %q", path, got, want)
	}
}

// TestParseReplaceArgument matches main()'s FROM=TO validation: an
// argument with no "=" or an empty FROM is rejected.
func TestParseReplaceArgument(t *testing.T) {
	tests := []struct {
		arg      string
		wantFrom string
		wantTo   string
		wantErr  bool
	}{
		{arg: "a=b", wantFrom: "a", wantTo: "b"},
		{arg: "a=b=c", wantFrom: "a", wantTo: "b=c"},
		{arg: "noequals", wantErr: true},
		{arg: "=novalue", wantErr: true},
		{arg: "empty=", wantFrom: "empty", wantTo: ""},
	}
	for _, tt := range tests {
		t.Run(tt.arg, func(t *testing.T) {
			from, to, err := ParseReplaceArgument(tt.arg)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("ParseReplaceArgument(%q) succeeded, want an error", tt.arg)
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseReplaceArgument(%q): %v", tt.arg, err)
			}
			if from != tt.wantFrom || to != tt.wantTo {
				t.Fatalf("ParseReplaceArgument(%q) = (%q, %q), want (%q, %q)", tt.arg, from, to, tt.wantFrom, tt.wantTo)
			}
		})
	}
}
