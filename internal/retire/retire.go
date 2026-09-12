// Package retire ports lib/retire.py: dropping Pi package entries an
// earlier generation installed under an identity the current one no
// longer uses.
//
// Only entries Pi's own settings.json actually lists are ever named to
// `pi remove`, and settings.json is re-read fresh on every run rather than
// cached, so a converged file matches no rule and nothing runs -- the same
// idempotency the Python original relies on instead of a stamp of its own.
package retire

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// schemePrefixes are the prefixes that tell an npm spec or a git/plain-URL
// source apart from a filesystem path, which is compared a different way
// (by suffix, and by where it resolves to) than an exact or prefixed
// spelling.
var schemePrefixes = []string{"npm:", "git:", "https://", "ssh://"}

func hasSchemePrefix(entry string) bool {
	for _, prefix := range schemePrefixes {
		if strings.HasPrefix(entry, prefix) {
			return true
		}
	}
	return false
}

// Rule is one displaced-package identity rule, the Go shape of the JSON
// object retire.py receives once per --displaced argument. Not every
// field applies to every Type; matches_rule dispatches on Type the same
// way the Python original's matches_rule does.
type Rule struct {
	Type     string   `json:"type"`
	Name     string   `json:"name,omitempty"`
	Patterns []string `json:"patterns,omitempty"`
	Except   *string  `json:"except,omitempty"`
	Keep     string   `json:"keep,omitempty"`
	// Wanted is a pointer so a rule that never mentions "wanted" (nil) is
	// told apart from one that gives it explicit JSON null -- rule.get
	// ("wanted") in Python returns None either way, so both map to nil
	// here and are treated identically by applicableRules.
	Wanted *string `json:"wanted,omitempty"`
}

// Remover is the process-execution boundary Run depends on.
type Remover interface {
	// LookPath reports whether "pi" resolves on PATH.
	LookPath(name string) bool
	// Remove runs `pi remove <entry>`, connecting the child's stdio to
	// this process's own, and reports whether it exited zero.
	Remove(entry string) bool
	// Printf writes one line to stderr.
	Printf(format string, args ...any)
}

// Options mirrors retire.py's argparse contract: --settings plus a
// repeated --displaced, already decoded into Rule values.
type Options struct {
	Settings string
	Rules    []Rule
}

// installedPackages is installed_packages: Pi's own declared packages,
// read best-effort. A settings.json this step cannot make sense of --
// missing, unreadable, truncated, or shaped unlike Pi's settings --
// degrades to "no packages" rather than failing the switch that happens
// to run alongside it.
func installedPackages(settingsPath string, printf func(string, ...any)) []string {
	raw, err := os.ReadFile(settingsPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		printf("gentle-ai: cannot read Pi settings %s: %v", settingsPath, err)
		return nil
	}

	var settings map[string]json.RawMessage
	if err := json.Unmarshal(raw, &settings); err != nil {
		printf("gentle-ai: cannot read Pi settings %s: %v", settingsPath, err)
		return nil
	}
	if settings == nil {
		// A top-level JSON value that decodes into a nil map (an array, a
		// number, a string, ...) is not a JSON object.
		printf("gentle-ai: Pi settings %s is not a JSON object", settingsPath)
		return nil
	}

	packagesRaw, ok := settings["packages"]
	if !ok {
		return nil
	}

	var packages []json.RawMessage
	if err := json.Unmarshal(packagesRaw, &packages); err != nil {
		return nil
	}

	var out []string
	for _, item := range packages {
		var s string
		if err := json.Unmarshal(item, &s); err == nil {
			out = append(out, s)
		}
	}
	return out
}

func matchesNpm(entry, name string) bool {
	prefix := "npm:" + name
	return entry == prefix || strings.HasPrefix(entry, prefix+"@")
}

var gitEntryPattern = func(name string) *regexp.Regexp {
	return regexp.MustCompile(`^git:.*/` + regexp.QuoteMeta(name) + `(@[^/]*)?$`)
}

func matchesGit(entry, name string) bool {
	return gitEntryPattern(name).MatchString(entry)
}

func resolvedLocal(entry, settingsDir string) string {
	located := entry
	if !filepath.IsAbs(entry) {
		located = filepath.Join(settingsDir, entry)
	}
	return filepath.Clean(located)
}

func matchesLocal(entry string, patterns []string, exception *string, settingsDir string) bool {
	if hasSchemePrefix(entry) {
		return false
	}

	matched := false
	for _, pattern := range patterns {
		if regexp.MustCompile(pattern).MatchString(entry) {
			matched = true
			break
		}
	}
	if !matched {
		return false
	}

	if exception == nil {
		return true
	}
	return resolvedLocal(entry, settingsDir) != filepath.Clean(*exception)
}

func npmPackageName(spec string) string {
	if strings.HasPrefix(spec, "@") {
		slash := strings.Index(spec, "/")
		if slash == -1 {
			return spec
		}
		at := strings.Index(spec[slash:], "@")
		if at == -1 {
			return spec
		}
		return spec[:slash+at]
	}
	at := strings.Index(spec, "@")
	if at == -1 {
		return spec
	}
	return spec[:at]
}

func repoPackageName(path string) string {
	beforePin := strings.SplitN(path, "@", 2)[0]
	beforePin = strings.TrimRight(beforePin, "/")
	segments := strings.Split(beforePin, "/")
	return segments[len(segments)-1]
}

func packageNameOf(source string) string {
	switch {
	case strings.HasPrefix(source, "npm:"):
		return npmPackageName(source[len("npm:"):])
	case strings.HasPrefix(source, "git:"):
		return repoPackageName(source[len("git:"):])
	case strings.HasPrefix(source, "https://"):
		return repoPackageName(source[len("https://"):])
	case strings.HasPrefix(source, "ssh://"):
		return repoPackageName(source[len("ssh://"):])
	default:
		return filepath.Base(strings.TrimRight(source, "/"))
	}
}

func matchesPackage(entry, keep string) bool {
	if entry == keep {
		return false
	}
	return packageNameOf(entry) == packageNameOf(keep)
}

func matchesRule(entry string, rule Rule, settingsDir string) (bool, error) {
	switch rule.Type {
	case "npm":
		return matchesNpm(entry, rule.Name), nil
	case "git":
		return matchesGit(entry, rule.Name), nil
	case "local":
		return matchesLocal(entry, rule.Patterns, rule.Except, settingsDir), nil
	case "package":
		return matchesPackage(entry, rule.Keep), nil
	default:
		return false, fmt.Errorf("unknown displaced-package rule type %q", rule.Type)
	}
}

func replacementPresent(wanted string, packages []string, settingsDir string) bool {
	if hasSchemePrefix(wanted) {
		for _, p := range packages {
			if p == wanted {
				return true
			}
		}
		return false
	}

	target := resolvedLocal(wanted, settingsDir)
	for _, entry := range packages {
		if !hasSchemePrefix(entry) && resolvedLocal(entry, settingsDir) == target {
			return true
		}
	}
	return false
}

// applicableRules is applicable_rules: a rule whose "wanted" replacement
// is not yet among Pi's own packages retires nothing this run, because
// retiring the entry it displaces before its replacement exists would
// turn a failed install into a missing harness rather than a previous,
// working one left in place.
func applicableRules(rules []Rule, packages []string, settingsDir string, printf func(string, ...any)) ([]Rule, error) {
	var applicable []Rule
	for _, rule := range rules {
		if rule.Wanted == nil || replacementPresent(*rule.Wanted, packages, settingsDir) {
			applicable = append(applicable, rule)
			continue
		}
		for _, entry := range packages {
			matched, err := matchesRule(entry, rule, settingsDir)
			if err != nil {
				return nil, err
			}
			if matched {
				printf("gentle-ai: kept %s: replacement %s is not installed", entry, *rule.Wanted)
			}
		}
	}
	return applicable, nil
}

func displacedEntries(packages []string, rules []Rule, settingsDir string) ([]string, error) {
	var displaced []string
	for _, entry := range packages {
		for _, rule := range rules {
			matched, err := matchesRule(entry, rule, settingsDir)
			if err != nil {
				return nil, err
			}
			if matched {
				displaced = append(displaced, entry)
				break
			}
		}
	}
	return displaced, nil
}

// Run is main() from retire.py: it always returns exit code 0, exactly
// like the Python original, whose only nonzero exit would come from
// argparse itself rejecting the command line.
func Run(opts Options, remover Remover) (int, error) {
	if len(opts.Rules) == 0 {
		return 0, nil
	}

	packages := installedPackages(opts.Settings, remover.Printf)
	if len(packages) == 0 {
		return 0, nil
	}

	absSettings, err := filepath.Abs(opts.Settings)
	if err != nil {
		return 0, err
	}
	settingsDir := filepath.Dir(absSettings)

	rules, err := applicableRules(opts.Rules, packages, settingsDir, remover.Printf)
	if err != nil {
		return 0, err
	}

	entries, err := displacedEntries(packages, rules, settingsDir)
	if err != nil {
		return 0, err
	}
	if len(entries) == 0 {
		return 0, nil
	}

	if !remover.LookPath("pi") {
		remover.Printf("gentle-ai: cannot retire displaced Pi packages: pi is not on PATH")
		return 0, nil
	}

	failed := false
	for _, entry := range entries {
		remover.Printf("gentle-ai: pi remove %s", entry)
		if !remover.Remove(entry) {
			failed = true
			remover.Printf("gentle-ai: failed to retire displaced package: %s", entry)
		}
	}

	if failed {
		remover.Printf("gentle-ai: some displaced Pi packages could not be retired")
	}

	return 0, nil
}
