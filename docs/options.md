## programs\.gentle-ai\.enable



Whether to enable Gentle AI\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```



## programs\.gentle-ai\.package



Gentle AI package\. It both renders the configuration and is installed,
so what runs matches what was rendered\.



*Type:*
package



*Default:*

```nix
gentle-ai-nix.packages.${pkgs.system}.gentle-ai
```



## programs\.gentle-ai\.backgroundSubagents\.opencode

OpenCode background subagent policy\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.backgroundSubagents\.pi



Pi background subagent policy\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.communityTools



The community tools to configure, keyed by Gentle AI’s own id\. The names are
deliberately not enumerated here: Gentle AI rejects one it does not know
rather than ignoring it, so a community tool it gains works the day it ships\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.communityTools\.\<name>\.enable



Whether to enable the ‹name› community tool\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```



## programs\.gentle-ai\.components



The components to configure, keyed by Gentle AI’s own id\. The names are
deliberately not enumerated here: Gentle AI rejects one it does not know
rather than ignoring it, so a component it gains works the day it ships\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.components\.\<name>\.enable



Whether to enable the ‹name› component\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```



## programs\.gentle-ai\.document



The desired-state document these options produced\.



*Type:*
attribute set of anything *(read only)*



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.engramPackage



Engram package, installed when the engram component is enabled\. The
component is what configures the clients to use it; this only puts the
binary on PATH, which Nix does rather than letting Gentle AI fetch it\.



*Type:*
null or package



*Default:*

```nix
gentle-ai-nix.packages.${pkgs.system}.engram
```



## programs\.gentle-ai\.extensions



Provider-specific configuration keyed by provider, for a provider not
declared through ` providers `\. Prefer ` providers.<name>.settings `\.



*Type:*
attribute set of anything



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.extraFiles



Files layered onto the rendered tree, replacing whatever Gentle AI put
at the same path\. This is how you add a skill of your own or override a
generated one without forking Gentle AI\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  ".config/opencode/skills/house-style/SKILL.md".source = ./house-style.md;
  ".claude/agents/gentle-apply.md".text = "---\nname: gentle-apply\n---\nMy own prompt.\n";
}

```



## programs\.gentle-ai\.extraFiles\.\<name>\.mode



Whether this content replaces what Gentle AI rendered at the path or
is appended after it\. Appending is how a section of your own
survives in a file Gentle AI regenerates\.



*Type:*
one of “replace”, “append”



*Default:*

```nix
"replace"
```



## programs\.gentle-ai\.extraFiles\.\<name>\.source



File or directory to copy\. Set exactly one of source or text\.



*Type:*
null or absolute path



*Default:*

```nix
null
```



## programs\.gentle-ai\.extraFiles\.\<name>\.target



Path relative to the home directory\.



*Type:*
string



*Default:*

```nix
"‹name›"
```



## programs\.gentle-ai\.extraFiles\.\<name>\.text



Inline content\. Set exactly one of text or source\.



*Type:*
null or strings concatenated with “\\n”



*Default:*

```nix
null
```



## programs\.gentle-ai\.install\.channel



Release channel\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.install\.scope



Install scope\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.mcpServers



MCP servers, keyed by name\. A server a component already configures does
not need an entry here; this is for the ones only you know about\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.mcpServers\.\<name>\.enable



Whether the client should start this server\.



*Type:*
null or boolean



*Default:*

```nix
null
```



## programs\.gentle-ai\.mcpServers\.\<name>\.args



Arguments for the command\.



*Type:*
list of string



*Default:*

```nix
[ ]
```



## programs\.gentle-ai\.mcpServers\.\<name>\.command



Executable for a local server\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.mcpServers\.\<name>\.env



Environment for the command\.



*Type:*
attribute set of string



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.mcpServers\.\<name>\.url



Endpoint for a remote server\. Mutually exclusive with command\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.models\.claudePhases



Claude phase assignments carrying both a model and an effort\.



*Type:*
attribute set of anything



*Default:*

```nix
{ }
```



*Example:*

```nix
{ sdd-apply = { model = "opus"; effort = "high"; }; }
```



## programs\.gentle-ai\.models\.codexCarril



Codex carril to model id\.



*Type:*
attribute set of string



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.models\.codexOrchestrator



Model and effort for the Codex main session\.



*Type:*
null or (attribute set of anything)



*Default:*

```nix
null
```



## programs\.gentle-ai\.models\.codexPhases



Codex phase to model id\.



*Type:*
attribute set of string



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.openCodePlugins



The OpenCode plugins to configure, keyed by Gentle AI’s own id\. The names are
deliberately not enumerated here: Gentle AI rejects one it does not know
rather than ignoring it, so a OpenCode plugin it gains works the day it ships\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



## programs\.gentle-ai\.openCodePlugins\.\<name>\.enable



Whether to enable the ‹name› OpenCode plugin\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```



## programs\.gentle-ai\.overrideRendered



Arbitrary post-processing of the rendered tree, applied after
` extraFiles `\. The derivation holds ` tree/ ` and ` manifest.json `\.



*Type:*
function that evaluates to a(n) package



*Default:*

```nix
lib.id
```



## programs\.gentle-ai\.permissions\.allow



Rules allowed on top of the shipped guardrails\.



*Type:*
list of string



*Default:*

```nix
[ ]
```



## programs\.gentle-ai\.permissions\.ask



Rules that prompt on top of the shipped guardrails\.



*Type:*
list of string



*Default:*

```nix
[ ]
```



## programs\.gentle-ai\.permissions\.deny



Rules denied on top of the shipped guardrails\.



*Type:*
list of string



*Default:*

```nix
[ ]
```



## programs\.gentle-ai\.persona



Persona applied to the generated guidance\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.preset



Preset the installation starts from\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.providers



Clients to configure, keyed by Gentle AI’s own provider id\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  opencode.enable = true;
  claude-code = {
    enable = true;
    skills = [ "cognitive-doc-design" ];
    settings.theme = "system";
  };
}

```



## programs\.gentle-ai\.providers\.\<name>\.enable



Whether to enable the ‹name› client\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```



## programs\.gentle-ai\.providers\.\<name>\.modelPreset



One of Gentle AI’s own model profiles for this client, by name\.
Profiles are per client because subscriptions are: the cheap tier on
one and the expensive tier on another is a thing you can want, and a
single global profile cannot say it\.

Naming the profile rather than restating the models it resolves to
is what keeps it the profile Gentle AI recommends today\. An
assignment set explicitly in ` models ` still wins over it\.

Not every client offers profiles; one that does not is reported
rather than accepted and ignored\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"economy"
```



## programs\.gentle-ai\.providers\.\<name>\.models



Model assignments in this provider’s own vocabulary, keyed by phase\.
Providers express models differently — an alias, a reasoning effort,
a provider/model pair — so values are passed through as written\.



*Type:*
attribute set of anything



*Default:*

```nix
{ }
```



*Example:*

```nix
{ sdd-apply = "opus"; }
```



## programs\.gentle-ai\.providers\.\<name>\.profileStrategy



How profiles are materialised for this client: generated alongside
the default agents, or left to an external profile manager that
keeps one active at a time\. Omitted, Gentle AI detects it\.

Only OpenCode expresses this today\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"generated-multi"
```



## programs\.gentle-ai\.providers\.\<name>\.profiles



Named SDD profiles for this client, switchable at runtime\. Each one
generates its own orchestrator and phase agents alongside the
default set, so a task can run on cheap models without reconfiguring
anything\.

Only OpenCode expresses these today\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  cheap.orchestrator = {
    provider = "anthropic";
    model = "claude-haiku";
  };
}

```



## programs\.gentle-ai\.providers\.\<name>\.profiles\.\<name>\.orchestrator



Model this profile’s orchestrator runs on\.



*Type:*
null or (submodule)



*Default:*

```nix
null
```



## programs\.gentle-ai\.providers\.\<name>\.profiles\.\<name>\.orchestrator\.effort



Reasoning effort, where the provider expresses one\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.providers\.\<name>\.profiles\.\<name>\.orchestrator\.model



Model id within the provider\.



*Type:*
string



## programs\.gentle-ai\.providers\.\<name>\.profiles\.\<name>\.orchestrator\.provider



Model provider id\.



*Type:*
string



## programs\.gentle-ai\.providers\.\<name>\.profiles\.\<name>\.phases



Model per SDD phase within this profile\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  sdd-apply = {
    provider = "anthropic";
    model = "claude-sonnet-5";
  };
}

```



## programs\.gentle-ai\.providers\.\<name>\.profiles\.\<name>\.phases\.\<name>\.effort



Reasoning effort, where the provider expresses one\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.providers\.\<name>\.profiles\.\<name>\.phases\.\<name>\.model



Model id within the provider\.



*Type:*
string



## programs\.gentle-ai\.providers\.\<name>\.profiles\.\<name>\.phases\.\<name>\.provider



Model provider id\.



*Type:*
string



## programs\.gentle-ai\.providers\.\<name>\.settings



Provider-specific configuration the neutral contract does not model\.
It is merged verbatim into this provider’s settings and no other’s\.



*Type:*
attribute set of anything



*Default:*

```nix
{ }
```



*Example:*

```nix
{ share = "disabled"; }
```



## programs\.gentle-ai\.providers\.\<name>\.skills



Skills for this provider only\. Null takes the globally enabled
skills, so a provider is named here only when it must differ\.



*Type:*
null or (list of string)



*Default:*

```nix
null
```



## programs\.gentle-ai\.rendered



The rendered tree, after extraFiles and overrideRendered\.



*Type:*
package *(read only)*



## programs\.gentle-ai\.review\.mode



Global review kill switch\. Left unset, the machine’s own setting stands:
this is a user-owned choice, so declaring it is opting into managing it\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.roles



Logical agent roles, keyed by id\. References name ids, never rendered names\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  orchestrator = {
    renderedName = "my-orchestrator";
    mode = "primary";
    references = [ "apply" ];
  };
  apply = {
    renderedName = "my-apply";
    mode = "subagent";
  };
}

```



## programs\.gentle-ai\.roles\.\<name>\.description



One-line description shown by the client\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.roles\.\<name>\.hidden



Whether the client hides this role from its agent list\.



*Type:*
null or boolean



*Default:*

```nix
null
```



## programs\.gentle-ai\.roles\.\<name>\.mode



Whether the operator addresses this role directly or another role
delegates to it\.



*Type:*
null or one of “primary”, “subagent”



*Default:*

```nix
null
```



## programs\.gentle-ai\.roles\.\<name>\.model



Model this role runs on\.



*Type:*
null or (submodule)



*Default:*

```nix
null
```



## programs\.gentle-ai\.roles\.\<name>\.model\.effort



Reasoning effort, where the provider expresses one\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.roles\.\<name>\.model\.model



Model id within the provider\.



*Type:*
string



## programs\.gentle-ai\.roles\.\<name>\.model\.provider



Model provider id\.



*Type:*
string



## programs\.gentle-ai\.roles\.\<name>\.prompt



System prompt for this role\.



*Type:*
null or strings concatenated with “\\n”



*Default:*

```nix
null
```



## programs\.gentle-ai\.roles\.\<name>\.references



Ids of the roles this one delegates to\.



*Type:*
list of string



*Default:*

```nix
[ ]
```



## programs\.gentle-ai\.roles\.\<name>\.renderedName



Name this role is rendered as\. Null renders it under its id\. Other
roles always reference the id, so changing this is one edit\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.roles\.\<name>\.tools



Tools this role may use\. Null leaves the client’s default\.



*Type:*
null or (list of string)



*Default:*

```nix
null
```



## programs\.gentle-ai\.schemaVersion



Version of the Gentle AI configuration schema this document is written
against\. Gentle AI rejects a version it cannot interpret, so pinning it
turns an incompatible upgrade into a build failure rather than a silent
reinterpretation\.



*Type:*
string



*Default:*

```nix
"v1"
```



## programs\.gentle-ai\.sdd\.mode



SDD orchestrator mode\.



*Type:*
null or string



*Default:*

```nix
null
```



## programs\.gentle-ai\.sdd\.strictTdd



Whether SDD phases enforce strict TDD\.



*Type:*
boolean



*Default:*

```nix
false
```



## programs\.gentle-ai\.settings



Raw ` selection ` fields merged last, overriding everything the grouped
options produced\. This is the escape hatch for a contract field newer
than this module\.



*Type:*
attribute set of anything



*Default:*

```nix
{ }
```



*Example:*

```nix
{ someNewContractField = true; }
```



## programs\.gentle-ai\.skills



Skills, keyed by Gentle AI’s own id\. Naming none installs every skill
Gentle AI ships, so this is only for narrowing that: an entry set to
false excludes one skill and leaves the rest, and any entry set to true
narrows the installation to the ones named\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{ go-testing.enable = false; }
```



## programs\.gentle-ai\.skills\.\<name>\.enable



Whether to enable the ‹name› skill\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```


