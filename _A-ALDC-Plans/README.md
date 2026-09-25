# `_A-ALDC-Plans/` — working folders for fork-level initiatives

> **Fork-only.** This tree is in `tools/aproda-sync/aproda-sync.json → neverTouch`, so nothing here ever
> reaches a consuming project. It holds work **on the framework**, not work *with* it.

## The two plan roots — don't mix them

| Folder | Contents |
|---|---|
| `.github/plans/` | Requirement sets for the **ALDC tool itself** (spec / architecture / test-plan per `aldc.yaml → contracts`) |
| **`_A-ALDC-Plans/`** | Working folders for **proposed extensions to the tool** — one per `E-xxx` backlog entry |

## Where the `E-xxx` IDs come from

The IDs are issued and tracked in the backlog:

**[`../.github/extension-ideas-and-todos.md`](../.github/extension-ideas-and-todos.md)** — the status
board (`Proposed` → `Approved` → `In Progress` → `Implemented` / `Rejected`), one section per idea with
problem, proposal, constraints, acceptance criteria and approval gate.

A folder here is created **after** the backlog entry moves past `Proposed`. Folder name:
`E-xxx-{kebab-case-name}`, matching the backlog ID.

## Orientation

Read **[`00-ALDC-Aproda-Ground-Truth.md`](00-ALDC-Aproda-Ground-Truth.md)** first when working on the
framework — durable repo facts, where authoritative knowledge lives, and what is currently in flight.
It is deliberately not a content store; it points at the real sources.

## Current folders

| Folder | Backlog ID | State |
|---|---|---|
| [`E-005-translation-ai-workflow/`](E-005-translation-ai-workflow/) | E-005 | In progress — stages 0/1 implemented, 2/3 design-only |
| [`E-006-layer-visibility-and-version-consistency/`](E-006-layer-visibility-and-version-consistency/) | E-006 | Blocks 1–3 done; Block 4 (BCQuality part 1) next |
| [`E-007-azure-cli-skill/`](E-007-azure-cli-skill/) | E-007 | V2 (MCP-first hybrid) in progress |
| [`dev-day-2026-09-16/`](dev-day-2026-09-16/) | — | Session notes, not a backlog item |

> Keep this table current when adding a folder — it is the only index of this tree.
