---
description: >
  Aproda guardrail (D-16): when you edit any Aproda ALDC layer file (a .aproda.*
  file or anything under a skill-aproda-* folder), STOP first — surface the relevant
  decisions.aproda.md decision, confirm with the user that the change is deliberate
  (not an unknowing revert), and remember it must flow back to the aproda-aldc fork.
applyTo: "**/*.aproda.*, **/skill-aproda-*/**"
---

# Aproda — ALDC layer steward (HITL guardrail)

> Stacking instruction (additive; strengthens, never revokes Upstream behaviour). Rationale: `decisions.aproda.md` D-16. The "how/why" knowledge is in `skill-aproda-aldc`.

You are editing a file that belongs to the **Aproda ALDC customization layer** — the `.aproda.` fork layer on top of ALDC Core. Most users only **read/apply** this layer; **changing** it is rare and consequential. Before you change anything here:

## STOP — confirm before editing (mandatory HITL)

1. **Load `skill-aproda-aldc`** if not already loaded (the layer's how/why + the stacking-vs-edit decision tree).
2. **Identify the relevant decision** in [`decisions.aproda.md`](../decisions.aproda.md) (D-1..D-N) that the intended change touches.
3. **Tell the user, in one short note**:
   - which file/mechanism is affected (net-new `.aproda.` vs in-place Upstream edit),
   - which **D-entry** the change touches, and
   - whether the change **changes/relaxes a deliberate decision** (vs purely additive).
4. **Wait for explicit confirmation.** Do not edit until the user confirms they intend to change the decision knowingly. The goal is to prevent silently reverting or ignoring a deliberate choice.

> If the change is **purely additive** (a brand-new `.aproda.` file / `skill-aproda-*` folder that revokes nothing), say so — the confirmation can be brief, but still surface it. If it **changes or relaxes** an existing rule/flow, treat it as a real in-place Upstream edit (D-2) and be explicit.

## After the change

- **Record it**: add/extend a D-entry in `decisions.aproda.md`; if you touched an Upstream file in place, add a row to the **Upstream-edits register**.
- **English** for all persisted `.github/**` artifacts.
- **Flow back to the fork**: you are editing a **working copy** inside a project. Validate here, but remind the user the change is only adopted once it is pushed back to the **aproda-aldc fork** (`subtree push` / PR) — otherwise the next `subtree pull` overwrites it and project copies drift.

This guardrail applies **only** to Aproda-layer files (this instruction's `applyTo`). It does not affect normal AL/product development.
