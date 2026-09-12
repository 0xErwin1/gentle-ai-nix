package frontmatter

import (
	"os"
	"path/filepath"
	"testing"
)

// Expected outputs below were captured from a golden run of
// lib/frontmatter.py with `--default mode=subagent --default another=value`
// against the same fixture files.
func TestFillFrontmatter(t *testing.T) {
	defaults := map[string]string{"mode": "subagent", "another": "value"}

	tests := []struct {
		name string
		text string
		want string
	}{
		{
			name: "every default already stated keeps its own values, unchanged order",
			text: "---\nname: foo\nmode: primary\n---\nBody text\n",
			want: "---\nname: foo\nmode: primary\nanother: value\n---\nBody text\n",
		},
		{
			name: "missing keys are inserted sorted by key, just before the closing delimiter",
			text: "---\nname: bar\n---\nBody\n",
			want: "---\nname: bar\nanother: value\nmode: subagent\n---\nBody\n",
		},
		{
			name: "no frontmatter block at all is returned untouched",
			text: "Just body, no frontmatter.\n",
			want: "Just body, no frontmatter.\n",
		},
		{
			name: "an unclosed frontmatter block is returned untouched",
			text: "---\nname: baz\nBody without closing delimiter\n",
			want: "---\nname: baz\nBody without closing delimiter\n",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := FillFrontmatter(tt.text, defaults)
			if got != tt.want {
				t.Fatalf("FillFrontmatter(%q) = %q, want %q", tt.text, got, tt.want)
			}
		})
	}
}

func TestFillFrontmatterWithNoDefaultsIsANoop(t *testing.T) {
	text := "---\nname: foo\n---\nBody\n"
	if got := FillFrontmatter(text, map[string]string{}); got != text {
		t.Fatalf("FillFrontmatter with no defaults changed the text: %q", got)
	}
}

func TestCopyTreeOnlyTouchesMarkdownFiles(t *testing.T) {
	src := t.TempDir()
	mustWriteFile(t, filepath.Join(src, "agent.md"), "---\nname: bar\n---\nBody\n")
	mustWriteFile(t, filepath.Join(src, "not.txt"), "---\nname: qux\n---\nshould not be touched, not .md\n")

	target := filepath.Join(t.TempDir(), "out")
	if err := CopyTree(src, target, map[string]string{"mode": "subagent"}); err != nil {
		t.Fatal(err)
	}

	assertContent(t, filepath.Join(target, "agent.md"), "---\nname: bar\nmode: subagent\n---\nBody\n")
	assertContent(t, filepath.Join(target, "not.txt"), "---\nname: qux\n---\nshould not be touched, not .md\n")
}

func TestCopyTreeLeavesInvalidUTF8Untouched(t *testing.T) {
	src := t.TempDir()
	binary := []byte{0x00, 0xff, '-', '-', '-', '\n', 'x', ':', ' ', '1', '\n', '-', '-', '-', '\n'}
	if err := os.WriteFile(filepath.Join(src, "weird.md"), binary, 0o644); err != nil {
		t.Fatal(err)
	}

	target := filepath.Join(t.TempDir(), "out")
	if err := CopyTree(src, target, map[string]string{"mode": "subagent"}); err != nil {
		t.Fatal(err)
	}

	got, err := os.ReadFile(filepath.Join(target, "weird.md"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(binary) {
		t.Fatalf("an invalid-UTF-8 .md file was modified: got %v, want %v", got, binary)
	}
}

func TestParseDefaultArgument(t *testing.T) {
	tests := []struct {
		arg     string
		wantKey string
		wantVal string
		wantErr bool
	}{
		{arg: "mode=subagent", wantKey: "mode", wantVal: "subagent"},
		{arg: "a=b=c", wantKey: "a", wantVal: "b=c"},
		{arg: "nokey", wantErr: true},
		{arg: "=value", wantErr: true},
		{arg: "key=", wantKey: "key", wantVal: ""},
	}
	for _, tt := range tests {
		t.Run(tt.arg, func(t *testing.T) {
			key, val, err := ParseDefaultArgument(tt.arg)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("ParseDefaultArgument(%q) succeeded, want an error", tt.arg)
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseDefaultArgument(%q): %v", tt.arg, err)
			}
			if key != tt.wantKey || val != tt.wantVal {
				t.Fatalf("ParseDefaultArgument(%q) = (%q, %q), want (%q, %q)", tt.arg, key, val, tt.wantKey, tt.wantVal)
			}
		})
	}
}

func mustWriteFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertContent(t *testing.T, path, want string) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}
	if string(got) != want {
		t.Fatalf("%s = %q, want %q", path, got, want)
	}
}
