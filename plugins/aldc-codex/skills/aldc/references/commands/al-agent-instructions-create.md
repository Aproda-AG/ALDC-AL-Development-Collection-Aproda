## Codex host contract

Resolve .agents/skills/aldc paths below against the installed ALDC skill root
if using plugin discovery instead of local bootstrap. Workflow names below are
reference files in commands/, not automatically registered slash commands.
Packaged domain entrypoints named SKILL.md in the source are stored as GUIDE.md
under references/skills/. This alias applies only when reading packaged guidance;
new discoverable skills must still be created with SKILL.md.

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


# Workflow: Generate Agent Instructions

You are an expert in Business Central agent instruction authoring.

## Output Modes

- **Designer Mode**: Text ready to paste into Agent Designer wizard
- **SDK Mode**: Text stored in `.resources/Instructions/InstructionsV1.txt`, loaded via `NavApp.GetResourceAsText()` returning `SecretText`, applied via `Agent.SetInstructions(UserSecurityId, InstructionsText)`

## Framework: Responsibilities → Guidelines → Instructions

```
**RESPONSIBILITY**: {One-line accountability}

**GUIDELINES**:
- ALWAYS {mandatory rule}
- DO NOT {prohibited action}
- MEMORIZE {values to retain across steps}

**INSTRUCTIONS**:

## Task: {Primary Task Name}

1. Navigate to "{Page Name}"
   a. Search for {value} in "{Field Name}"
   b. Read "{Field Name}" → **MEMORIZE** {description}: {example}
2. If {condition}: {action}
   a. **DO NOT** {prohibited action}
   b. Request user intervention with: {details}
3. Set field "{Field Name}" to {value}
4. Invoke action "{Action Name}"
5. Add comment: "{Agent Name} - [Date] | {outcome format}"
```

## Keywords Reference

| Keyword                     | Purpose                   |
| --------------------------- | ------------------------- |
| `Navigate to`               | Page navigation           |
| `Search for`                | List filtering            |
| `Set field`                 | Value assignment          |
| `Invoke action`             | Action execution          |
| `MEMORIZE`                  | Retain value across steps |
| `DO NOT` (bold)             | Prohibit critical action  |
| `ALWAYS` (bold)             | Mandate critical action   |
| `Request user intervention` | Human-in-the-loop         |

## Validation Checklist

- [ ] Page names match agent profile and page customizations exactly
- [ ] Field names match page fields exactly
- [ ] MEMORIZE placed BEFORE value is needed
- [ ] All critical actions (posting, sending, releasing) gated by user intervention
- [ ] Written in English — safeguards optimized for English
- [ ] Environment-agnostic (no hardcoded company names, URLs, etc.)
- [ ] Concise — shorter often performs better
- [ ] Stored in `.resources/Instructions/InstructionsV1.txt` (SDK mode)
