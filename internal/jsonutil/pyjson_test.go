package jsonutil

import (
	"crypto/sha256"
	"encoding/hex"
	"testing"
)

// These expectations were produced by running the exact Python expression
// the module used to hash a command list:
//
//	json.dumps(commands, sort_keys=True).encode("utf-8")
//
// A stamp file written by the Python provisioner must still read as
// up-to-date once gentle-nix takes over, so the encoding this package
// produces has to match Python's default separators (", " and ": ") byte
// for byte, not just decode to an equal value.
func TestEncodeCommandsMatchesPythonJSONDumps(t *testing.T) {
	tests := []struct {
		name     string
		commands [][]string
		want     string
		wantHash string
	}{
		{
			name: "two commands",
			commands: [][]string{
				{"fake-pi", "install", "npm:gentle-pi"},
				{"fake-pi", "install", "npm:gentle-engram"},
			},
			want:     `[["fake-pi", "install", "npm:gentle-pi"], ["fake-pi", "install", "npm:gentle-engram"]]`,
			wantHash: "8aad27fbf87b66d8f267f37aeb005b7712e4ac6c314438cb971b2ecf427ab9d5",
		},
		{
			name:     "empty list",
			commands: [][]string{},
			want:     `[]`,
		},
		{
			name: "single command single arg",
			commands: [][]string{
				{"pi"},
			},
			want: `[["pi"]]`,
		},
		{
			name: "command containing a double quote and a backslash",
			commands: [][]string{
				{`say "hi"`, `back\slash`},
			},
			want: `[["say \"hi\"", "back\\slash"]]`,
		},
		{
			name: "command containing a non-ASCII character is escaped",
			commands: [][]string{
				{"café"},
			},
			want: `[["caf\u00e9"]]`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := EncodeCommands(tt.commands)
			if string(got) != tt.want {
				t.Fatalf("EncodeCommands(%v) = %q, want %q", tt.commands, got, tt.want)
			}
			if tt.wantHash != "" {
				sum := sha256.Sum256(got)
				if hex.EncodeToString(sum[:]) != tt.wantHash {
					t.Fatalf("sha256(EncodeCommands(%v)) = %x, want %s", tt.commands, sum, tt.wantHash)
				}
			}
		})
	}
}
