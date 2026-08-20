---
agent: agent
model: GPT-5.6 Terra (copilot)
description: 'Prepare a clean, documented pull request draft for AL features or fixes with summary, testing notes, and checklist.'
tools: [vscode/getProjectSetupInfo, vscode/installExtension, vscode/newWorkspace, vscode/runCommand, vscode/vscodeAPI, vscode/extensions, execute/runNotebookCell, execute/getTerminalOutput, execute/createAndRunTask, execute/runInTerminal, execute/runTests, read/getNotebookSummary, read/problems, read/readFile, read/readNotebookCellOutput, read/terminalSelection, read/terminalLastCommand, agent, edit, search, web, 'github/*', 'github/*', 'github/*', 'microsoft-learn/microsoft_docs_fetch', microsoft-learn/microsoft_docs_search, 'al-symbols-mcp/*', ms-dynamics-smb.al/al_downloadsymbols, ms-dynamics-smb.al/al_symbolsearch, ms-dynamics-smb.al/al_symbolrelations, SShadowSdk.al-lsp-for-agents/bclsp_goToDefinition, SShadowSdk.al-lsp-for-agents/bclsp_hover, SShadowSdk.al-lsp-for-agents/bclsp_findReferences, SShadowSdk.al-lsp-for-agents/bclsp_prepareCallHierarchy, SShadowSdk.al-lsp-for-agents/bclsp_incomingCalls, SShadowSdk.al-lsp-for-agents/bclsp_outgoingCalls, SShadowSdk.al-lsp-for-agents/bclsp_codeLens, SShadowSdk.al-lsp-for-agents/bclsp_codeQualityDiagnostics, SShadowSdk.al-lsp-for-agents/bclsp_documentSymbols, SShadowSdk.al-lsp-for-agents/bclsp_renameSymbol, todo]

---

# AL Pull Request Preparation

Your goal is to prepare a **pull request draft** for the branch `${input:Branch}` summarizing all modifications, test evidence, and validation steps — and to execute all finalization steps at the end of this file (memory.md update, documentation update).

## 🔒 Human Gate: Pre-PR Review

**Before generating PR draft document:**

1. **Review code changes** - Present summary of all modifications
2. **Security check** - Confirm no sensitive data in commits
3. **Quality validation** - Verify tests pass and build succeeds
4. **Human approval required** - Obtain confirmation before creating PR draft

## Process

### 1. Change Analysis

#### Inspect Branch Differences

Use `codebase` to analyze modifications:
```
codebase: Compare ${input:Branch} with main branch
```

Use `githubRepo` to gather context:
```
githubRepo: Get branch information and commit history
```

**Gather:**
- Modified files and line counts
- New files added
- Deleted files
- Commit messages and references
- Related issues or work items

#### Classify Changes

Categorize into:

1. **New Features** - New AL objects, functionality, APIs
2. **Bug Fixes** - Corrections, refactors, optimizations
3. **Tests** - Test codeunits, scenarios, data
4. **Configuration** - app.json, permissions, dependencies
5. **Documentation** - README, comments, API docs

### 2. Extract Metadata

**Find References:**
Scan commit messages and PR description for:
- ADO work item references (`#123`) — used when repo is hosted directly in Azure DevOps
- Azure Boards GitHub App references (`AB#123`) — used when repo is on GitHub linked to Azure Boards
- Requirement names (matching `.github/plans/` subdirectories)

**Pattern matching:**
- #123 (ADO)
- AB#123 (GitHub + Azure Boards)
- req_name

**Auto-detect repo type:** If the remote origin URL contains `dev.azure.com` or `visualstudio.com`, use `#123`. If it contains `github.com`, use `AB#123`.

**Identify Reviewers:**
If `${input:Reviewer}` is specified, include in the draft.

### 3. Generate PR Draft

Create `/reports/pr-draft.md` with this compact structure:

```markdown
## What
[1-2 sentences: what was implemented/fixed and why]

## References
- Req: `{req_name}` · Spec: `.github/plans/{req_name}/{req_name}.spec.md`
- #[work-item] *(ADO) or* AB#[work-item] *(GitHub + Azure Boards)*

## DB Changes
> none
<!-- or: TableExt 50xxx — field "XYZ" added (no upgrade codeunit required) -->

## Test Result
- Deploy-Run-Verify: ✅ / ❌
- Open HITL issues: none / [link to {req_name}-hitl-validation-issues.md]

## Deployment
> no special steps
<!-- or: list steps beyond standard AL-Go release here -->
```

**Rules:**
- Omit empty sections — only include sections with real content.
- DB Changes: only fill in if new tables, new fields, or changed keys are present.
- Deployment: only fill in if steps beyond the standard AL-Go release are required.
- Do NOT list AL objects — changed files in GH/ADO already show this.

**Primary:** `/reports/pr-draft.md`
**Format:** Compact markdown — only sections with real content

## Success Criteria

- ✅ PR draft file created under `/reports/pr-draft.md`
- ✅ "What" filled in with 1-2 sentences
- ✅ Work item reference present (`#123` for ADO, `AB#123` for GitHub + Azure Boards)
- ✅ DB Changes explicitly stated (or explicitly "none")
- ✅ Deploy-Run-Verify result documented

## Aproda: memory.md Completion Update

Before finalizing the PR, update `.github/plans/memory.md`:

1. **Move the req row** from `## Active Requirements` to `## Completed Requirements`:
   - Add row: `| {req_name} | {YYYY-MM-DD} | No |`
   - Remove the row from Active Requirements table
2. **Append Inter-Session Context** entry (date, who = al-pr-prepare, what = PR created, branch, PR number if known).

> This is the only step that signals delivery acceptance to all agents. Without it, the req stays in `review` forever.

## Aproda: Documentation Update (D-13 / D-14)

Before finalizing the PR, refresh the durable per-module documentation:

```
@workspace use al-doc-update
```

This updates `.github/documentation/<Module>/`:
- `<Module>.reference.md` — technical reference (English)
- `<Module>.Handbuch.de-CH.md` — user handbook (de-CH)

Run once per affected module at the delivery boundary (all UAT issues DONE, spec frozen). Mandatory alongside `al-pr-prepare` (D-14).

## Next Steps

**For final validation:**
```
@AL Development Conductor   # TDD orchestration with review subagent
@AL Implementation Specialist   # Direct testing and fixes
```

---

**PR draft ready for GitHub submission.**
