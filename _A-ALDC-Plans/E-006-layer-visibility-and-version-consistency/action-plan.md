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
| **F-16** | `neverTouchExceptions → workflows/bcquality-evidence.yaml` is **inert** — declared as the one Aproda-owned file under a denied folder, but `.github/workflows/…` reverse-maps to `$null` before the exception is consulted. Verified absent in the reference project. Same mechanism as F-14 | ⏳ **T-21**, needs a decision |
| — | `.github/actions/aldc-validate/action.yml` + `workflows/aldc-validate.yml` do **not** ship either. Not a defect: a consuming repo runs AL-Go workflows. The register entry now says so explicitly | ✅ register corrected |
| — | `readme.aproda.md` carries a **second, partial in-place register** (8 rows vs. 47 in `decisions.aproda.md`) and claimed the never-applied v1.1→v1.2 fix too. A third source of truth next to the register and `aproda-sync.json` | ⏳ folded into **T-10** |
| — | `agents/al-conductor.agent.md` says "Core **v1.1** violation" twice. The file is already an `inPlaceEdits` merge-point, so fixing it adds no new conflict surface — the "don't sweep inherited v1.1" argument does not apply here | ⏳ folded into **T-9** leftovers |

**T-21 — decide and fix F-16.** Two options: (a) add `workflows/**` to `dotGithub` so the declared
exception actually works and the BCQuality evidence CI reaches projects; (b) declare the workflow
fork-only and remove it from `neverTouchExceptions`, since a consuming repo's CI is AL-Go's. Option (a)
is what the manifest currently *claims*; (b) is what it currently *does*. Either way the two must agree.

---

## Next — Block 2: the rule (durable value)

*Without Block 2, Block 1 is a one-off cleanup that the next audit repeats.*

| # | Todo | Depends on |
|---|---|---|
| **T-5** | **D-46** "catalog synchronisation is part of a primitive change" + canonical catalog list; replace the provisional Step 2.5 in `skill-aproda-aldc` with the decision-backed version (text in `E-006-plan.md` § A) | — |
| **T-7** | Register verification in `skill-aproda-aldc-release`: diff each `inPlaceEdits` path against the pinned upstream base — *byte-identical ⇒ registered edit missing*. Exactly the check that would have caught T-9 in June | T-5 |
| **T-6** | **D-47** + three validator rules: `catalogCoherence`, `versionCoherence` (⚠️ scope to Aproda paths, else ~22 inherited failures), `aprodaInventoryCoherence`; optional `aproda.primitives` in `aldc.yaml` | T-5 |

---

## Next — Block 3: remaining cleanup

| # | Todo | Ships? |
|---|---|---|
| **T-10** | Complete `readme.aproda.md` inventory (5 missing artifacts incl. F-14 files); unify path layout; fix D-range claims | ✅ |
| **T-11** | Rewrite `agents/index.md` (11 agents) **and** register it in `aldc.yaml → required.catalog` — otherwise it keeps not shipping (proven) | ✅ after registration |
| **T-12** | Correct `aldc.yaml → aproda.basePin` to the real merge-base `4f3371f`; drop the stale "in sync" comment | ✅ |
| **T-17** | `external.bcquality.home` (`../../BCQuality-Aproda`) is project-correct / fork-wrong. Needs a layout decision: dual-variant rewrite or a consistently toolkit-relative value | ✅ |
| **T-13** | Document `.claude/` + `claude-plugin/` as upstream-owned (**do not delete** — 6 of 27 upstream commits touch them) | ❌ |
| **T-14** | Small items: `.github/agents/test.agent.md`; register or inline `docs/copilot-reference.md` (**F-11 proven**); clarify `CLAUDE.md` ownership | mixed |
| **T-4** | **Q-3 release strategy** — bump `layerVersion`? Recommendation: *after* T-7, so the release gate exists before the release | — |

---

## Next — Block 4: upstream (independent track)

| # | Todo |
|---|---|
| **T-15** | One upstream PR finishing the v1.1 → v1.2 migration (`aldc.yaml` line 1, validator banner, catalogs, ~11 doc files) + "superseded" banner on `ALDC-Core-Spec-v1.1.md`. Upstream touched none of them in 27 commits. **Include the `extended` entrypoint mode (D-45)** — the gap is not Aproda-specific |
| **T-16** | **Q-4:** analyse the 27-commit / 340-file / ~47k-line upstream backlog (canonical Spec Agent, Codex bootstrap, BC29/AL18 workflows) *before* the next pull. `basePin` currently claims "in sync", which actively misleads |

---

## Explicitly not doing

| | Why |
|---|---|
| Sweeping the ~22 inherited v1.1 files in the fork | Converts conflict-free files into permanent D-2 merge-points for a defect Aproda did not cause → Block 4 |
| Deleting `.claude/` or `claude-plugin/` | Upstream-owned and actively maintained; deletion guarantees a pull conflict |
| Deleting `instructions/copilot-instructions.md` | Q-2 — upstream-maintained, would break the validator and create a delete/modify conflict |
| Releasing before T-7 exists | Would release exactly the state whose verification is still missing |

---

## Recommended order

```
Block 1  T-8, T-9, T-19   -> commit + push      ✅ done 2026-09-24
Block 2  T-5, T-7, T-6                          the rule + enforcement (own session)
Block 3  T-10 … T-14, T-4                       cleanup, now validator-protected
Block 4  T-15, T-16                             upstream, parallel at any time
```

**Block 2 is now the priority, and T-7 is its real target.** Block 1 produced two independent cases
(T-9, T-19) of a change believed to be in effect that was not. T-7 is the only proposed measure that
would have caught either. Its stated dependency on T-5 is worth re-checking when Block 2 starts —
register-vs-upstream diffing may not actually need the catalog rule, in which case T-7 can go first.
