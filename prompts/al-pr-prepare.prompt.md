---
agent: agent
model: GPT-5.6 Terra (copilot)
description: 'Prepare a clean, documented pull request draft for AL features or fixes with summary, testing notes, and checklist.'
tools: [vscode/getProjectSetupInfo, vscode/installExtension, vscode/newWorkspace, vscode/runCommand, vscode/vscodeAPI, vscode/extensions, execute/runNotebookCell, execute/getTerminalOutput, execute/createAndRunTask, execute/runInTerminal, execute/runTests, read/getNotebookSummary, read/problems, read/readFile, read/readNotebookCellOutput, read/terminalSelection, read/terminalLastCommand, agent, edit, search, web, 'github/*', 'github/*', 'github/*', 'microsoft-learn/microsoft_docs_fetch', microsoft-learn/microsoft_docs_search, 'al-symbols-mcp/*', ms-dynamics-smb.al/al_downloadsymbols, ms-dynamics-smb.al/al_symbolsearch, ms-dynamics-smb.al/al_symbolrelations, SShadowSdk.al-lsp-for-agents/bclsp_goToDefinition, SShadowSdk.al-lsp-for-agents/bclsp_hover, SShadowSdk.al-lsp-for-agents/bclsp_findReferences, SShadowSdk.al-lsp-for-agents/bclsp_prepareCallHierarchy, SShadowSdk.al-lsp-for-agents/bclsp_incomingCalls, SShadowSdk.al-lsp-for-agents/bclsp_outgoingCalls, SShadowSdk.al-lsp-for-agents/bclsp_codeLens, SShadowSdk.al-lsp-for-agents/bclsp_codeQualityDiagnostics, SShadowSdk.al-lsp-for-agents/bclsp_documentSymbols, SShadowSdk.al-lsp-for-agents/bclsp_renameSymbol, todo]

---
# AL Pull Request Preparation

Your goal is to prepare a **pull request draft** for the branch `${input:Branch}` summarizing all modifications, test evidence, and validation steps. At the delivery boundary, update module documentation before creating the PR, then execute the approved ADO delivery actions and finally close the requirement in `memory.md`.

## Pre-PR Review

**Before generating PR draft document:**

1. **Review code changes** - Present summary of all modifications
2. **Security check** - Confirm no sensitive data in commits
3. **Quality validation** - Verify tests pass, build succeeds, and, when translations changed, recorded `skill-translate` evidence shows the approval gate passed with zero open review units and strict XLIFF validation has zero issues; do not run the XLIFF tool here
4. **Delivery readiness** - Confirm the requirement is accepted and no HITL issues remain open

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

### 3. Aproda: Documentation Update (D-13 / D-14)

Before creating a PR, refresh the durable per-module documentation:

```
@workspace use al-doc-update
```

This updates `.github/documentation/<Module>/`:
- `<Module>.reference.md` — technical reference (English)
- `<Module>.Handbuch.de-CH.md` — user handbook (de-CH)

Run once per affected module at the delivery boundary (all HITL issues DONE, spec frozen). Commit and push all delivery changes, including these documentation updates, before creating an ADO PR. Never commit `/reports/pr-draft.md`.

### 4. Generate PR Draft

Create `/reports/pr-draft.md` with the delivery preview in this compact structure:

```markdown
## PR Title Proposal
[Concise imperative title]

## PR Description

### Summary
[1-2 sentences: what was implemented/fixed and why]

### References
- Req: `{req_name}` · Spec: `.github/plans/{req_name}/{req_name}.spec.md`
- #[work-item] *(ADO) or* AB#[work-item] *(GitHub + Azure Boards)*

### DB Changes
> none
<!-- or: TableExt 50xxx — field "XYZ" added (no upgrade codeunit required) -->

### Test Result
- Deploy-Run-Verify: ✅ / ❌
- XLIFF (`de-CH`, when translations changed): approval gate ✅/❌, open review units: 0 / [count] / n/a; strict validation: 0 issues / ❌ / n/a
- Open HITL issues: none / [link to {req_name}-hitl-validation-issues.md]

### Deployment
> no special steps
<!-- or: list steps beyond standard AL-Go release here -->

## ADO Work Item Completion Comment Proposal
<!-- ADO-hosted repositories only; substitute <PR_ID> only after the PR exists. -->
✅ Gelöst via PR #<PR_ID>: <Kurztitel>

Lösung: <1–2 Sätze, was/wie>
Getestet: <Deploy-Run-Verify ✅/❌ + 1 Zeile, oder Link auf hitl-validation-issues>
Setup/Datenupgrade: keine | <1–2 Bulletpoints>
Zu beachten: keine | <1 Zeile Caveat/Follow-up>
```

**Rules:**
- Omit empty sections — only include sections with real content.
- DB Changes: only fill in if new tables, new fields, or changed keys are present.
- Deployment: only fill in if steps beyond the standard AL-Go release are required.
- Do NOT list AL objects — changed files in GH/ADO already show this.
- The ADO completion-comment proposal applies only to ADO-hosted repositories. Fill `Setup/Datenupgrade` and `Zu beachten` with `keine` when no content applies.

**Primary:** `/reports/pr-draft.md`
**Format:** Compact markdown — only sections with real content

## Success Criteria

- ✅ PR draft file created under `/reports/pr-draft.md`
- ✅ "Summary" filled in with 1-2 sentences
- ✅ Work item reference present (`#123` for ADO, `AB#123` for GitHub + Azure Boards)
- ✅ DB Changes explicitly stated (or explicitly "none")
- ✅ Deploy-Run-Verify result documented
- ✅ XLIFF approval-gate result, open review count, and strict-validation evidence documented when translations changed; this workflow only consumes evidence and never runs the XLIFF tool
- ✅ PR title and, for ADO-hosted repositories, ADO completion-comment proposals included

## 🔒 Aproda: ADO Delivery Gate (ADO-hosted repositories only)

> Applies only when the remote origin was auto-detected as ADO-hosted (§2, `#123` pattern). For GitHub-hosted repos (with or without an `AB#123` Azure Boards link), `/reports/pr-draft.md` remains a manual-submission draft — skip this section and go straight to the Completion Gate below.

Load **`skill-aproda-ado`** (SRP-safe execution, see its `SKILL.md`). Before either ADO write, show the delivery preview from `/reports/pr-draft.md`:

- proposed PR title and complete PR description
- proposed work-item completion comment, with the literal `<PR_ID>` placeholder
- source branch, target branch, and linked work item

Obtain **one explicit approval** authorizing exactly these two writes: create (or reuse) this PR, then post this exact completion comment with `<PR_ID>` replaced only by the returned PR ID. Any changed text, branch, or work item requires a new explicit confirmation.

1. Call `Create-AdoPullRequest.ps1` with the title proposal, `-DescriptionFile` pointing at `/reports/pr-draft.md` (the script extracts its `PR Description` section), `-SourceBranch ${input:Branch}`, `-TargetBranch` (ask once if not obvious from the repo default), and the linked `-WorkItemId`.
2. On `created: true` **or** `existing-open-pull-request`, replace only `<PR_ID>` in the approved completion-comment proposal with the returned ID and call `Update-AdoWorkItem.ps1 -Comment`. On PR creation failure, stop and report — do not retry silently or post a comment.
3. On completion-comment failure, stop and report. Do not move the requirement to Completed; a retry needs a fresh preview and approval.

After the PR and comment both succeed, delete `/reports/pr-draft.md` — it must not be committed to the repo. No `.gitignore` entry as a safety net (deliberately omitted); the explicit delete is the only measure.

## 🔒 Completion Gate (before moving the req to Completed)

- [ ] PR created (`Create-AdoPullRequest.ps1` → `created:true` or `existing-open-pull-request`) — ADO-hosted repos only; for GitHub-hosted repos, the PR is submitted manually from `/reports/pr-draft.md`
- [ ] `/reports/pr-draft.md` deleted — **only if the PR was actually created** in this run (ADO-hosted repos); if PR creation failed, was never attempted, or the repo is GitHub-hosted, the file is expected to still exist and its presence is not a gate failure
- [ ] ADO completion comment posted — ADO-hosted repos only
- [ ] `al-doc-update` run and its changes committed and pushed before PR creation
- [ ] XLIFF approval gate passed with zero open review units and strict-validation evidence shows zero issues when translations changed; this workflow does not run the tool
- [ ] No open `TODO` issues remain in `{req_name}-hitl-validation-issues.md` (if the file exists)

**🚨 HARD GATE — this is a verification step, not a checklist to narrate.** A documented
gate that is only described in prose is not a guarantee it was executed — treat each item
as unproven until actively checked:

1. You MUST run `git status --short` (or the workspace-equivalent) and confirm `memory.md`
   does **not** appear as modified/untracked before claiming the move is done.
2. `/reports/pr-draft.md` deletion is conditional, not absolute — check which case applies
   before judging it:
   - PR creation in this run reported `created:true`/`existing-open-pull-request`
     (ADO-hosted) → You MUST confirm `/reports/pr-draft.md` no longer exists on disk. Do
     not infer this from having *intended* to delete it earlier in the conversation.
   - PR creation failed, was never attempted, or the repo is GitHub-hosted → the file is
     **expected** to still exist (kept for retry or manual submission); its presence is
     **not** a gate failure, and it must not be deleted before a successful PR creation.
3. **Verify actual completeness, not just this workflow's own mechanics:** before the
   move, read (if present) `.github/plans/{req_name}/{req_name}-hitl-validation-issues.md`
   and check its Status-Board table. If any row still shows `Status: TODO`, the
   requirement is **not** done — refuse the move, tell the user which issue(s) remain open,
   instead of silently marking it "Completed". If the file doesn't exist, this item counts
   as satisfied (no HITL feedback ever occurred).
4. Your final response in this workflow MUST render all applicable checklist items above as an
   explicit ✅/❌ list with the verification evidence (e.g. `git status` output,
   file-existence check, Status-Board scan) — not a restatement of the checklist text. A
   skipped or unverified item is reported as ❌, not silently omitted.
5. Proceeding to the `memory.md` move without having performed 1–3 is a process violation,
   even if the underlying PR/comment mutations succeeded.

Only once all applicable items are satisfied and verified (or explicitly skipped by the
user) → proceed to the `memory.md` move below.

## Aproda: memory.md Completion Update

Only after the Completion Gate passes, update `.github/plans/memory.md`:

1. **Move the req row** from `## Active Requirements` to `## Completed Requirements`:
   - Add row: `| {req_name} | {YYYY-MM-DD} | No |`
   - Remove the row from Active Requirements table
2. **Append Inter-Session Context** entry (date, who = al-pr-prepare, what = PR created, branch, PR number if known).
3. **Commit and push this file change** — an uncommitted or unpushed `memory.md` edit is
   equivalent to not having made it. After the commit, run `git status --short` and confirm
   that `memory.md` no longer appears as modified/untracked; when an upstream branch exists,
   verify that the delivery commit has been pushed.

> This is the only step that signals delivery acceptance to all agents. Without it, the req stays in `review` forever.

## Next Steps

**For final validation:**
```
@AL Development Conductor   # TDD orchestration with review subagent
@AL Implementation Specialist   # Direct testing and fixes
```

---

**PR draft ready for GitHub submission (or created directly in ADO — see above).**
