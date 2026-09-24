# E-006 — Action Plan & Status

> Operational tracker for the E-006 remediation. The *analysis* lives in
> [`findings-01`](findings-01-layer-visibility.md) / [`findings-02`](findings-02-version-drift.md); the
> *strategy* in [`E-006-plan.md`](E-006-plan.md). **This file tracks what is done and what is next.**
>
> **Last updated:** 2026-09-24 · **Branch:** `feature/e006-catalog-consistency` · **Layer:** `1.2.0_aproda.17`

---

## Legend

| | |
|---|---|
| ✅ | done and verified |
| 🟡 | in progress / partially done |
| ⏳ | open |
| 🔴 | active defect — affects customers or releases today |

---

## Done

| # | Todo | Outcome |
|---|---|---|
| **T-0** | Integrity check before commit | ✅ 5 script-written files intact, trailing newlines ok, renumbering clean |
| **T-1** | Branch + commit + push | ✅ `53f2a7b`, 19 files, pushed to `origin/feature/e006-catalog-consistency` |
| **T-2** | Q-1 fork discovery | ✅ **A′** — pointer in `.github/copilot-instructions.md`; **D-5** scope-corrected. Settings route rejected on evidence (`chat.*FilesLocations` deprecated / Local-agent-only, discovery paths fixed) |
| **T-3** | Q-2 `copilotSource` | ✅ **Keep.** Upstream maintains it (2 of 27 commits), fork never modified it, deletion ⇒ delete/modify conflict + `missingToolkitFiles: error` |
| **T-18** | `aldc.code-workspace` BCQuality path | ✅ **Not a project defect** — `templates/workspace.seed.jsonc` already ships `../BCQuality-Aproda`; only the fork-local file is wrong, and `*.code-workspace` is `neverTouch` |
| — | Ansatz 2: `extended` entrypoint mode | ✅ **D-45** + validator change; validator self-confirms: *"deliberately extends its source (17633 vs 16341)"*, 0 warnings |
| — | Decision-record hygiene | ✅ **D-42** written (dangling reference), duplicate `D-37` → **D-43**, **D-44** (ground-truth doc), FKH entries D-26/D-36/D-43 compressed. 45 entries, no gaps, no duplicates |
| — | Fork-vs-project analysis | ✅ Ground-Truth §7 — what is fork-only, what ships, what needs a real project |
| — | **Reference-project measurement** | ✅ `straub-medical-ag-base` — P-1/P-2/P-4/P-8/P-9 confirmed; F-4/F-5/F-11 **proven**; **F-14** newly found |
| **T-20** | **F-15** — committed UTF-8 BOM in 10 toolkit files | ✅ Removed. `agents/al-conductor.agent.md` had `EF BB BF` before `---`, so its frontmatter was never parsed (agent showed as `al-conductor`, tools/model unapplied). 3 files had already reached the reference project. Byte check added as Ground-Truth §6-G. Committed in isolation as `b3bc2d9` (10 files, 10+/10−) |
| **T-9** | `aldc-validate` v1.1 → v1.2 | ✅ 5 sites (`index.js` ×4 + `action.yml`). Validator now self-reports `ALDC Core v1.2 COMPLIANT`. Register line corrected: the 2026-06-25 entry documented a fix **never applied** |
| **T-8** | Rewrite `prompts/index.md` | ✅ 12 linked / 12 real — 0 phantom, 0 missing. Added a "not workflows — these are skills" redirect table for the 12 removed names. No `inPlaceEdits` entry needed: ships via `required.catalog` + `includeAldcFramework` |
| **T-19** | **F-14** — `onboarding.aproda.md` never ships | ✅ Root cause was a **manifest bug**, not a policy question: `Get-LogicalPath` maps layout *before* applying globs, so a `.github/` fork file absent from `dotGithub` returns `$null` and is invisible — despite matching `**/*.aproda.*`. Added to `dotGithub`; D-18 extended with the trap. `CHANGELOG.aproda.md` is correctly listed — its absence in the reference project is sync lag, not a defect |
| **T-7** | Register verification in `skill-aproda-aldc-release` | ✅ New "Register verification" section + `tools/aproda-sync/Test-InPlaceEditsRegister.ps1`: diffs every `inPlaceEdits` path against `aldc.yaml → aproda.basePin`; byte-identical ⇒ registered edit missing. Smoke-tested against the current register: 21/21 ok, pin reachable. Registered in `decisions.aproda.md` (D-4/D-7) |
| **T-5** | **D-46** + canonical catalog list + decision-backed Step 2.5 in `skill-aproda-aldc` | ✅ `decisions.aproda.md` D-46 (canonical catalog table) + D-47 (validator rules) added at end of file. `skill-aproda-aldc/SKILL.md` Step 2.5 replaced with the D-46-referencing version; knowledge-map row added |
| **T-6** | **D-47** + three validator rules (`catalogCoherence`, `versionCoherence`, `aprodaInventoryCoherence`) + `aproda.primitives` in `aldc.yaml` | ✅ Implemented in `tools/aldc-validate/index.js`, registered at `"warn"` in `aldc.yaml → validation.rules`. Live-run found real drift (genuine findings, fixed in T-10/T-11 below): 4 unlisted agents + 1 unlisted skill in catalogs, 4 missing + 6 unresolved-reference gaps in `readme.aproda.md`'s inventory (confirms F-10's `.github/`-prefix inconsistency). The 4th flag ("`skill-aproda-aldc-release/SKILL.md` still v1.1") was **verified false on 2026-09-24 (T-10)** — the hits are historical quotes about the T-9 incident, not a live claim; see D-47's corrected `versionCoherence` row. `aproda.primitives` block added (5 skills, 1 agent, 1 workflow, 2 instructions — matches `copilot-instructions.md`'s stated counts). Registered in `decisions.aproda.md` (D-2/D-47) |
| **T-10** | Complete `readme.aproda.md` inventory; unify path layout; fix D-range/pin claims | ✅ Added the 5 missing artifacts (`onboarding.aproda.md`, `al-translate-subagent.aproda.agent.md`, `tools/aproda-sync/README.aproda.md`, `skill-aproda-ado/`, `skill-aproda-fkh/`); removed the stray `.github/` prefix from 6 rows (F-10); `D-1…D-27`/`D-1…D-22` → `D-1…D-47`; corrected the "Pinning" section's inline value to match T-12; marked the partial in-place-edits table as a curated subset pointing at the D-7 register as sole authority |
| **T-11** | Rewrite `agents/index.md` (11 agents) and register it in `aldc.yaml → required.catalog` | ✅ 7 public + 4 subagents (was 4+3, missing `al-triage`/`dredd`/`al-agent-builder`/`al-translate-subagent.aproda`); v1.1 → v1.2; registered in `required.catalog` alongside `docs/copilot-reference.md` (F-11) |
| **T-13** | Document `.claude/` + `claude-plugin/` as upstream-owned | ✅ New "Upstream-owned content the fork does not maintain" section in `readme.aproda.md`; also covers `.github/agents/test.agent.md`, confirmed via `git log`/`git branch --contains` to originate from upstream commit `179e782` (not an Aproda leftover as first assumed — do not delete) |
| **T-14** | `.github/agents/test.agent.md`; `docs/copilot-reference.md`; `CLAUDE.md` ownership | ✅ Documented (not deleted, see T-13); registered `docs/copilot-reference.md` in `required.catalog` and replaced its 3 fork-only-correct relative links in `copilot-instructions.md` with layout-aware prose (F-11); `CLAUDE.md` given a one-line ownership disclaimer instead of a full count rewrite; `al-conductor.agent.md`'s stray "Core v1.1 violation" (2×, Block-1 follow-up) corrected to v1.2 |
| **T-4** | Q-3 release strategy — bump `layerVersion`? | ✅ **Decided: not now.** Bump happens at the actual release step via `skill-aproda-aldc-release`, which now has the T-7 register-verification gate available to run first. Block 3 is cleanup on `feature/e006-catalog-consistency`, not a release |

---

## Next — Block 1: active defects

*✅ **Done 2026-09-24.** All three shipped defects are closed — see the Done table above.*

| # | Todo | Outcome |
|---|---|---|
| ✅ **T-8** | Rewrite `prompts/index.md` | 12 phantom workflows removed, 6 missing added |
| ✅ **T-9** | `aldc-validate` v1.1 → v1.2 + `action.yml` + register correction | False compliance statement ended |
| ✅ **T-19** | **F-14** `onboarding.aproda.md` | `dotGithub` gap closed; D-18 documents the trap |

> **What T-9 and T-19 have in common:** both were *registered or intended* changes that silently never
> took effect — one documented in the D-7 register but never applied to the file, one matching the
> allowlist globs but blocked by the layout mapping. Neither is visible by reading the governance
> documents; both need a check against reality. That is precisely **T-7**'s job — which raises its
> priority in Block 2.

### Follow-up from Block 1 (found by generalising the two findings)

*Closing T-9 and T-19 fixed the two known instances. Asking "are there more of the same" produced these.*

| # | Finding | Status |
|---|---|---|
| **F-16** | `neverTouchExceptions → workflows/bcquality-evidence.yaml` is **inert** — declared as the one Aproda-owned file under a denied folder, but `.github/workflows/…` reverse-maps to `$null` before the exception is consulted. Verified absent in the reference project. Same mechanism as F-14 | → **Block 4**, see [`bcquality.md`](bcquality.md) B-1 |
| — | `.github/actions/aldc-validate/action.yml` + `workflows/aldc-validate.yml` do **not** ship either. Not a defect: a consuming repo runs AL-Go workflows. The register entry now says so explicitly | ✅ register corrected |
| — | `readme.aproda.md` carries a **second, partial in-place register** (8 rows vs. 47 in `decisions.aproda.md`) and claimed the never-applied v1.1→v1.2 fix too. A third source of truth next to the register and `aproda-sync.json` | ⏳ folded into **T-10** |
| — | `agents/al-conductor.agent.md` says "Core **v1.1** violation" twice. The file is already an `inPlaceEdits` merge-point, so fixing it adds no new conflict surface — the "don't sweep inherited v1.1" argument does not apply here | ⏳ folded into **T-9** leftovers |

> Chasing F-16 opened a whole subsystem (ownership, the per-user clone path, a validator that passes
> vacuously, three shipped claims that are not in effect). It is **not** a layer-visibility problem and
> now has its own chapter: **[`bcquality.md`](bcquality.md)** — scheduled as Block 4, untouched until then.

---

## Next — Block 2: the rule (durable value)

*Without Block 2, Block 1 is a one-off cleanup that the next audit repeats.*

*✅ T-7, T-5, T-6 all done 2026-09-24 — see Done table above. Block 2 is closed.*

> **T-7 closed 2026-09-24.** It did **not** need the catalog rule — it needed `inPlaceEdits` and a
> *correct* pin, i.e. **T-12**, done earlier the same day. Result: `Test-InPlaceEditsRegister.ps1`
> verified the current register clean (21/21), so no Block-1-style latent defect remains undiscovered.
>
> **T-5/T-6 closed 2026-09-24.** D-46/D-47 written, Step 2.5 replaced, three validator rules
> implemented and live-run against this repo. All three genuinely found drift on the first run
> (proof the rules work, not a bug) — none of that drift was fixed as part of T-5/T-6; it is now
> Block 3's job (T-10 for the `readme.aproda.md` inventory + path-prefix unification, T-11 for
> `agents/index.md` + its missing `required.catalog` registration, and one leftover "v1.1" string
> in `skill-aproda-aldc-release/SKILL.md`). Only **two** of the four real catalogs (`prompts`,
> `skills`) are registered in `aldc.yaml → required.catalog` — T-11 still needs to add `agents`
> and `instructions`, else `agents/index.md` keeps not shipping to consumer projects.

---

## Next — Block 3: remaining cleanup

*✅ **Done 2026-09-24.** All five items closed — see the Done table above.*

| # | Todo | Ships? |
|---|---|---|
| ✅ **T-10** | Complete `readme.aproda.md` inventory (5 missing artifacts incl. F-14 files); unify path layout; fix D-range claims | ✅ |
| ✅ **T-11** | Rewrite `agents/index.md` (11 agents) **and** register it in `aldc.yaml → required.catalog` | ✅ |
| ✅ **T-12** | `aproda.basePin` `a900263…` → `4f3371f…` (done 2026-09-24, pulled forward — T-7 depended on it) | ✅ |
| ✅ **T-13** | Document `.claude/` + `claude-plugin/` as upstream-owned | ❌ (fork-only) |
| ✅ **T-14** | `.github/agents/test.agent.md`; `docs/copilot-reference.md`; `CLAUDE.md` ownership | mixed |
| ✅ **T-4** | Q-3 release strategy — decided: bump at release time, not here | — |

> **T-14 correction en route.** The `.github/agents/test.agent.md` finding (F-12) was scoped as
> "delete or document" — `git log`/`git branch --all --contains` showed it originates from upstream
> commit `179e782`, reachable from `origin/main`. It is Upstream content, not an Aproda leftover;
> deleting it would have created the exact needless merge-point this whole block argues against for
> `.claude/`. Documented instead, alongside `.claude/`/`claude-plugin/` (T-13).
>
> **A second self-correction.** T-6's `versionCoherence` live-run flag on
> `skill-aproda-aldc-release/SKILL.md` ("still v1.1") was re-verified while working T-10 and found to
> be a **false positive** — all three hits are historical quotes documenting the T-9 incident itself,
> not a live claim about the file's own version. Left unedited; D-47's `versionCoherence` row and the
> T-6 register entry in `decisions.aproda.md` were corrected to say so, rather than "fixing" prose that
> was already correct.

> `T-17` (BCQuality clone path) **moved to Block 4** — it is not a path-layout nit, it silently
> disables citation checking.

---

## Next — Block 4: BCQuality (own chapter)

*Full content in **[`bcquality.md`](bcquality.md)**. Listed here only so the plan stays complete.*

**Until this block starts, BCQuality stays exactly as-is.** The knowledge layer works where a clone is
mounted; only the **verification** layer is broken. Treat any "BCQuality Evidence" block in a phase
report as a claim, not as proof.

| # | Item |
|---|---|
| **T-22** | **Per-user clone path** — the actual requirement: the clone location is a property of the workstation, not the repo. Today repo-scoped in `aldc.yaml` + `*.code-workspace`. **Designed 2026-09-24** (resolver + `#bcquality` LM tool); junction sidecar plan B **tested 2026-09-24 → viable**, one confirmed limitation (B-9). Implementation open |
| **T-28** | **B-10** — in a consuming project `aldc.yaml` is deliberately gitignored **and** sits outside every workspace root. The agents' documented *"fall back to direct root-level access"* clause therefore cannot succeed; `#aldcConfiguration` is load-bearing, not optional. Fix the prose, not the ignore rule |
| **T-29** | **B-9** — a workspace root cannot exclude itself from search; **fix found in round 4** (mount a wrapper folder, nest the clone one level down; shipped layout `.external/bcquality`). Decide whether to apply it to **the sibling-root mount shipping today**, which is unexcludable as laid out |
| **T-30** | ✅ **Closed 2026-09-24** — an excluded mount stays readable (consumption is read-by-path, never search). Implementation constraint carried forward: `search.exclude` + `files.watcherExclude` only, **never `files.exclude`** |
| **T-31** | ✅ **Closed 2026-09-24** — `aldc-validate` and `aproda-sync -WhatIf` produce **identical output with and without the junction** (control comparison, not a single run). The feared allowlist blow-up did not occur. Residual: Windows-specific — re-measure for POSIX symlinks |
| **T-32** | ✅ **Closed 2026-09-24** — a missing mount is cosmetic: yellow Explorer entry, no workspace-file rewrite, and a junction created live is readable immediately without a reload. No reload prompt or activation-timing logic needed; `BCQuality/.gitkeep` **decided against** |
| **T-33** | **Move `aldc.yaml` to `toolkitRoot`** (`.github/` in a consumer) — the structural fix for B-10. `.github` is a workspace root, so the direct read finally works without the extension. Fork unaffected (`toolkitRoot: "."`). Two-rung lookup for a non-breaking migration; prose lands with T-22/T-28 in one pass |
| **T-17** | `external.bcquality.home` resolves to a non-existent directory in the fork — the validator skips citation checking *although a clone is present* |
| **T-23** | Validator **passes vacuously**: three paths to false green, all exit `0`. Prerequisite for any gate |
| **T-24** | Restore honesty in shipped docs: `aldc.yaml` points at absent files, `copilot-instructions.md` promises CI that is not there, the script advertises a pin check it no longer performs |
| **T-21** | Decide the CI question (ship or declare fork-only). Check first whether `BCQuality-Aproda` is private — an unauthenticated clone would fail on a GitHub runner |
| **T-25** | One-line fix: the manifest calls an Upstream workflow "ours" |
| **T-26** | Agent-executed gate in `al-pr-prepare` — feasibility confirmed, but must evaluate `notes` not exit code, and is a self-check, not independent verification |
| **T-27** | Exercise audit evidence (`.github/audits/`) end-to-end — never done |

> **BCQuality is Upstream, not Aproda** (`fa37cf7`, Javier Armesto Gonzalez, PR #51). Most fixes here are
> upstream-PR candidates rather than fork edits — the per-user path is the likely exception.

---

## Next — Block 5: upstream (independent track)

| # | Todo |
|---|---|
| **T-15** | One upstream PR finishing the v1.1 → v1.2 migration (`aldc.yaml` line 1, validator banner, catalogs, ~11 doc files) + "superseded" banner on `ALDC-Core-Spec-v1.1.md`. Upstream touched none of them in 27 commits. **Include the `extended` entrypoint mode (D-45)** — the gap is not Aproda-specific |
| **T-16** | **Q-4:** analyse the 27-commit / 340-file / ~47k-line upstream backlog (canonical Spec Agent, Codex bootstrap, BC29/AL18 workflows) *before* the next pull. `basePin` currently claims "in sync", which actively misleads |

---

## Explicitly not doing

| | Why |
|---|---|
| Sweeping the ~22 inherited v1.1 files in the fork | Converts conflict-free files into permanent D-2 merge-points for a defect Aproda did not cause → **Block 5** (upstream PR, T-15) |
| Deleting `.claude/` or `claude-plugin/` | Upstream-owned and actively maintained; deletion guarantees a pull conflict |
| Deleting `.github/agents/test.agent.md` | Confirmed 2026-09-24 (T-10/T-13) to originate from upstream commit `179e782` — same reasoning as `.claude/` |
| Deleting `instructions/copilot-instructions.md` | Q-2 — upstream-maintained, would break the validator and create a delete/modify conflict |
| Releasing before T-7 exists | Would release exactly the state whose verification is still missing |

---

## Recommended order

```
Block 1  T-8, T-9, T-19                                -> commit + push      ✅ done 2026-09-24
Block 2  T-7, T-5, T-6                                 -> commit + push      ✅ done 2026-09-24
Block 3  T-10, T-11, T-13, T-14, T-4                   -> commit + push      ✅ done 2026-09-24
Block 4  T-22, T-17, T-23 …                            BCQuality -> bcquality.md (as-is until then)
Block 5  T-15, T-16                                    upstream, parallel at any time
```

**Block 3 is closed.** All five items landed clean: `readme.aproda.md`'s inventory, path-prefix
consistency and stale-claim corrections (T-10); `agents/index.md` rewritten to the real 7+4 and
registered in `required.catalog` alongside `docs/copilot-reference.md` (T-11/T-14, F-11); `.claude/`,
`claude-plugin/`, and — after verifying its true origin — `.github/agents/test.agent.md` documented as
upstream-owned, not deleted (T-13); `CLAUDE.md` given an ownership disclaimer instead of a stale
rewrite, and `al-conductor.agent.md`'s leftover "Core v1.1 violation" corrected (T-14); Q-3 decided —
bump `layerVersion` at release time via `skill-aproda-aldc-release`, not as part of this cleanup (T-4).
One planned fix turned out to be unnecessary on verification: T-6's `versionCoherence` flag on
`skill-aproda-aldc-release/SKILL.md` was historical prose quoting the T-9 incident, not live drift —
left as-is, and the register text corrected instead of the file. Only Block 4 (BCQuality) and Block 5
(upstream) remain, both independent tracks. **Committed as `5f7d042` and pushed.**

**Block 4 status (2026-09-24).** Not opened. **T-22 is designed, tested and decided** — five measured
rounds in `straub-medical-ag-base`, recorded in [`bcquality.md`](bcquality.md) §1.3–§1.6 with two new
findings (B-9, B-10) and six new items (T-28–T-33). Nothing implemented; no shipped artifact touched.
