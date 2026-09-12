package roles

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestValidateRejectsUnknownReference(t *testing.T) {
	spec := Spec{
		Agents: []string{"claude-code"},
		Roles: map[string]Role{
			"orchestrator": {References: []string{"apply"}},
		},
	}

	err := Validate(spec)
	if err == nil {
		t.Fatal("Validate() error = nil, want a reference error")
	}
	if !strings.Contains(err.Error(), "apply") {
		t.Errorf("Validate() error = %v, want it to name the missing reference", err)
	}
	if _, ok := err.(ValidationError); !ok {
		t.Errorf("Validate() error type = %T, want ValidationError", err)
	}
}

func TestValidateRejectsUnsupportedMode(t *testing.T) {
	spec := Spec{
		Agents: []string{"claude-code"},
		Roles: map[string]Role{
			"orchestrator": {Mode: "observer"},
		},
	}

	if err := Validate(spec); err == nil {
		t.Fatal("Validate() error = nil, want an unsupported mode error")
	}
}

func TestValidateRejectsAnAdapterThatCannotExpressRoles(t *testing.T) {
	spec := Spec{
		Agents: []string{"claude-code", "gemini-cli"},
		Roles: map[string]Role{
			"orchestrator": {},
		},
	}

	err := Validate(spec)
	if err == nil {
		t.Fatal("Validate() error = nil, want gemini-cli refused")
	}
	if !strings.Contains(err.Error(), "gemini-cli") {
		t.Errorf("Validate() error = %v, want it to name gemini-cli", err)
	}
}

func TestValidateAcceptsAnUnsupportedAdapterWithoutRoles(t *testing.T) {
	spec := Spec{Agents: []string{"gemini-cli"}}

	if err := Validate(spec); err != nil {
		t.Errorf("Validate() error = %v, want nil: no role was declared", err)
	}
}

func TestWriteTreeEmptySpecIsANoOp(t *testing.T) {
	tree := t.TempDir()

	if err := WriteTree(tree, Spec{Agents: []string{"claude-code", "opencode"}}); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	entries, err := os.ReadDir(tree)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Errorf("WriteTree() with no roles wrote %v, want nothing", entries)
	}
}

func TestWriteTreeRendersFrontmatterForFileAdapters(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"claude-code", "cursor", "kimi", "kiro-ide"},
		Roles: map[string]Role{
			"orchestrator": {
				RenderedName: "my-orchestrator",
				References:   []string{"worker"},
				Description:  "coordinates",
				Prompt:       "you coordinate",
				Tools:        []string{"Read", "Edit"},
				Model:        &ModelAssignment{Provider: "anthropic", Model: "claude-opus-5", Effort: "high"},
			},
			"worker": {RenderedName: "my-worker"},
		},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	for adapter, dir := range map[string]string{
		"claude-code": ".claude/agents",
		"cursor":      ".cursor/agents",
		"kimi":        ".kimi/agents",
		"kiro-ide":    ".kiro/agents",
	} {
		path := filepath.Join(tree, filepath.FromSlash(dir), "my-orchestrator.md")
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("%s: read rendered orchestrator: %v", adapter, err)
		}

		want := "---\n" +
			"name: my-orchestrator\n" +
			"description: coordinates\n" +
			"model: claude-opus-5\n" +
			"effort: high\n" +
			"tools: Read, Edit\n" +
			"references: my-worker\n" +
			"---\n" +
			"you coordinate\n"
		if string(data) != want {
			t.Errorf("%s orchestrator document = %q, want %q", adapter, data, want)
		}
	}
}

func TestWriteTreeOmitsWhatTheRoleDidNotDeclare(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"claude-code"},
		Roles:  map[string]Role{"worker": {}},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	data, err := os.ReadFile(filepath.Join(tree, ".claude", "agents", "worker.md"))
	if err != nil {
		t.Fatalf("read rendered worker: %v", err)
	}

	want := "---\nname: worker\n---\n"
	if string(data) != want {
		t.Errorf("worker document = %q, want %q", data, want)
	}
}

func TestWriteTreeRenderedNameIsUsedInsteadOfID(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"claude-code"},
		Roles: map[string]Role{
			"orchestrator": {RenderedName: "gentle-orchestrator", References: []string{"apply"}},
			"apply":        {RenderedName: "gentle-implementer"},
		},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	document, err := os.ReadFile(filepath.Join(tree, ".claude", "agents", "gentle-orchestrator.md"))
	if err != nil {
		t.Fatalf("read rendered orchestrator: %v", err)
	}
	if !strings.Contains(string(document), "references: gentle-implementer") {
		t.Errorf("rendered orchestrator = %s, want the reference resolved to the rendered name", document)
	}
	if _, err := os.Stat(filepath.Join(tree, ".claude", "agents", "apply.md")); !os.IsNotExist(err) {
		t.Errorf("a role without a rendered name override must not also render under its id")
	}
}

func TestWriteTreeRendersTheWholeDeclaredRoleForOpenCode(t *testing.T) {
	tree := t.TempDir()
	hidden := true
	spec := Spec{
		Agents: []string{"opencode"},
		Roles: map[string]Role{
			"orchestrator": {
				RenderedName: "my-orchestrator",
				References:   []string{"worker"},
				Description:  "coordinates",
				Prompt:       "you coordinate",
				Tools:        []string{"Read", "Edit"},
				Mode:         "primary",
				Model:        &ModelAssignment{Provider: "anthropic", Model: "claude-opus-5", Effort: "high"},
			},
			"worker": {RenderedName: "my-worker", Mode: "subagent", Hidden: &hidden},
		},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	raw, err := os.ReadFile(filepath.Join(tree, ".config", "opencode", "opencode.json"))
	if err != nil {
		t.Fatalf("read rendered opencode settings: %v", err)
	}

	var settings struct {
		Agent map[string]map[string]any `json:"agent"`
	}
	if err := json.Unmarshal(raw, &settings); err != nil {
		t.Fatalf("decode rendered settings: %v", err)
	}

	orchestrator := settings.Agent["my-orchestrator"]
	for field, want := range map[string]any{
		"description": "coordinates",
		"prompt":      "you coordinate",
		"mode":        "primary",
		"model":       "anthropic/claude-opus-5",
		"variant":     "high",
	} {
		if orchestrator[field] != want {
			t.Errorf("orchestrator %s = %v, want %v", field, orchestrator[field], want)
		}
	}

	tools, _ := orchestrator["tools"].(map[string]any)
	if tools["read"] != true || tools["edit"] != true || tools["*"] != false {
		t.Errorf("orchestrator tools = %v, want the declared tools enabled and the rest denied", tools)
	}

	permission, _ := orchestrator["permission"].(map[string]any)
	task, _ := permission["task"].(map[string]any)
	if task["my-worker"] != "allow" || task["*"] != "deny" {
		t.Errorf("orchestrator delegation = %v, want only the referenced role allowed", task)
	}

	if settings.Agent["my-worker"]["hidden"] != true {
		t.Errorf("worker hidden = %v, want true", settings.Agent["my-worker"]["hidden"])
	}
}

func TestWriteTreeOpenCodeOmitsWhatTheRoleDidNotDeclare(t *testing.T) {
	tree := t.TempDir()
	spec := Spec{
		Agents: []string{"opencode"},
		Roles:  map[string]Role{"worker": {RenderedName: "my-worker"}},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	raw, err := os.ReadFile(filepath.Join(tree, ".config", "opencode", "opencode.json"))
	if err != nil {
		t.Fatalf("read rendered opencode settings: %v", err)
	}
	var settings struct {
		Agent map[string]map[string]any `json:"agent"`
	}
	if err := json.Unmarshal(raw, &settings); err != nil {
		t.Fatalf("decode rendered settings: %v", err)
	}
	if len(settings.Agent["my-worker"]) != 0 {
		t.Errorf("rendered agent = %v, want nothing the document did not declare", settings.Agent["my-worker"])
	}
}

func TestWriteTreeOpenCodeReplacesRatherThanMergesToolsAndDelegation(t *testing.T) {
	tree := t.TempDir()
	settingsPath := filepath.Join(tree, ".config", "opencode", "opencode.json")
	if err := os.MkdirAll(filepath.Dir(settingsPath), 0o755); err != nil {
		t.Fatal(err)
	}
	existing := `{"agent":{"my-worker":{"tools":{"bash":true},"permission":{"task":{"other":"allow"}}}}}`
	if err := os.WriteFile(settingsPath, []byte(existing), 0o644); err != nil {
		t.Fatal(err)
	}

	spec := Spec{
		Agents: []string{"opencode"},
		Roles: map[string]Role{
			"orchestrator": {RenderedName: "my-worker", References: []string{"helper"}, Tools: []string{"Read"}},
			"helper":       {RenderedName: "helper"},
		},
	}

	if err := WriteTree(tree, spec); err != nil {
		t.Fatalf("WriteTree() error = %v", err)
	}

	raw, err := os.ReadFile(settingsPath)
	if err != nil {
		t.Fatal(err)
	}
	var settings struct {
		Agent map[string]map[string]any `json:"agent"`
	}
	if err := json.Unmarshal(raw, &settings); err != nil {
		t.Fatalf("decode merged settings: %v", err)
	}

	tools, _ := settings.Agent["my-worker"]["tools"].(map[string]any)
	if _, stale := tools["bash"]; stale {
		t.Errorf("tools = %v, want the stale entry replaced rather than merged", tools)
	}
	if tools["read"] != true {
		t.Errorf("tools = %v, want the declared tool enabled", tools)
	}

	permission, _ := settings.Agent["my-worker"]["permission"].(map[string]any)
	task, _ := permission["task"].(map[string]any)
	if _, stale := task["other"]; stale {
		t.Errorf("delegation = %v, want the stale entry replaced rather than merged", task)
	}
	if task["helper"] != "allow" {
		t.Errorf("delegation = %v, want the declared reference allowed", task)
	}
}
