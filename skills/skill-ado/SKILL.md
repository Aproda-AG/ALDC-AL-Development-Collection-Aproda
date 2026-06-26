---
name: skill-ado
description: "Azure DevOps work item conventions for ALDC plans. Use when a requirement, bug, or task originates from an ADO work item — governs req_name derivation, folder naming, URL construction, and diagnosis/plan file headers."
---

# Skill: ADO Work Item Naming & Linking

## Purpose

Map an ADO work item to a `plans/` folder name, file name, and document header — consistent across Triage, Architect, and Conductor.

## When to Load

A requirement, bug, or task is identified by an ADO work item ID (e.g. "Bug 36370", "Task 12345", "US 99001").

## Pattern 1 — req_name = `{type}-{id}`

Lowercase type + numeric ID. No descriptive slug — the title lives in ADO.

| ADO Type | Input | `{req_name}` |
|----------|-------|--------------|
| Bug | Bug 36370 | `bug-36370` |
| Task | Task 12345 | `task-12345` |
| User Story | US 99001 | `us-99001` |
| Feature | Feature 5500 | `feature-5500` |

Folder + files: `.github/plans/bug-36370/bug-36370-diagnosis.md` (Triage), `…-plan.md` / `….spec.md` / `….architecture.md` (Conductor/Architect).

State the derived `{req_name}` and let the user correct it before creating files. If only an ID is given, ask once for the type.

## Pattern 2 — ADO header (below the title, before other metadata)

```markdown
**ADO**: [Bug 36370](https://dev.azure.com/{org}/{project}/_workitems/edit/36370)
**Type**: Bug
```

URL: `https://dev.azure.com/{org}/{project}/_workitems/edit/{id}`. Org = `alphasol`. Project from `aldc.yaml → ado.project`, else ask once and persist to `plans/memory.md → Project Info`. URL-encode spaces (`Gustav%20Gerig%20AG`).

## Constraints

- Naming + linking only — no ADO API fetch.
- Free-text requirements (no ADO ID) → normal kebab-case derivation per agent rules; do not load this skill.
