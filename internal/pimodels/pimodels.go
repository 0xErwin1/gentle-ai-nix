// Package pimodels writes Pi's own custom-provider overlay,
// .pi/agent/models.json, from the declared providers.pi.modelProviders.
// The overlay is the supported way to register a provider without an
// extension (Pi's docs/models.md): the two Pi runtimes that pass
// --no-extensions -- notably the review host relay's locked-down reviewer
// subprocess -- never see a provider registered by a Pi package, so the
// file has to exist for their model to resolve.
//
// The module renders file content, never provider knowledge: Providers
// carries Pi's provider objects exactly as written and this package only
// marshals them. No model id, context window, cost or compat value is
// invented or defaulted here, the same rule lib/models.nix states for the
// flake itself.
package pimodels

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// ValidationError marks a problem with the declared spec itself, as opposed
// to an I/O failure while writing the result. gentle-nix pi models uses
// this distinction to exit 2 for the former and 1 for the latter, the same
// split gentle-nix pi routing already makes.
type ValidationError struct{ msg string }

func (e ValidationError) Error() string { return e.msg }

func validationErrorf(format string, args ...any) error {
	return ValidationError{msg: fmt.Sprintf(format, args...)}
}

// Spec is gentle-nix pi models' own input contract: Providers is the
// decoded top-level object of Pi's models.json overlay, keyed by provider
// id, with every provider field kept exactly as written. The object-of-
// objects shape is also the structural validation: a provider whose value
// is not an object fails at decode time, before this package is called.
type Spec struct {
	Providers map[string]map[string]any `json:"providers,omitempty"`
}

// Validate checks the declared overlay's structure only: a provider id must
// be non-empty, and a provider must be an object. Pi's own provider/model
// schema is deliberately not restated here -- Pi validates the file at
// startup and reports the field it dislikes, and a second copy of that
// schema in this repo would be one machine's answer frozen into everyone's,
// the same frozen-knowledge mistake lib/models.nix warns about. Nothing in
// this package can validate a provider's meaning; a wrong field reaches Pi
// and surfaces as its startup diagnostic.
func Validate(spec Spec) error {
	for id, provider := range spec.Providers {
		if id == "" {
			return validationErrorf("providers: a provider id must be non-empty")
		}
		if provider == nil {
			return validationErrorf("providers.%s: a provider must be an object, not null", id)
		}
	}
	return nil
}

// WriteTree writes the declared providers into tree as Pi's custom-provider
// overlay, .pi/agent/models.json, mirroring the pirouting writer's shape
// (MarshalIndent with two spaces, a trailing newline, 0o644). It writes
// nothing when no provider is declared, so an omitted option can never
// clobber a live file.
func WriteTree(tree string, spec Spec) error {
	if err := Validate(spec); err != nil {
		return err
	}
	if len(spec.Providers) == 0 {
		return nil
	}

	agentDir := filepath.Join(tree, ".pi", "agent")
	if err := os.MkdirAll(agentDir, 0o755); err != nil {
		return fmt.Errorf("create Pi agent directory: %w", err)
	}

	encoded, err := json.MarshalIndent(struct {
		Providers map[string]map[string]any `json:"providers"`
	}{spec.Providers}, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal Pi custom providers: %w", err)
	}
	if err := os.WriteFile(filepath.Join(agentDir, "models.json"), append(encoded, '\n'), 0o644); err != nil {
		return fmt.Errorf("write Pi custom providers: %w", err)
	}
	return nil
}
