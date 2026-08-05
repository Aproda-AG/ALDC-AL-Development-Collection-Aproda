---
name: skill-aproda-ado
description: "Azure DevOps work item conventions for ALDC plans. Use when a requirement, bug, or task originates from an ADO work item — governs req_name derivation, folder naming, URL construction, and diagnosis/plan file headers."
---

# Skill: ADO Work Item Naming & Linking

## Purpose

Map an ADO work item to a `plans/` folder name, file name, and document header — consistent across Triage, Architect, and Conductor.

## When to Load

A requirement, bug, or task is identified by an ADO work item ID (e.g. "Bug 36370", "Task 12345", "US 99001").

## Pattern 1 — req_name = `{type}-{id}-{short-name}`

Lowercase type + numeric ID + kebab-case short name derived from the work item title. The short name makes folder names human-readable at a glance.

**Short name rules:**
- Derive from the work item title: lowercase, kebab-case, max 4–5 meaningful words.
- Strip articles, conjunctions, and noise words (a, an, the, and, or, for, …).
- If the title is not yet known, ask once, then derive; never leave it empty.

| ADO Type | Input + Title | `{req_name}` |
|----------|---------------|----------------|
| Bug | Bug 36370 "Sales posting fails with VAT" | `bug-36370-sales-posting-vat` |
| Task | Task 12345 "Add approval workflow" | `task-12345-add-approval-workflow` |
| User Story | US 99001 "Customer price list import" | `us-99001-customer-price-list-import` |
| Feature | Feature 5500 "Warehouse Management" | `feature-5500-warehouse-management` |

Folder + files: `.github/plans/bug-36370-sales-posting-vat/bug-36370-sales-posting-vat-diagnosis.md` (Triage), `…-plan.md` / `….spec.md` / `….architecture.md` (Conductor/Architect).

**Before creating any files:** read `memory.md` → `## Active Requirements`. If any row has Status `in progress` or `review`, mention it briefly (e.g. "ℹ️ `{req}` is currently `{status}`") and continue — no hard stop.
State the derived `{req_name}` and let the user correct it before creating files. If only an ID is given, ask once for type and title.

## Pattern 2 — ADO header (below the title, before other metadata)

```markdown
**ADO**: [Bug 36370](https://dev.azure.com/{org}/{project}/_workitems/edit/36370)
**Type**: Bug
```

URL: `https://dev.azure.com/{org}/{project}/_workitems/edit/{id}`. Org = `alphasol`. Project from `aldc.yaml → ado.project`, else ask once and persist to `plans/memory.md → Project Info`. URL-encode spaces (`Gustav%20Gerig%20AG`).

## Constraints

- Naming + linking only — no ADO API fetch.
- Free-text requirements (no ADO ID) → normal kebab-case derivation per agent rules; do not load this skill.
