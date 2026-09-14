## Codex host contract

Resolve .agents/skills/aldc paths below against the installed ALDC skill root
if using plugin discovery instead of local bootstrap. Workflow names below are
reference files in commands/, not automatically registered slash commands.

Use only tools actually exposed by this session. Model, reasoning, sandbox and
approval settings inherit from the parent; this profile grants no extra tools.
Role write scopes below are behavioral, not filesystem sandboxes. Discover MCP
providers before using their examples; none are installed by this package.
If delegation is unavailable, report that the affected independent review or
Conductor workflow is pending; do not certify self-review as independent review.


## BC29 / AL18 terminal contract

Before selecting AL tools, dependency changes or validation evidence, read
[the terminal-host contract](../skills/skill-migrate/references/cli-al-tools.md)
and apply its role boundaries. It qualifies older tool examples below without
changing the workflow or human gates. Missing capabilities limit the affected
validation; they do not imply success or require an unrelated upgrade.

Resolve input placeholders from the user request or ask for missing required values;
`${input:...}` is template notation, not an automatically expanded CLI variable.


# Workflow: Generate Agent Task Integration Code

You are an expert AL developer. Generate production-ready AL code for agent task integration.

The skill `bc-agent-task-patterns` provides the 8 integration patterns and SDK codeunit reference. Use it as your knowledge base.

## Step 1 — Gather Context

Before generating code, determine:

1. **Agent name and prefix**: Read from `app.json` or ask the developer
2. **Object ID range**: Check existing objects in `app/` to find the next available IDs
3. **Which pattern(s)**: Ask the developer or infer from their request:
   - "I need a Public API" → Pattern A
   - "Add a button to send work to the agent" → Pattern B (calls A)
   - "Trigger agent on posting/releasing" → Pattern C (calls A)
   - "Agent needs to process files" → Pattern D (combine with A/B/C)
   - "Continue an existing task" → Pattern E
   - "Run code only in agent context" → Pattern G/H
4. **ExternalId format**: Convention is `{PREFIX}-{No.}` (e.g., `LEAD-001`, `SO-1001`)
5. **Target page/table**: Which page extension or event subscriber is needed?

## Step 2 — Generate Code

For each requested pattern:

1. **Search the codebase** for existing agent objects (Setup table, Public API, enums) to reuse
2. **Generate the AL objects** following the pattern from the skill, substituting:
   - `{Agent}` → actual agent name/prefix
   - `{id}` → actual object IDs
   - Record names, field names, enum values → actual project values
3. **Place files** in the correct project structure folder:
   - Public API + Impl → `app/Example/`
   - Page extensions → `app/Example/`
   - Session events → `app/Setup/TaskExecution/`
4. **Verify** generated code references correct enum values and codeunit names from the project

## Step 3 — Validate

- [ ] All generated codeunits compile (correct parameter types, return types)
- [ ] Public API has `Access = Public`, Implementation has `Access = Internal`
- [ ] Event-driven task creation uses `[TryFunction]`
- [ ] Business conditions checked BEFORE task creation
- [ ] Failures logged via `Session.LogMessage`
- [ ] ExternalId follows the agreed format convention
- [ ] Page extensions use `AgentSetup.OpenAgentLookup()` for agent selection

🛑 **STOP — Review generated code with the developer.**
