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


# Build and Deploy AL Extension

Your goal is to build (compile + package) the AL extension for the `${input:DeploymentType}` environment and to guide its deployment.

> **What runs where.** In the Codex harness you compile and package with the **AL command-line tool (ALTool / `al`)** via `shell`. No deployment or test runner is bundled — the existing handoff is VS Code (`AL: Publish` / `AL: Run Tests`) or AL-Go/CI pipeline steps. So this command builds the `.app` and then hands off the deploy with a clear, approved checklist.

## Select Deployment Strategy
Inspect the project (Read `app.json`, Search/Search, **al-symbols-mcp** for dependencies) and select the appropriate deployment strategy.
Ask and confirm with the user before proceeding.

## Deployment Types

Based on the deployment type, use the appropriate strategy:

### Development Environment
1. **Build**: `shell: al compile` (single project) or `al workspace compile` (multi-project) to produce the `.app`
2. **Review**: Present compiler results for human approval
3. **Deploy**: hand off to VS Code `AL: Publish with RAD` for rapid iteration (requires approval)
4. **Verify**: Read the compiler output for any errors

### Testing Environment
1. **Build**: `shell: al compile` with full validation (read all warnings/errors)
2. **Package**: the `.app` is produced by `al compile`
3. **Review**: Present package details for human approval
4. **Deploy**: hand off to VS Code `AL: Publish` (debugging enabled) or the CI pipeline (requires approval)
5. **Test**: ask the human to run VS Code `AL: Run Tests` (or the CI test runner) and confirm all unit tests pass

### Production Environment
1. **Build**: `shell: al compile` with strict validation
2. **Package**: take the release `.app` produced by `al compile`
3. **Validation**: Verify package integrity and dependencies (`app.json` + **al-symbols-mcp** `al_packages`)
4. **Documentation**: Generate deployment checklist and present for review
5. **Human Gate**: **MANDATORY** - Manual approval required before any production action
   - **Note**: Automated deployment to production is intentionally disabled as safeguard
   - All production changes require explicit human authorization, run through the AL-Go/CI release pipeline or VS Code

### Existing Package Deployment
- When deploying a pre-built `.app`, hand off to VS Code `AL: Publish` (or the CI pipeline) — this plugin does not configure a deployment provider
- Verify package compatibility with the target environment first

### Full Dependency Package
- For packages bundling all dependencies (offline/isolated installs), drive this through the AL-Go/CI packaging pipeline
- `al compile` produces the extension `.app`; dependency bundling is a pipeline concern

## Error Handling

Monitor the output for:
- Compilation errors
- Dependency conflicts
- Publishing failures
- Permission issues

## Post-Deployment Verification

After deployment:
1. Verify extension appears in Extension Management
2. Check all functionality works as expected
3. Validate permissions are correctly applied
4. Monitor for any runtime errors
