// Package rewrite ports lib/rewrite.py: copying a rendered subtree while
// pointing its cross-references at the copy, so prose that names the
// directory it was rendered for still resolves once the same files sit
// under a different client's root.
//
// Only text is rewritten. Anything that does not decode as UTF-8 is
// copied byte for byte, because a substring that looks like a path inside
// a binary is not one.
package rewrite

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"
)

// CompileReplacements builds one alternation, most specific (longest)
// pattern first, so each position in a file is rewritten at most once --
// applying the patterns one after another would let a later, shorter
// pattern match inside what an earlier one already produced. pairs with
// no entries return a nil pattern, which Rewrite treats as "leave data
// unchanged" without even attempting a UTF-8 decode.
func CompileReplacements(pairs [][2]string) (*regexp.Regexp, map[string]string) {
	table := make(map[string]string, len(pairs))
	for _, pair := range pairs {
		table[pair[0]] = pair[1]
	}
	if len(table) == 0 {
		return nil, table
	}

	ordered := make([]string, 0, len(table))
	for from := range table {
		ordered = append(ordered, from)
	}
	sort.Slice(ordered, func(i, j int) bool { return len(ordered[i]) > len(ordered[j]) })

	quoted := make([]string, len(ordered))
	for i, from := range ordered {
		quoted[i] = regexp.QuoteMeta(from)
	}

	return regexp.MustCompile(strings.Join(quoted, "|")), table
}

// Rewrite is rewrite() from rewrite.py: substitute every match of pattern
// in data, looking each match up in table, unless data does not decode as
// UTF-8 -- in which case it is returned unchanged, since a substring that
// looks like a path inside a binary is not one.
func Rewrite(data []byte, pattern *regexp.Regexp, table map[string]string) []byte {
	if pattern == nil {
		return data
	}
	if !utf8.Valid(data) {
		return data
	}

	return pattern.ReplaceAllFunc(data, func(match []byte) []byte {
		return []byte(table[string(match)])
	})
}

// CopyTree is copy_tree from rewrite.py: recurse through source, mirroring
// its structure exactly under target, rewriting file content and copying
// through symbolic links (the source is a store tree of them) rather than
// re-creating them as links. Every delivered file gains the owner-write
// bit, since the store copy it came from is read-only.
func CopyTree(source, target string, pattern *regexp.Regexp, table map[string]string) error {
	info, err := os.Stat(source)
	if err != nil {
		return err
	}

	if info.IsDir() {
		if err := os.MkdirAll(target, 0o777); err != nil {
			return err
		}
		entries, err := os.ReadDir(source)
		if err != nil {
			return err
		}
		names := make([]string, len(entries))
		for i, entry := range entries {
			names[i] = entry.Name()
		}
		sort.Strings(names)

		for _, name := range names {
			if err := CopyTree(filepath.Join(source, name), filepath.Join(target, name), pattern, table); err != nil {
				return err
			}
		}
		return nil
	}

	if err := os.MkdirAll(filepath.Dir(target), 0o777); err != nil {
		return err
	}

	data, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	if err := os.WriteFile(target, Rewrite(data, pattern, table), info.Mode().Perm()); err != nil {
		return err
	}

	return os.Chmod(target, (info.Mode().Perm() | 0o200))
}

// ParseReplaceArgument splits a --replace FROM=TO argument the way
// main()'s partition("=") does: the first "=" separates the two halves,
// and either a missing "=" or an empty FROM is rejected.
func ParseReplaceArgument(arg string) (from, to string, err error) {
	sourceReference, targetReference, found := strings.Cut(arg, "=")
	if !found || sourceReference == "" {
		return "", "", fmt.Errorf("--replace expects FROM=TO, got %q", arg)
	}
	return sourceReference, targetReference, nil
}
