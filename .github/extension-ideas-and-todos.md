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
