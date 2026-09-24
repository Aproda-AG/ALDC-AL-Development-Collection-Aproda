# E-006 — Layer Visibility & Version Consistency

> **Status (2026-09-24):** findings complete · **Block 1 done and pushed** (T-8, T-9, T-19 — the three
> defects that reached consumer projects) · Blocks 2–5 open. Live tracker:
> [`action-plan.md`](action-plan.md).
> **Scope:** the Aproda ALDC fork repo itself. **Out of scope** (per maintainer): `packages/foundation/**`
> (APM package distribution — the upstream ALDC VS Code extension, not used at Aproda; Aproda ships
> `tools/aproda-vscode-extension/`) and Claude Code / Codex as *runtimes* (Aproda uses GitHub Copilot only).
>
> ⚠️ `.claude/**` and `claude-plugin/**` are **in scope anyway** — see F-1: VS Code Copilot actively
> loads `.claude/` in this repo, so a "Claude-only" tree is not inert here.

## Why this exists

Two questions were asked of the repository:

1. **Is the Aproda ALDC layer cleanly and completely represented** in the instructions and catalog/index
   files that GitHub Copilot and human contributors actually read?
2. **Is the mixed `ALDC Core v1.1` / `v1.2` labelling deliberate or drift?**

The audit answered both, and surfaced one finding (F-1) that is more consequential than either question
as originally posed.

## TL;DR

| # | Finding | Severity |
|---|---------|----------|
| **F-1** | In the fork repo VS Code Copilot loads `.claude/`, **not** the root toolkit folders. The Aproda layer is therefore **completely invisible** to Copilot while working in the fork: 0 of 5 Aproda skills, 0 of 2 Aproda instructions, 0 of 1 Aproda agent. | 🔴 blocker |
| **F-2** | Direct consequence of F-1: the **D-16 steward guardrail does not fire in the fork** — the one repo where layer edits happen. Self-evidenced during this session. | 🔴 blocker |
| **F-3** | `readme.aproda.md`'s inventory table — self-declared as *"the Aproda index (D-17), the one place to answer 'what has Aproda added?'"* — is **missing 5 of 19 live layer artifacts**. | 🟠 major |
| **F-4** | `prompts/index.md` describes an **obsolete 18-workflow set from the v2.11.0 era** and **ships to every consumer project** via `aldc.yaml → required.catalog`. | 🟠 major |
| **F-5** | `tools/aldc-validate/index.js` still prints `v1.1` although the D-7 register (line 524) **claims the fix was applied on 2026-06-25** — a registered in-place edit that is not in the file. | 🟠 major |
| **F-6** | The v1.1/v1.2 split is **drift, not design** — and **~22 of ~24 drifted files are unmodified upstream content**. `aldc.yaml → core.version: 1.2.0` is authoritative; even `main:aldc.yaml` contradicts itself (line 1 says v1.1). Most remediation belongs **upstream**, not in the fork. | 🟠 major |
| **F-7** | **No documented duty exists** to update `*/index.md` when adding a primitive — not in `readme.aproda.md`, not in `skill-aproda-aldc`, not in `aproda-sync.json`. Every catalog drift found here is a symptom of this one missing rule. | 🟠 major |

Full evidence with `file:line` references in the two findings documents.

> **Update 2026-09-23 — upstream audit.** The local `main` branch (ALDC Core without the Aproda layer)
> was audited afterwards. It changed three conclusions:
> 1. The version drift is **inherited**, not introduced by Aproda (43× v1.1 vs 6× v1.2 on `main`) →
>    R-4/R-5 re-routed from "sweep in the fork" to **one upstream PR** (new Phase 4).
> 2. The missing `aldc-validate` fix was **never applied**, not reverted — the file is byte-identical to
>    `main` *and* `origin/main`. But 20 of 21 register entries are genuine, so the register is sound;
>    only the *verification step* was missing.
> 3. `.claude/` is **actively maintained upstream** (6 of the last 27 commits) — so F-8's "dead weight"
>    reading was wrong, and deleting it is not an option.

## Reading order

| Document | Contents |
|----------|----------|
| [action-plan.md](action-plan.md) | **Start here** — what is done, what is next, in which block |
| [findings-01-layer-visibility.md](findings-01-layer-visibility.md) | Task 1 — discovery mechanics, the four parallel distributions, inventory/catalog completeness, sync + validator coverage gaps (F-1…F-4, F-7 and 8 further findings) |
| [findings-02-version-drift.md](findings-02-version-drift.md) | Task 2 — full v1.1 vs v1.2 inventory, assessment, and recommendation (F-5, F-6) |
| [bcquality.md](bcquality.md) | **Own chapter** (Block 4) — BCQuality evidence, audit checking and the per-user clone path. Split out because F-16 opened a whole subsystem. **As-is until Block 4** |
| [E-006-plan.md](E-006-plan.md) | Phased remediation plan + the concrete text proposed for `skill-aproda-aldc` and `skill-aproda-aldc-release` + Appendix A (already-made session edits) |

## The single most important sentence

> Every catalog and inventory defect in this audit is downstream of **one missing rule**: *"when you add
> or remove a primitive, update the catalogs."* Fixing the individual files without installing that rule
> (and a validator that enforces it) guarantees the same audit finds the same class of defect again.

---

**Author:** GitHub Copilot (Claude Opus 5), commissioned by the fork maintainer
**Date:** 2026-09-22
**Layer version at audit time:** `1.2.0_aproda.17` (`aldc.yaml → aproda.layerVersion`)
**ALDC core version at audit time:** `1.2.0` (`aldc.yaml → core.version`)
