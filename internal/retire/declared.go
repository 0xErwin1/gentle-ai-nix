package retire

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
)

// fixedPiPackageNames mirrors fixedPiPackageNames in
// modules/home-manager.nix: the npm package names `gentle-nix provision`'s
// Pi adapter always installs on its own, regardless of what
// providers.pi.packages says. A key naming one of these overrides that
// package's install source in place rather than declaring a second,
// independent package -- so dropping such a key from the set is not a
// removal, it is going back to the harness's own default source, and none
// of these names is ever retired through the declared-set diff below.
var fixedPiPackageNames = map[string]bool{
	"gentle-pi":                          true,
	"gentle-engram":                      true,
	"pi-mcp-adapter":                     true,
	"@juicesharp/rpiv-ask-user-question": true,
	"pi-web-access":                      true,
	"pi-btw":                             true,
}

// DeclaredPackages is providers.pi.packages the way the Nix option itself
// carries it: package name -> Pi install source.
type DeclaredPackages map[string]string

// readDeclaredPackages decodes path, the current generation's own declared
// set. An empty path (the feature disabled), a missing file, or one this
// step cannot parse all degrade to an empty set rather than failing the
// switch over a file gentle-nix does not own -- installedPackages already
// follows the same policy for Pi's own settings.json.
func readDeclaredPackages(path string, printf func(string, ...any)) DeclaredPackages {
	if path == "" {
		return nil
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		printf("gentle-ai: cannot read declared Pi packages %s: %v", path, err)
		return nil
	}
	var declared DeclaredPackages
	if err := json.Unmarshal(raw, &declared); err != nil {
		printf("gentle-ai: declared Pi packages %s is malformed, treating as empty: %v", path, err)
		return nil
	}
	return declared
}

// readDeclaredRecord decodes the previous generation's persisted declared
// set. The bool return is whether a record was found at all: false means
// this is the first run this record has ever seen, which is different
// from a record that existed but declared nothing -- both leave dropped
// nil, but only the second one is a record actually read.
func readDeclaredRecord(path string, printf func(string, ...any)) (record DeclaredPackages, existed bool) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}
	if err := json.Unmarshal(raw, &record); err != nil {
		printf("gentle-ai: declared Pi packages record %s is malformed, treating as empty: %v", path, err)
		return nil, true
	}
	return record, true
}

// droppedDeclaredNames is the package names the previous generation's
// record declared that the current declared set no longer does, minus
// Pi's own fixed harness names. Order is deterministic (sorted) so the
// entries retired for them, and any log line naming them, do not depend
// on Go's random map iteration.
func droppedDeclaredNames(previous, current DeclaredPackages) []string {
	var dropped []string
	for name := range previous {
		if _, ok := current[name]; ok {
			continue
		}
		if fixedPiPackageNames[name] {
			continue
		}
		dropped = append(dropped, name)
	}
	sort.Strings(dropped)
	return dropped
}

// entriesForDroppedNames is the installed entries -- Pi's own, freshly
// read package list -- whose source-derived package name (packageNameOf,
// the same derivation a "package" Rule's Keep is compared by) matches one
// of names. Unlike a "package" Rule's Keep, a dropped declaration has no
// spelling left to except: every matching entry is retired, the exact
// previously declared source included.
func entriesForDroppedNames(packages []string, names []string) []string {
	if len(names) == 0 {
		return nil
	}
	wanted := make(map[string]bool, len(names))
	for _, name := range names {
		wanted[name] = true
	}
	var entries []string
	for _, entry := range packages {
		if wanted[packageNameOf(entry)] {
			entries = append(entries, entry)
		}
	}
	return entries
}

// writeDeclaredRecord persists current at path for the next generation to
// diff against, through a temporary file and rename -- the same
// write-then-rename WriteStamp in internal/provision uses -- so a write
// interrupted midway never leaves a truncated record that a later run
// misreads as an empty declared set and retires everything still declared.
func writeDeclaredRecord(path string, current DeclaredPackages) error {
	if current == nil {
		current = DeclaredPackages{}
	}
	encoded, err := json.Marshal(current)
	if err != nil {
		return err
	}

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o777); err != nil {
		return err
	}

	temp, err := os.CreateTemp(dir, "")
	if err != nil {
		return err
	}
	tempName := temp.Name()

	if _, err := temp.Write(encoded); err != nil {
		temp.Close()
		os.Remove(tempName)
		return err
	}
	if err := temp.Close(); err != nil {
		os.Remove(tempName)
		return err
	}

	return os.Rename(tempName, path)
}
