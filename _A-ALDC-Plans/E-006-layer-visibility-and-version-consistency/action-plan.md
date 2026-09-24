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

| # | Todo | Depends on |
|---|---|---|
| **T-5** | **D-46** "catalog synchronisation is part of a primitive change" + canonical catalog list; replace the provisional Step 2.5 in `skill-aproda-aldc` with the decision-backed version (text in `E-006-plan.md` § A) | — |
| **T-7** | Register verification in `skill-aproda-aldc-release`: diff each `inPlaceEdits` path against the pinned upstream base — *byte-identical ⇒ registered edit missing*. Exactly the check that would have caught T-9 in June | ~~T-5~~ → **T-12 ✅** |
| **T-6** | **D-47** + three validator rules: `catalogCoherence`, `versionCoherence` (⚠️ scope to Aproda paths — measured: 21 files carry "v1.1", only **2** are Aproda paths, so an unscoped rule fails 19 inherited files), `aprodaInventoryCoherence`; optional `aproda.primitives` in `aldc.yaml` | T-5 |

> **Dependency corrected (2026-09-24).** T-7 does **not** need the catalog rule — it needs `inPlaceEdits`
> and a *correct* pin. Its real precondition was **T-12**, which sat in Block 3. T-12 is now done, so
> **T-7 can go first** — and it is the highest-value item, being the only measure that would have caught
> both T-9 and T-19.
>
> Also ready: T-5/T-6 texts exist (`E-006-plan.md` Z50 / Z73 / Z92 / Z188); the provisional Step 2.5 is
> in place at `skill-aproda-aldc/SKILL.md` Z93–105. Four real catalogs exist (`agents`, `instructions`,
> `prompts`, `skills`), but only **two** are registered in `aldc.yaml → required.catalog` — so T-5's
> canonical list must cover registration too, else `agents/index.md` keeps not shipping (T-11, proven).

---

## Next — Block 3: remaining cleanup

| # | Todo | Ships? |
|---|---|---|
| **T-10** | Complete `readme.aproda.md` inventory (5 missing artifacts incl. F-14 files); unify path layout; fix D-range claims | ✅ |
| **T-11** | Rewrite `agents/index.md` (11 agents) **and** register it in `aldc.yaml → required.catalog` — otherwise it keeps not shipping (proven) | ✅ after registration |
| **T-12** | ✅ **done 2026-09-24** — `aproda.basePin` `a900263…` → `4f3371f…` (real merge-base, shared by `aproda`/`origin/aproda`/feature branch against the upstream mirror `origin/main`). Old value asserted "upstream == fork, in sync" while upstream was 27 commits ahead. Pulled forward out of Block 3 because **T-7 depends on it** | ✅ |
| **T-13** | Document `.claude/` + `claude-plugin/` as upstream-owned (**do not delete** — 6 of 27 upstream commits touch them) | ❌ |
| **T-14** | Small items: `.github/agents/test.agent.md`; register or inline `docs/copilot-reference.md` (**F-11 proven**); clarify `CLAUDE.md` ownership | mixed |
| **T-4** | **Q-3 release strategy** — bump `layerVersion`? Recommendation: *after* T-7, so the release gate exists before the release | — |

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
| **T-22** | **Per-user clone path** — the actual requirement: the clone location is a property of the workstation, not the repo. Today repo-scoped in `aldc.yaml` + `*.code-workspace`. Needs design |
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
| Sweeping the ~22 inherited v1.1 files in the fork | Converts conflict-free files into permanent D-2 merge-points for a defect Aproda did not cause → Block 4 |
| Deleting `.claude/` or `claude-plugin/` | Upstream-owned and actively maintained; deletion guarantees a pull conflict |
| Deleting `instructions/copilot-instructions.md` | Q-2 — upstream-maintained, would break the validator and create a delete/modify conflict |
| Releasing before T-7 exists | Would release exactly the state whose verification is still missing |

---

## Recommended order

```
Block 1  T-8, T-9, T-19   -> commit + push      ✅ done 2026-09-24
Block 2  T-7, T-5, T-6                          T-12 ✅ unblocked T-7 -> start there
Block 3  T-10, T-11, T-13, T-14, T-4            cleanup, now validator-protected
Block 4  T-22, T-17, T-23 …                     BCQuality -> bcquality.md (as-is until then)
Block 5  T-15, T-16                             upstream, parallel at any time
```

**Block 2 is now the priority, and T-7 is its real target.** Block 1 produced two independent cases
(T-9, T-19) of a change believed to be in effect that was not. T-7 is the only proposed measure that
would have caught either. Its stated dependency on T-5 is worth re-checking when Block 2 starts —
register-vs-upstream diffing may not actually need the catalog rule, in which case T-7 can go first.
