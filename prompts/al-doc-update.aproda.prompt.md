---
agent: agent
model: Claude Sonnet 4.5
description: "Aproda: refresh the durable per-module documentation (technical reference EN + user handbook de-CH) under .github/documentation/<Module>/ from the current code + spec. Run at the delivery boundary."
tools: [vscode/memory, read/readFile, edit, search, 'al-symbols-mcp/*', todo]
---

# AL Module Documentation Update (Aproda)

> Net-new Aproda workflow (`.aproda.` infix, D-4 — no Upstream conflict). Rationale: `decisions.aproda.md` **D-13 / D-14**.

Refresh the **durable, per-module** documentation so it reflects the module's **target state** after a delivery. This workflow does **not** invent behaviour — it derives docs from the code and the (now-stable) spec.

## When to run

- **At the delivery boundary** (D-10): the requirement is accepted, the `{req}.spec.md` is frozen, all `uat-issues.md` issues are `DONE`. This is the moment the docs should mirror the final state.
- Invoked by `@al-developer` (LOW) before PR hand-off, and by `@al-conductor` (MEDIUM/HIGH) at plan completion — both at the delivery point, alongside `al-pr-prepare`.
- May also be run **manually** anytime: `@workspace use al-doc-update` for a module.

## Inputs

- **Module** name (e.g. `AuditTrail`). If omitted, infer the affected module(s) from the changed objects / the active plan folder and confirm with the user.
- **Scope** — `both` (default) / `reference` (technical only) / `handbook` (user only).

## Target files

```
.github/documentation/<Module>/
├── <Module>.reference.md        ← technical module reference (English)
└── <Module>.Handbuch.de-CH.md   ← user handbook (de-CH, Aproda standard)
```

If the folder/files do not exist, create them; otherwise **update in place** (these are living documents — preserve structure, refresh content).

## Execution steps

### 1. Gather sources (do not duplicate them)

- Read the module's `.al` files under `SRC/<Module>/` (or wherever the objects live) to learn the **current** object set, lifecycle, and behaviour.
- Read the module's `SKILL.md` (`.github/skills/<module-skill>/SKILL.md`) if one exists — it is the AI-canonical contract.
- Read the requirement's frozen `{req}.spec.md` and the `uat-issues.md` (for the accepted target behaviour).
- Read any `Doc/<Module>-OpenItems.md` for on-hold / not-yet-active features.

> **Source-of-truth rule (D-13)**: the reference is a *lean overview*. It **links** to the `.al` files + SKILL as the source of truth and must **never mirror object IDs, file paths, or exact signatures** (they drift). Capture purpose, scope, lifecycle, building blocks, extension pointer, translations note.

### 2. Update `<Module>.reference.md` (English) — when scope ≠ handbook

Sections: Purpose · Audited/Covered scope · Core building blocks · Lifecycle · State model · Adding a new sub-module (pointer to SKILL) · Translations. Mark it a **living document**. Reflect the **target state**; if related UAT issues are still `TODO`, it may describe soll-state ahead of code — that is acceptable for a reference (note it).

### 3. Update `<Module>.Handbuch.de-CH.md` (de-CH) — when scope ≠ reference

User-facing, **de-CH**, task-oriented: what the feature does, the core workflow (step-by-step), how to do common tasks, where to find logs/results, FAQ. No object IDs, no code. Keep on-hold features out of the user flow (mention only as a footnote if relevant).

### 4. Verify & report

- Run `get_errors` on the two markdown files (link integrity) if applicable.
- Report which files were created/updated and what changed. Do **not** commit — that is `al-pr-prepare`'s job.

## Guardrails

- Persisted artifacts language rule: `reference.md` = **English**; `Handbuch.de-CH.md` = **de-CH**. Never mix.
- Do not edit `.al` code, the spec, or the `uat-issues.md` from this workflow — it is documentation-only.
- Do not duplicate IDs/paths/signatures (D-13). Link instead.
