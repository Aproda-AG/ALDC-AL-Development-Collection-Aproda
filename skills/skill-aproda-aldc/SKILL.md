---
name: skill-aproda-aldc
description: "Explain, extend, change, or maintain the Aproda ALDC layer (the .aproda. fork customization on top of ALDC Core). Triggers on: extend/modify/add Aproda skill/agent/instruction/workflow, .aproda. convention, decisions.aproda.md, readme.aproda.md, stacking vs in-place edit, skill-aproda-*, Upstream-touch register, subtree pull/push, 'what is the Aproda layer', onboarding questions about ALDC. Also the knowledge entry point for Aproda infrastructure (site-profile.aproda.md). Aproda custom skill."
---

# Skill: Aproda ALDC — Explain & Extend the Customization Layer

> **Aproda custom skill** — the meta-skill for the Aproda ALDC layer itself. See [`../../readme.aproda.md`](../../readme.aproda.md) (how the layer works) and [`../../decisions.aproda.md`](../../decisions.aproda.md) (why — decisions D-1..D-15).
> **Two audiences:** the **many** who just ask what the layer is / why a rule exists (Explain mode), and the **few** who change it (Extend mode). Extend mode is **guarded** — see [`../../instructions/aproda-aldc-steward.aproda.instructions.md`](../../instructions/aproda-aldc-steward.aproda.instructions.md).

## When to Load

Load this skill when the task is **about the Aproda layer**, not about the BC extension being built:

- **Explain**: "what is the Aproda ALDC layer?", "why is X done this way?", "what does decision D-N mean?", onboarding questions about the framework, where a convention comes from.
- **Extend / change**: add a new Aproda skill/agent/instruction/workflow; change an existing Upstream behaviour; reroute an agent; decide stacking vs in-place edit; record a decision; maintain the Upstream-touch register; plan a `subtree pull`/`push`.
- **Infra lookup**: as the entry point to [`../../site-profile.aproda.md`](../../site-profile.aproda.md) (K: DVD, NST servers, SRP, remote-PS, paste mangling).

> This skill is **not** loaded for normal AL development. Building the BC extension uses the domain skills (`skill-api`, `skill-events`, …) and `skill-aproda-test-loop`. This one is meta — it changes/explains the **framework**, not the product.

## Knowledge map (where the truth lives — link, don't duplicate)

| Question | Source of truth |
|----------|-----------------|
| *How* does the layer extend ALDC? (conventions, naming, no override folder) | [`readme.aproda.md`](../../readme.aproda.md) |
| *Why* is it built this way? (every design decision, D-1..D-15) | [`decisions.aproda.md`](../../decisions.aproda.md) |
| What infra do we run on? (K:, NST servers, SRP, remote-PS) | [`site-profile.aproda.md`](../../site-profile.aproda.md) |
| How is the runtime test-loop standardized? | [`skill-aproda-test-loop`](../skill-aproda-test-loop/SKILL.md) |
| Which Upstream files did we touch in place? | `decisions.aproda.md` → *Upstream edits register* |

This skill **orchestrates and links** those; it never copies their content.

## Explain mode

Answer from the knowledge map above. Core facts to convey when onboarding someone:

- The Aproda layer is a **fork customization on top of ALDC Core**, kept in the **same Upstream folders** — there is **no separate `aproda/` override folder, no agent clones, no `.vscode` discovery registration** (D-3/D-4/D-5).
- **Two mechanisms only** (the TL;DR of `readme.aproda.md`):
  1. **Net-new** things use the **`.aproda.` infix** (files) or **`skill-aproda-*`** prefix (folders) → they never collide → `subtree pull` merges them cleanly.
  2. **Changes to Upstream behaviour** are **in-place edits** of the original file → the next-pull **merge conflict is the deliberate change-log**.
- The `.aproda.` infix keeps the **type suffix intact** (`.prompt.md`, `.instructions.md`, `.agent.md`) so default discovery + `applyTo` keep working with zero registration.
- When the user is **about to change** something, always surface the relevant **decision (D-N)** so they don't unknowingly revert a deliberate choice (this is the steward guardrail's whole purpose).

## Extend / change mode

### Step 0 — Guardrail (mandatory, HITL)
Editing any Aproda-layer file triggers [`aproda-aldc-steward.aproda.instructions.md`](../../instructions/aproda-aldc-steward.aproda.instructions.md). Before changing/relaxing anything:
1. Read `decisions.aproda.md`, identify the **relevant D-entry**.
2. Tell the user which decision the change touches, and whether it **changes/relaxes** a deliberate choice.
3. **Stop and get explicit confirmation** before editing.

### Step 1 — Choose the mechanism (the core decision)
Use the `readme.aproda.md` "Stacking vs. changing" table:

| Intent | Mechanism | Touches Upstream? |
|--------|-----------|-------------------|
| "Additionally always do X" | **Stacking**: new `.aproda.instructions.md` (matching `applyTo`) | ❌ no |
| New capability (skill/agent/workflow) | **Net-new** `.aproda.` file / `skill-aproda-*` folder | ❌ no |
| Reroute an agent to a custom skill/step | **Indirection** — edit the agent in place | ✅ yes (D-2) |
| Change/relax an existing rule or flow | **In-place edit** of the original | ✅ yes (D-2) |

> **Stacking can only add/strengthen, never revoke** an Upstream rule (F-5). Anything that must *change or relax* existing behaviour requires an in-place edit and a register entry.

### Step 2 — Implement following the conventions
- Net-new file → `.aproda.` infix / `skill-aproda-*` folder, type suffix intact.
- In-place edit → keep it **additive and minimal** (smaller conflicts on the next pull).
- Persisted artifacts under `.github/**` are **English** (copilot-instructions rule).

### Step 3 — Record the decision
- Add/extend a **D-N entry** in `decisions.aproda.md` for any non-trivial design choice (rationale + rejected alternative).
- If you touched an Upstream file in place, add a row to the **Upstream-edits register** (file / change / decision / date) — this is the list the upgrade reviewer diffs against (D-6/D-7).

### Step 4 — Validate where you are, then flow back to the fork
- You are almost always editing a **working copy** of the layer inside a concrete project (so you can validate live — e.g. run `skill-aproda-test-loop`). That is fine and encouraged.
- **The change is only "real" once it flows back to the aproda-aldc fork** (`subtree push` / PR). Until then, the next `subtree pull` in any project will overwrite or conflict with the local-only edit, and project copies drift.
- Direction: **fork = source of truth**; projects = working copies that read+apply and may edit+validate, then push the change upstream to the fork.

## Distribution model

```
aproda-aldc fork (source of truth)
        │  subtree pull (D-6)         ▲  subtree push / PR
        ▼                             │  (layer changes flow back)
project repo A / B / C  ── read + apply (many) ── edit + validate (few) ──┘
```

- **Everything in this layer ships to every project** via the `.github/` subtree (skills, instructions, site-profile, this meta-skill).
- **Reading/applying** happens in every project; **changing** happens where the need arises (with live validation), then **must** flow back to the fork.
- A repo that does **not** carry the full subtree relies on the personal **user-memory** summary of the infra facts as a fallback (redundant by design, like the self-describing `uat-issues.md`, D-11).

## Constraints

- This skill **explains and orchestrates** the layer; it does not duplicate `readme.aproda.md` / `decisions.aproda.md` / `site-profile.aproda.md` — it links them.
- Extend mode is **gated by the steward guardrail** (HITL stop). Never change/relax an Upstream behaviour without surfacing the D-entry and getting confirmation.
- It does **not** build BC product code — that is the domain skills + agents.
