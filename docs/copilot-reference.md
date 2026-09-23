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

### Tier 1 — reach for first (official, `ms-dynamics-smb.al` / `sshadowsdk.al-lsp-for-agents`)

| Tool | When |
|------|------|
| `al_symbolsearch` | Fields, events, methods from `.alpackages` (Base App, libraries) — no source needed |
| `al_symbolrelations` | Dependencies between objects |
| `al_getdiagnostics` | Compilation errors/diagnostics — note the exact name (no `_` between `get` and `diagnostics`; a typo variant `al_get_diagnostics` has previously crept into agent frontmatter and silently resolves to nothing) |
| `al_downloadsymbols` | Refresh symbols after a dependency version bump |
| `bclsp_goToDefinition` / `bclsp_findReferences` | Semantic navigation across workspace source (requires `sshadowsdk.al-lsp-for-agents`, a separate community extension not bundled with the AL Language extension) |

### Tier 2 — situational

`bclsp_documentSymbols`, `bclsp_hover`, `bclsp_prepareCallHierarchy` + `bclsp_incomingCalls`/`bclsp_outgoingCalls`, `bclsp_renameSymbol`, `al_build`/`al_debug`/`al_publish` (deferred — call `tool_search` first if unavailable).

**Key distinction**: `al_symbolsearch` reads compiled `.alpackages` (no source needed); `bclsp_*` reads your own open workspace source. They complement, not replace, each other.

### `al-symbols-mcp` — optional community MCP server

A third-party Rust MCP server (B0tis, MIT, small/lightly-maintained project) exposing 8 tools: `al_search_objects`, `al_get_object_definition`, `al_find_references`, `al_search_object_members`, `al_get_object_summary`, `al_get_free_id`, `al_packages`, `al_cli_status`. Its unique value over the Tier 1/2 tools above is `al_get_free_id` (next free object ID from `app.json` `idRanges`) and `al_cli_status`/`al_packages` for runtime packages (e.g. Base Application) that lack an embedded `SymbolReference.json`.

- **Not bundled** — requires manual install + `mcp.json` config per machine; the binary can be blocked by AppLocker/SRP policies.
- **Not guaranteed available** — several agent files reference `'al-symbols-mcp/*'` in their `tools:` frontmatter, but the server may not be registered in a given session/workspace. When absent, the wildcard silently resolves to zero tools — no error, just missing capability. Verify it actually shows up in the available/deferred tools list before relying on it in a new environment.

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
