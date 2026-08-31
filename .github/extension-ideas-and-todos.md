# Aproda ALDC Extension Ideas

> Curated fork backlog for proposed Aproda-ALDC enhancements.
>
> This is a fork-only, versioned file. It is intentionally not named with the
> `.aproda.` infix and is not listed in `tools/aproda-sync/aproda-sync.json`.
> The allowlist syncer therefore never distributes it to consuming project
> repositories.
>
> A proposal becomes implementation work only after explicit approval. Then
> create a dedicated `.github/plans/{req_name}/` folder with the required
> specification, architecture, and test plan. Record enduring architectural
> decisions in `decisions.aproda.md` only after adoption.

## Status Board

| ID | Idea | Source | Value | Status |
| --- | --- | --- | --- | --- |
| E-001 | Read-only upstream drift report for Aproda Sync | DSC `sync/upstream-2026-08-24` | High | Proposed |
| E-002 | Official Microsoft Learn MCP endpoint pilot | Dynamic-Technology-Partners `feat/official-microsoft-docs-endpoint` | Medium | Proposed |
| E-003 | Run Auto-Cleanup on task completion (Aproda VS Code extension command) | `todos.md` session note | Medium | Proposed |
| E-004 | Next AL object ID suggestion via a rule-based system + global per-repo assignment | Session note (Aproda) | Medium | Proposed |

## Status Values

- `Proposed`: Captured and awaiting explicit approval.
- `Approved`: Create the corresponding implementation plan.
- `In Progress`: Approved plan is being implemented.
- `Implemented`: Delivered and validated; record a durable decision when applicable.
- `Rejected`: Not pursued; retain the reason below.

## E-001 - Read-Only Upstream Drift Report for Aproda Sync

- **Status:** Proposed
- **Source:** DSC Group branch `sync/upstream-2026-08-24`
- **Problem:** The Aproda layer has an allowlist-based syncer and fleet tools, but no consolidated read-only report that highlights upstream drift, retained Aproda overlays, and workflow conflicts before a pull or fleet update.
- **Proposal:** Add a non-mutating report mode under `tools/aproda-sync/` that compares the fork's upstream baseline, Aproda in-place edits, and source/target layer state.
- **Constraints:** Preserve the existing allowlist overlay model; never auto-merge upstream; never overwrite project or AL-Go files; support `-WhatIf`; remain SRP-safe.
- **Acceptance Criteria:**
  - Generates a readable summary and machine-readable report.
  - Identifies files affected by upstream drift and deliberate Aproda in-place edits.
  - Identifies workflow conflicts without modifying either repository.
  - Works for a single target and can be consumed by fleet-status tooling.
- **Approval Gate:** Approve a dedicated implementation plan before code changes.

## E-002 - Official Microsoft Learn MCP Endpoint Pilot

- **Status:** Proposed
- **Source:** Dynamic-Technology-Partners branch `feat/official-microsoft-docs-endpoint`
- **Problem:** The Claude plugin currently configures `microsoft-docs` through the third-party `@nicholasglazer/microsoft-docs-mcp` npx package.
- **Proposal:** Pilot the official Microsoft Learn MCP HTTP endpoint behind the existing `microsoft-docs` server identifier.
- **Constraints:** Do not change agent prose or server identifiers during the pilot; preserve a documented rollback path to the current stdio configuration; do not modify unrelated MCP servers.
- **Acceptance Criteria:**
  - Documentation search and code-sample retrieval provide equivalent or better results.
  - Claude Code supports the configured HTTP MCP transport in the supported target environment.
  - Connection, proxy, timeout, and fallback behavior are documented.
  - The current stdio configuration can be restored without changes to agent instructions.
- **Approval Gate:** Approve an isolated configuration and validation plan before changing the plugin configuration.

## E-003 - Run Auto-Cleanup on Task Completion

- **Status:** Proposed
- **Source:** `todos.md` session note (Aproda)
- **Problem:** After an implementation task is considered done, uncommitted files are not automatically passed through `al-code-outline`'s code-cleanup command (e.g. "Run Code Cleanup on Uncommited Files in the Active Project"). There is currently no hook that connects "agent marked the implementation as finished" to that cleanup action.
- **Proposal:** Add a manual command to the existing Aproda VS Code extension (e.g. "Aproda: Run Post-Implementation Cleanup") that internally calls `vscode.commands.executeCommand('<al-code-outline-cleanup-command-id>')`. The relevant ALDC agents/prompts recommend running this command to the human at the delivery boundary (same HITL pattern as the other gates in this framework); it is not invoked autonomously.
- **Constraints:** No real "implementation finished" event exists in the VS Code API — chat/agent session completion is not exposed to extensions, so this cannot be a fully automatic trigger; it must remain a human-invoked command, not bound to `onDidSaveTextDocument`/git events. The exact `al-code-outline` command ID must be confirmed via *Preferences: Open Keyboard Shortcuts* → filter "Code Cleanup" → *Copy Command ID*, not guessed. Requires real extension code (TypeScript), since `executeCommand` only exists inside the running Extension Host process and cannot be invoked from PowerShell/tasks/git hooks.
- **Acceptance Criteria:**
  - New command registered in the Aproda VS Code extension that invokes the confirmed `al-code-outline` cleanup command ID.
  - Command activates `al-code-outline` on demand if not already loaded.
  - Relevant agent/prompt guidance recommends running the command at the delivery boundary, without claiming it runs automatically.
  - Documented fallback/rollback: `alOutline.codeActionsOnSave` setting remains available as the zero-code alternative.
- **Approval Gate:** Approve a dedicated implementation plan (including the confirmed command ID) before code changes.

## E-004 - Next AL Object ID Suggestion via a Rule-Based System + Global Per-Repo Assignment

- **Status:** Proposed
- **Source:** Session note (Aproda)
- **Problem:** Multiple developers picking a "next free" AL object ID independently (e.g. from `app.json` `idRanges`) risk colliding IDs when several branches are worked on in parallel; there is no shared, authoritative record of which IDs are already claimed but not yet merged.
- **Proposal:** Add a rule-based "next object ID" suggestion to the Aproda VS Code extension: derive candidate IDs from the project's `idRanges` and existing object IDs in the repo, then check/reserve the suggestion against a **global assignment record scoped per repository** (not per branch/worktree) so concurrent developers don't get the same suggestion. Complements, rather than replaces, the existing `al_get_free_id` MCP tool (personal `al-tools.md` note), which only looks at local `.alpackages` state.
- **Constraints:** Must not write to shared BC objects or `app.json` automatically; suggestion only, human confirms before creating the object. The "global" assignment record must live somewhere reachable by every clone of the repo (e.g. a committed reservation file or a remote lookup) without becoming a merge-conflict-prone shared-write bottleneck. Extension-fork-only tooling classification (like other `tools/aproda-vscode-extension/` capabilities) unless a case is made for syncing it to projects.
- **Acceptance Criteria:**
  - Suggests the next free ID per object type, respecting `idRanges` boundaries and reserved sub-ranges.
  - Cross-checks against a per-repo global record so two developers requesting a suggestion around the same time get different IDs.
  - Never mutates `app.json` or creates objects; output is advisory only.
  - Documented conflict-resolution path if two developers still collide (e.g. simultaneous offline work).
- **Approval Gate:** Approve a dedicated implementation plan (including where the "global per-repo" record lives and how it stays authoritative) before code changes.
