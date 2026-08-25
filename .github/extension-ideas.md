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
