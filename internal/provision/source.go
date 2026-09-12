package provision

import (
	"fmt"
	"strings"
)

// ValidSource reports whether s is one of the install source shapes
// gentle-nix accepts for a Pi package: an "npm:", "git:", "https://", or
// "ssh://" reference with a non-empty payload after its prefix, or an
// absolute local path carrying at least one non-empty component after the
// leading "/". A value padded with leading or trailing whitespace is never
// valid, even when trimming it would produce an accepted shape -- gentle-nix
// passes sources through verbatim to Pi's own installer, which does not
// trim them either.
func ValidSource(s string) bool {
	if s == "" || strings.TrimSpace(s) != s {
		return false
	}

	for _, prefix := range []string{"npm:", "git:", "https://", "ssh://"} {
		if strings.HasPrefix(s, prefix) {
			return s[len(prefix):] != ""
		}
	}

	if strings.HasPrefix(s, "/") {
		for _, part := range strings.Split(s, "/") {
			if part != "" {
				return true
			}
		}
		return false
	}

	return false
}

// InvalidSourceError reports value as an unsupported Pi package source,
// naming the accepted shapes so the mistake is obvious without reading this
// package's source.
func InvalidSourceError(value string) error {
	return fmt.Errorf(
		"unsupported Pi package source %q: use npm:<name>[@version], git:<host>/<user>/<repo>[@ref], an https:// or ssh:// URL, or an absolute path",
		value,
	)
}
