package provision

import "testing"

func TestValidSource(t *testing.T) {
	cases := []struct {
		name  string
		value string
		want  bool
	}{
		{"npm bare name", "npm:pi-btw", true},
		{"npm with version", "npm:pi-btw@1.2.3", true},
		{"npm empty payload", "npm:", false},
		{"git host/user/repo", "git:github.com/x/y", true},
		{"git with ref", "git:github.com/x/y@rev", true},
		{"git empty payload", "git:", false},
		{"https url", "https://example.com/pkg.tgz", true},
		{"https empty payload", "https://", false},
		{"ssh url", "ssh://git@example.com/x/y.git", true},
		{"ssh empty payload", "ssh://", false},
		{"absolute path", "/home/user/plugins/pi-btw", true},
		{"root only", "/", false},
		{"empty string", "", false},
		{"bare package name missing scheme", "@gtrabanco/pi-nan-provider", false},
		{"relative path", "plugins/pi-btw", false},
		{"leading whitespace", " npm:pi-btw", false},
		{"trailing whitespace", "npm:pi-btw ", false},
		{"whitespace only", "   ", false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := ValidSource(tc.value); got != tc.want {
				t.Fatalf("ValidSource(%q) = %v, want %v", tc.value, got, tc.want)
			}
		})
	}
}

func TestInvalidSourceErrorNamesTheValueAndAcceptedShapes(t *testing.T) {
	err := InvalidSourceError("@scope/name")
	want := `unsupported Pi package source "@scope/name": use npm:<name>[@version], git:<host>/<user>/<repo>[@ref], an https:// or ssh:// URL, or an absolute path`
	if err.Error() != want {
		t.Fatalf("error = %q, want %q", err.Error(), want)
	}
}
