# Copilot Reference (ALDC Core v1.2)

> Human-facing reference material moved out of `.github/copilot-instructions.md` to keep that file
> a lean, always-on entrypoint. Nothing here is operational routing logic — it is examples,
> workspace layout, links, and troubleshooting. The entrypoint links here under "Further Reference".

## Code Generation Examples

### Table with Validation

```al
// Ask Copilot: "Create a table for customer addresses with validation"
table 50100 "Customer Address"
{
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Customer No."; Code[20])
        {
            TableRelation = Customer."No.";
            NotBlank = true;
        }
        field(2; "Address Line 1"; Text[100])
        {
            Caption = 'Address Line 1';
        }
        field(3; "City"; Text[50])
        {
            Caption = 'City';
        }
        field(4; "Post Code"; Code[20])
        {
            Caption = 'Post Code';
        }
    }

    keys
    {
        key(PK; "Customer No.")
        {
            Clustered = true;
        }
    }
}
```

**Auto-applied** (for `CustomerAddress.Table.al`): al-guidelines, al-code-style, al-naming-conventions

### Event Subscriber

```al
// Ask: "Create event subscriber for customer validation"
[EventSubscriber(ObjectType::Table, Database::Customer, 'OnBeforeValidateEvent', 'Email', false, false)]
local procedure ValidateCustomerEmail(var Rec: Record Customer)
begin
    if Rec.Email <> '' then
        if not Rec.Email.Contains('@') then
            Error('Email must contain @');
end;
```

**Auto-applied** (for `SalesEventHandler.Codeunit.al`): al-guidelines, al-code-style, al-naming-conventions, al-performance, al-error-handling, al-events

## Best Practices for Copilot Interaction

### 1. Start with Context

- **Good**: "I'm building a customer approval workflow that needs to send notifications"
- **Avoid**: "Create a workflow"

### 2. Use the Right Tool

- **Strategic questions** → Use agents (`@AL Architecture & Design Specialist`, `@AL Implementation Specialist`, etc.)
- **Tactical tasks** → Use workflows (`@workspace use al-build`)
- **Normal coding** → Let auto-applied instructions work in background

### 3. Trust the Auto-Instructions

The instruction files work automatically:
- You don't need to ask for proper naming (al-naming-conventions handles it)
- You don't need to request performance optimization (al-performance suggests it)
- Error handling patterns apply automatically (al-error-handling activates)

### 4. Review Generated Code

Always review Copilot suggestions:
- Verify compliance with project guidelines
- Test in sandbox environment
- Check security implications
- Validate performance impact

## Workspace Structure

🟦 marks Aproda `.aproda.` layer additions (see [`../readme.aproda.md`](../readme.aproda.md) + [`../decisions.aproda.md`](../decisions.aproda.md)). Counts reflect the actual repo, not a fixed spec number — re-check `agents/`, `skills/`, `prompts/`, `instructions/` directly if in doubt.

```
ALDC-Core/ (Aproda-extended)
├── instructions/                          # 10 auto-applied files (8 core + 2 🟦) — see instructions/index.md
│   ├── al-guidelines.instructions.md .. al-testing.instructions.md      # 7 core (**/*.al or **/*.Codeunit.al scoped)
│   ├── al-agent-toolkit.instructions.md                                 # Agent SDK codeunits (**/*Factory|Metadata|TaskExecution|Setup.Codeunit.al)
│   ├── hitl-validation.aproda.instructions.md                       🟦  # HITL Validation lifecycle (**/*.al)
│   └── aproda-aldc-steward.aproda.instructions.md                   🟦  # Guardrail on the Aproda layer itself
├── agents/                                # 11 agent files (7 user-facing + 4 internal subagents)
│   ├── al-architect.agent.md / al-developer.agent.md / al-conductor.agent.md / al-presales.agent.md
│   ├── al-triage.agent.md / dredd.agent.md / al-agent-builder.agent.md          # user-facing
│   ├── al-planning-subagent.agent.md / al-implement-subagent.agent.md / al-review-subagent.agent.md   # internal (user-invocable: false)
│   └── al-translate-subagent.aproda.agent.md                                                       🟦  # internal
├── skills/                                # 21 composable knowledge modules
│   ├── skill-api / skill-copilot / skill-debug / skill-events / skill-estimation / skill-migrate /
│   │   skill-pages / skill-performance / skill-permissions / skill-testing / skill-translate / skill-manifest   # 12 core, loaded on demand
│   ├── skill-agent-instructions / skill-agent-task-patterns / skill-agent-toolkit                                # 3 BC Agents Pack
│   ├── skill-contribution-assistant                                                                              # 1 meta (skill authoring)
│   └── skill-aproda-ado / skill-aproda-aldc / skill-aproda-aldc-release /
│       skill-aproda-deploy-run-verify / skill-aproda-fkh                                                     🟦  # 5 Aproda
├── prompts/                               # 12 workflows
│   ├── al-spec.create / al-build / al-pr-prepare / al-memory.create / al-context.create / al-initialize   # 6 core
│   ├── al-agent.create / al-agent.task / al-agent.instructions / al-agent.test / al-agent.build-instructions  # 5 BC Agents Pack
│   └── al-doc-update.aproda.prompt.md                                                                      🟦
├── readme.aproda.md / decisions.aproda.md / site-profile.aproda.md / aldc.yaml                             🟦  # Aproda layer docs + config (repo root)
├── docs/
│   ├── framework/
│   │   └── ALDC-Core-Spec-v1.2.md         # Normative specification
│   ├── copilot-reference.md               # This file
│   └── templates/                         # Immutable templates
├── .github/plans/                         # Requirement sets & memory
├── src/                                   # Your AL code
└── app.json
```

## AL/BC Tools & MCP Servers

Reference for developers configuring agents/tools — which tool comes from which extension, and known environment caveats.

**Who this is for, and when.** This section is the maintained inventory for both humans and agents. Read it
before claiming a tool does not exist, before adding a tool name to an agent's `tools:` frontmatter, and
before choosing between a native chat tool and a terminal command. Agent files link here on purpose and
deliberately do **not** restate its contents — a tool fact restated per agent is a tool fact that will
drift (that is exactly how the `al_build` and `al_symbolrelations` errors below survived).

> **"Exists on the platform" is not "granted to this agent".** These are different facts and they drift
> apart when each agent file restates them in prose. This section is the single source for *what exists*;
> an agent's `tools:` frontmatter is the single source for *what it may call*. When an agent cannot do
> something, the honest wording is "not granted here", never "there is no such tool".
>
> **Terminal execution is a first-class route, not a fallback.** `execute` / `runInTerminal` is the
> sanctioned way to reach any AL/BC CLI capability (`altool`, `alc.exe`, `az`, PowerShell). A native
> chat tool is preferred when it is granted *and* unambiguous; where it is ambiguous — see the `scope`
> note below — the terminal route is the more deterministic choice, not the inferior one.
> `skill-aproda-deploy-run-verify` → *Build route* is the worked example.

### Tier 1 — reach for first (official, `ms-dynamics-smb.al` / `SShadowSdk.al-lsp-for-agents`)

| Tool | When |
|------|------|
| `al_symbolsearch` | Fields, events, methods from `.alpackages` (Base App, libraries) — no source needed |
| `bclsp_symbolRelations` | Dependencies between objects. **Not** `al_symbolrelations` — that name never existed (corrected 2026-09-29, see below) |
| `al_getdiagnostics` | Compilation errors/diagnostics — note the exact name (no `_` between `get` and `diagnostics`; a typo variant `al_get_diagnostics` has previously crept into agent frontmatter and silently resolves to nothing) |
| `al_downloadsymbols` | Refresh symbols after a dependency version bump |
| `bclsp_goToDefinition` / `bclsp_findReferences` | Semantic navigation across workspace source (requires `SShadowSdk.al-lsp-for-agents`, a separate community extension not bundled with the AL Language extension) |

### Tier 2 — situational

`bclsp_documentSymbols`, `bclsp_hover`, `bclsp_prepareCallHierarchy` + `bclsp_incomingCalls`/`bclsp_outgoingCalls`, `bclsp_renameSymbol`, `al_build`/`al_debug`/`al_publish` (deferred — call `tool_search` first if unavailable).

**Key distinction**: `al_symbolsearch` reads compiled `.alpackages` (no source needed); `bclsp_*` reads your own open workspace source. They complement, not replace, each other.

### The official tool set — what the AL Language extension actually ships

Per [AI agent tools overview](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/al-agent-tools/al-agent-tools-overview) (AL Language extension 17.0+). Verified against this list on 2026-09-29.

| Surface | Tools | Callable from VS Code Copilot Chat |
|---|---|---|
| **VS Code Language Model Tools** | `al_build`, `al_publish`, `al_downloadsymbols`, `al_symbolsearch`, `al_getdiagnostics`, `al_debug`, `al_setbreakpoint`, `al_snapshotdebugging` | ✅ yes |
| **AL MCP Server** (`altool launchmcpserver`) | the same set plus `al_compile` (validate without producing an `.app`), `al_getpackagedependencies`, `al_addproject`, `al_auth_login`/`al_auth_logout` — and `al_build` there takes an explicit **`projectPath`** | ❌ no — a standalone process for external agent hosts (CI, Copilot CLI, Claude Code) |
| **AL LSP Server** (`altool launchlspserver`) | hover, definitions, cross-project references, rename, formatting … over stdio JSON-RPC | ❌ no named chat tool — this is *not* what `bclsp_*` is; the community extension is what fills that gap in this surface |
| **`altool workspace compile/create/map`** | dependency-ordered multi-project build, scaffolding, Mermaid dependency graph | terminal route (see the principle above) |
| **Profiling / snapshot MCP proxies** | CPU profiling and snapshot debugging against a live BC session | preview (BC 2026 wave 2), not mandated |

**`al_symbolrelations` does not exist.** It appears in neither the official list above nor the live tool
registry of a running session; the real capability is `bclsp_symbolRelations` from the community LSP
extension. The wrong name sat in the `tools:` frontmatter of six agents and seven prompts and resolved
silently to nothing — the same failure class as the `al_get_diagnostics` typo. Corrected 2026-09-29.

### `al_build` scope — why a project path matters

`scope: "current"` builds *the active project*; `scope: "all"` builds the entire workspace in dependency
order. The VS Code variant has **no project-path parameter** (the MCP variant does), so in a multi-root
workspace (`.github` + `Base` + `Test`) `current` depends on which editor is focused — and `.github` is
not an AL project at all, having no `app.json`. What exactly "active project" means is **not defined in
the documentation**; that it follows the open editor is observation, not a cited fact.

Two measured consequences (2026-09-29, Straub Medical AG Base):

- `scope: "all"` compiles Test against the **fresh** Base — it resolves through workspace project
  references, not through the package cache.
- It does **not** refresh `Test/.alpackages`: the Base `.app` there was six days old afterwards, and an
  `alc.exe /project:"Test"` build — which knows only the cache — failed with
  `AL0132 … does not contain a definition for 'AldcBuildScopeAllProbe'`.

So a green `al_build scope:"all"` proves the sources compile; it proves nothing about what a later
publish or cache-based build will see.

### `al-symbols-mcp` — optional community MCP server

A third-party Rust MCP server (B0tis, MIT, small/lightly-maintained project) exposing 8 tools: `al_search_objects`, `al_get_object_definition`, `al_find_references`, `al_search_object_members`, `al_get_object_summary`, `al_get_free_id`, `al_packages`, `al_cli_status`. Its unique value over the Tier 1/2 tools above is `al_get_free_id` (next free object ID from `app.json` `idRanges`) and `al_cli_status`/`al_packages` for runtime packages (e.g. Base Application) that lack an embedded `SymbolReference.json`.

- **Not bundled** — requires manual install + `mcp.json` config per machine; the binary can be blocked by AppLocker/SRP policies.
- **Not guaranteed available** — several agent files reference `'al-symbols-mcp/*'` in their `tools:` frontmatter, but the server may not be registered in a given session/workspace. When absent, the wildcard silently resolves to zero tools — no error, just missing capability. Verify it actually shows up in the available/deferred tools list before relying on it in a new environment.

### Tool publisher casing is case-sensitive (verified 2026-09-29)

An agent's `tools:` frontmatter reference (`<publisher>.<extension>/<toolName>`) is resolved by an
**exact-case string match** against the installed extension's ID — not case-insensitive, unlike most
VS Code extension-ID handling. `sshadowsdk.al-lsp-for-agents/bclsp_findReferences` (lowercase publisher)
silently resolved to zero tools; only `SShadowSdk.al-lsp-for-agents/bclsp_findReferences` (matching the
Marketplace publisher's exact casing) worked, and only after a VS Code reload re-read the changed
frontmatter. Same failure class as the wildcard case above: no error, just a missing tool. Canonical
casing for this repo's publishers: `SShadowSdk.al-lsp-for-agents`, `aprodaag.aproda-aldc`,
`ms-dynamics-smb.al`. `tools/aldc-validate`'s `agentToolCasing` rule is the automated backstop — it
flags any case-variant of these publishers found in `agents/*.agent.md`.

### Zero-install MCP servers (URL only in `mcp.json`)

- `microsoft-learn` — `https://learn.microsoft.com/api/mcp` — official MS docs, no auth
- `context7` — `https://mcp.context7.com/mcp` — library/framework docs, no auth (API key optional for higher rate limits)

## BC Agents Pack (Extension)

For agent development with AI Development Toolkit:
- @AL Agent Builder — standalone agent builder (7-phase workflow)
- skill-agent-task-patterns — 8 SDK integration patterns
- skill-agent-instructions — instruction authoring framework
- skill-agent-toolkit — Agent SDK/Designer architecture, interfaces, naming conventions
- al-agent.create / al-agent.task / al-agent.instructions / al-agent.test / al-agent.build-instructions — workflows

Integrated mode: @AL Architecture & Design Specialist + al-spec.create + @AL Development Conductor
(architect loads skill-agent-task-patterns for design decisions)

### Meta skill (framework authoring, not BC-agent-specific)

- skill-contribution-assistant — guides authoring a new community skill for the AL Copilot Skill Collection; not part of the delivery pipeline, invoked on request when someone wants to contribute a skill.

## Reference Documentation

### Microsoft Documentation

- [AL Language Reference](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-reference-overview)
- [Business Central Development](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/)
- [VS Code Copilot Guide](https://code.visualstudio.com/docs/copilot)

### This Project's Documentation

- [Instructions Index](../instructions/index.md) — Guide to all instruction files
- [AL Guidelines](../instructions/al-guidelines.instructions.md) — Core principles
- [Skills Creation Guide](skills-creation-guide.md) — How to author new skills

## Troubleshooting Copilot

### No Suggestions Appearing

1. Check Copilot extension is enabled (View → Extensions)
2. Verify file type is `.al`
3. Try reloading VS Code window

### Suggestions Don't Follow Guidelines

1. Ensure instruction files are in correct locations
2. Check file glob patterns in instruction frontmatter
3. Reference specific guidelines: "Follow al-code-style patterns"
