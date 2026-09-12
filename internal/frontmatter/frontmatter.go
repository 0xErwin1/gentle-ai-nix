// Package frontmatter ports lib/frontmatter.py: copying a subtree while
// filling missing frontmatter keys in its markdown files.
//
// Only a missing key is filled -- a file that already states the key
// keeps its own value, whatever it is, because a default that overwrote a
// stated value would be a rename wearing a default's name. Files without
// a frontmatter block, or with an unclosed one, are copied untouched:
// inventing a block would also invent the required fields the receiving
// client checks before this one, and a loud parse failure there beats a
// silently half-valid definition here.
package frontmatter

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"
)

var frontmatterKeyPattern = regexp.MustCompile(`^([A-Za-z0-9_-]+)\s*:`)

// FillFrontmatter is fill_frontmatter from frontmatter.py: insert each
// default key defaults names but text does not already state, just
// before the closing "---" delimiter, in sorted key order. Text without
// an opening "---" on its first line, or without a matching closing
// "---" line, is returned unchanged.
func FillFrontmatter(text string, defaults map[string]string) string {
	lines := strings.Split(text, "\n")
	if len(lines) == 0 || strings.TrimSpace(lines[0]) != "---" {
		return text
	}

	closing := -1
	for i := 1; i < len(lines); i++ {
		if strings.TrimSpace(lines[i]) == "---" {
			closing = i
			break
		}
	}
	if closing == -1 {
		return text
	}

	stated := make(map[string]bool)
	for _, line := range lines[1:closing] {
		if match := frontmatterKeyPattern.FindStringSubmatch(line); match != nil {
			stated[match[1]] = true
		}
	}

	keys := make([]string, 0, len(defaults))
	for key := range defaults {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	var missing []string
	for _, key := range keys {
		if !stated[key] {
			missing = append(missing, key)
		}
	}
	if len(missing) == 0 {
		return text
	}

	inserted := make([]string, len(missing))
	for i, key := range missing {
		inserted[i] = fmt.Sprintf("%s: %s", key, defaults[key])
	}

	result := make([]string, 0, len(lines)+len(inserted))
	result = append(result, lines[:closing]...)
	result = append(result, inserted...)
	result = append(result, lines[closing:]...)

	return strings.Join(result, "\n")
}

// Fill is fill() from frontmatter.py: apply FillFrontmatter to data
// decoded as UTF-8, or return data unchanged when it does not decode.
func Fill(data []byte, defaults map[string]string) []byte {
	if !utf8.Valid(data) {
		return data
	}
	return []byte(FillFrontmatter(string(data), defaults))
}

// CopyTree is copy_tree from frontmatter.py: recurse through source,
// mirroring its structure exactly under target, filling frontmatter only
// in files named "*.md" and copying through symbolic links since the
// source is a store tree of them. Every delivered file gains the
// owner-write bit, since the store copy it came from is read-only.
func CopyTree(source, target string, defaults map[string]string) error {
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
			if err := CopyTree(filepath.Join(source, name), filepath.Join(target, name), defaults); err != nil {
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
	if filepath.Ext(source) == ".md" {
		data = Fill(data, defaults)
	}
	if err := os.WriteFile(target, data, info.Mode().Perm()); err != nil {
		return err
	}

	return os.Chmod(target, info.Mode().Perm()|0o200)
}

// ParseDefaultArgument splits a --default KEY=VALUE argument the way
// main()'s partition("=") does: the first "=" separates the two halves,
// and either a missing "=" or an empty KEY is rejected.
func ParseDefaultArgument(arg string) (key, value string, err error) {
	k, v, found := strings.Cut(arg, "=")
	if !found || k == "" {
		return "", "", fmt.Errorf("--default expects KEY=VALUE, got %q", arg)
	}
	return k, v, nil
}
