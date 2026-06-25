---
description: >
  Aproda convention (D-11): when a requirement under .github/plans/ has a
  '{req}-uat-issues.md' work-item, consume it via its Status-Board and per-issue
  Status field instead of treating the spec as a checklist. Pre-delivery UAT loop.
applyTo: "**/*.al"
---

# Aproda — UAT-loop work-item consumption

> Stacking instruction (additive; no Upstream behaviour is changed). Rationale: `decisions.aproda.md` D-10..D-13.

When you implement AL changes for a requirement that has a `*-uat-issues.md` file in its `.github/plans/{req}/` folder, follow this contract:

1. **Read only the Status-Board** (the index table at the top of the `uat-issues.md`) to see what is open.
2. **Take the next issue with `Status = TODO`**, respecting any stated implementation order.
3. **Load only that issue's detail block** — do not read `DONE` blocks (token-efficient).
4. **Implement** the fix/extension/adjustment for that one issue.
5. **Run the test-loop** (`skill-aproda-test-loop`) before considering the issue resolved.
6. **Set that issue's `Status = DONE`** (and update the Loop roll-up) in the `uat-issues.md`.

Rules:

- The `{req}.spec.md` is the **target-state reference** ("how the system should be"). It is **not** a checklist and carries **no status** — never derive "what is still to do" from the spec or from a spec `git diff`. The `uat-issues.md` `Status` fields are the single to-do signal.
- You **only fix / extend / adjust** what an open issue asks for. Do not invent scope.
- **Issue numbers are global and monotonic** (I-1, I-2, …) across all UAT loops — never renumber.
- UAT loops are **headers within the one `uat-issues.md`** (`## Loop N — <date>`), not separate files. Do not split per loop unless explicitly instructed.
- If new UAT feedback arrives, append it as a new `## Loop N` section with new (continuing) issue IDs and `Status: TODO`.

This applies **pre-delivery** only. After delivery (acceptance), further changes start a **new plan folder** (D-12) — they are not added to this file.
