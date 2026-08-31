---
# author: "[Flobi-Wan-Kenobi (Florian Köll)](https://github.com/Flobi-Wan-Kenobi)"
description: >
  Aproda convention (D-11): governs the full HITL Validation lifecycle — phase transition
  after agent delivery, creating the issues file on first feedback, and consuming open issues
  one-by-one with deploy-run-verify. The '{req}-hitl-validation-issues.md' Status fields are
  the single to-do signal; the spec is never a checklist.
applyTo: "**/*.al"
---

# Aproda — HITL Validation lifecycle & work-item consumption

> Stacking instruction (additive; no Upstream behaviour is changed). Rationale: `decisions.aproda.md` D-10..D-13.

## Status vocabulary (`memory.md` → `## Active Requirements` → Status column)

| Status | Meaning |
|--------|---------|
| `draft` | Not yet in active implementation (design, spec, backlog) |
| `in progress` | Conductor / impl-specialist actively implementing |
| `review` | Delivered; user testing; issues file has open TODOs |
| *(row moved to Completed)* | `al-pr-prepare` executed |

## Phase lifecycle

```
draft
  → conductor / impl-specialist starts → sets memory.md Status = 'in progress'
  → implements + deploy-run-verify
  → on delivery: sets memory.md Status = 'review'
  → [review phase begins]
       user tests → reports feedback
       → {req}-hitl-validation-issues.md  (created on first feedback; appended on later rounds)
       → agent resolves TODO issues one-by-one + deploy-run-verify → DONE
       → when last issue = DONE: inform user — "all issues resolved, ready for al-pr-prepare"
         (no status change needed — pr-prepare moves row to Completed once its
         Completion Gate is satisfied: PR + ADO-Kommentar/State + al-doc-update)
  → al-pr-prepare: moves row to ## Completed Requirements
```

Any user feedback, fix, or extension on a **delivered** req is HITL feedback — not a spec edit.

**Reopening a completed req:** if new issues surface after delivery, move the row back to `## Active Requirements` with `Status = review` and append a new `## Loop N` to the existing issues file (continuing monotone IDs).

## Entry check (do this before every AL change on a req)

1. **Read `memory.md` → `## Active Requirements`** (single read, token-cheap).
2. Find row(s) where Status = `review`:
   - One row → proceed to **§ Consuming issues**.
   - Multiple rows → if the user's message already names a req, use that; otherwise ask which plan.
   - No `review` row → normal implementation flow.
3. With the req name, check `.github/plans/{req}/{req}-hitl-validation-issues.md`.

## Creating the file (first HITL feedback for a req)

When the user reports the first issue and no `{req}-hitl-validation-issues.md` exists yet, create it:

```markdown
# {req} — HITL Validation Issues

## Status-Board

| ID  | Summary           | Status |
|-----|-------------------|--------|
| I-1 | {one-line summary} | TODO  |

---

## Loop 1 — {YYYY-MM-DD}

### I-1 — {Summary}

**Status:** TODO
**Reported:** {YYYY-MM-DD}

{issue description as provided by user}
```

Subsequent user feedback rounds: append `## Loop N — {date}` with continuing IDs (I-2, I-3, …) and `Status: TODO`.

## Consuming issues

When the file exists:

1. **Read only the Status-Board** (index table at the top) to see what is open.
2. **Take the next `Status = TODO` issue**, respecting any stated order.
3. **Load only that issue's detail block** — skip `DONE` blocks.
4. **Implement** the fix/extension for that one issue only.
5. **Run the Deploy-Run-Verify Cycle** (`skill-aproda-deploy-run-verify`).
6. **Set `Status = DONE`** for that issue (and update the Status-Board row).
7. **If no more TODO issues remain:** update `memory.md` → Active Requirements → Status to `HITL Validation — All DONE` and add an Inter-Session Context entry (date, who, what resolved).

## Rules

- The `{req}.spec.md` carries **no status** — never derive to-dos from it during HITL phase.
- **Only** fix what an open issue asks for. Do not invent scope.
- Issue numbers are **global and monotonic** (I-1, I-2, …) — never renumber.
- All rounds live in **one file** as `## Loop N` headers — do not split per round.
- Applies **pre-delivery only**. After acceptance, further changes start a new plan folder (D-12).
