# E-006 — Action Plan & Status

> Operational tracker for the E-006 remediation. The *analysis* lives in
> [`findings-01`](findings-01-layer-visibility.md) / [`findings-02`](findings-02-version-drift.md); the
> *strategy* in [`E-006-plan.md`](E-006-plan.md). **This file tracks what is done and what is next.**
>
> **Last updated:** 2026-09-25 · **Branch:** `feature/e007-ado-mcp-cli-and-e006-part1` (renamed from `feature/e006-catalog-consistency`; E-006 commits end at `5f7d042`, E-007 sits on top) · **Layer:** `1.2.0_aproda.17`

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

> **✅ Implemented 2026-09-25 — uncommitted.** All eight items below (**T-33, T-22, T-28, T-29, T-17,
> T-24, T-25, T-35**) are done, in the order the plan prescribed, each built by an implementation
> subagent and then checked by a **separate** review subagent; every review finding was fixed and
> re-reviewed. The work sits in the working tree — **nothing was committed**, by instruction.
>
> Independent block-wide review verdict: **PASS WITH FINDINGS**. Scope held: no deferred Block-5 item
> was implemented, and nothing unrelated rode along. Six new findings (**B-12–B-17**) and three new
> open items (**T-36–T-38**) came out of the implementation — see [`bcquality.md`](bcquality.md) §4/§5.
>
> The single most consequential discovery: **B-12** — the syncer's framework scrape silently dropped
> every catalog entry carrying a trailing `# comment`, so **T-11's and T-14's "now it ships" claims were
> never in effect**. Same failure class those items existed to fix, found only by asking why a dry-run
> did not list a file. Fixed; measured 73 → 76 resolved entries.

**Until this block starts, BCQuality stays exactly as-is.** The knowledge layer works where a clone is
mounted; only the **verification** layer is broken. Treat any "BCQuality Evidence" block in a phase
report as a claim, not as proof. *(Still true for the verification layer after Block 4 — T-21/T-23/T-26
remain deferred.)*

> **Governing decision: [D-49](../../.github/decisions.aproda.md)** (2026-09-25) — written before any
> implementation, as D-16 requires. It carries the four-part design (resolver · `#bcquality` tool + dual
> path · `aldc.yaml` at `toolkitRoot` · `.external/` wrapper), the measured evidence, and the rejected
> alternatives. Register rows for the in-place edits follow at implementation time.

| # | Item |
|---|---|
| **T-22** | **Per-user clone path** — the actual requirement: the clone location is a property of the workstation, not the repo. Today repo-scoped in `aldc.yaml` + `*.code-workspace`. **Designed 2026-09-24** (resolver + `#bcquality` LM tool); junction sidecar plan B **tested 2026-09-24 → viable**, one confirmed limitation (B-9). Implementation open |
| **T-28** | **B-10** — in a consuming project `aldc.yaml` is deliberately gitignored **and** sits outside every workspace root. The agents' documented *"fall back to direct root-level access"* clause therefore cannot succeed; `#aldcConfiguration` is load-bearing, not optional. Fix the prose, not the ignore rule |
| **T-29** | ✅ **Decided 2026-09-25** — **B-9**: the seed **swaps** the BCQuality root instead of dropping it. `workspace.seed.jsonc` mounts `.external/` (wrapper + tracked `README.md`) with the excludes on `bcquality/**`; the junction inside is created by the extension, or by hand per the README. Aproda-owned file — no upstream edit. The unexcludable sibling root goes away. **Two writers, not one:** `Initialize-AprodaProject.ps1` carries its own fallback workspace writer — updating only the seed would leave projects created through that path on the old layout (F-14 class) |
| **T-30** | ✅ **Closed 2026-09-24** — an excluded mount stays readable (consumption is read-by-path, never search). Implementation constraint carried forward: `search.exclude` + `files.watcherExclude` only, **never `files.exclude`** |
| **T-31** | ✅ **Closed 2026-09-24** — `aldc-validate` and `aproda-sync -WhatIf` produce **identical output with and without the junction** (control comparison, not a single run). The feared allowlist blow-up did not occur. Residual: Windows-specific — re-measure for POSIX symlinks |
| **T-32** | ✅ **Closed 2026-09-24** — a missing mount is cosmetic: yellow Explorer entry, no workspace-file rewrite, and a junction created live is readable immediately without a reload. No reload prompt or activation-timing logic needed. `.gitkeep` was decided against, then **superseded 2026-09-25** by the tracked `.external/README.md`, which anchors the folder *and* explains the junction |
| **T-33** | **Move `aldc.yaml` to `toolkitRoot`** (`.github/` in a consumer) — the structural fix for B-10. `.github` is a workspace root, so the direct read finally works without the extension. Fork unaffected (`toolkitRoot: "."`). Two-rung lookup for a non-breaking migration; prose lands with T-22/T-28 in one pass |
| **T-17** | ✅ **Decided 2026-09-25 (revised after T-29)** — `external.bcquality.home` becomes the **constant `.external/bcquality`**: once the seed mounts the wrapper for everyone, the junction sits at the same repo-relative path in every project, so B-5 is fixed as a *class*. Framing stays "static default" — authority is the resolver's `resolvedHome` (T-22). Deliverables: set the value, rewrite the comment (static fallback **+ how to check the real value**: user setting / `Show BCQuality Status`), extension sets `BCQUALITY_HOME` (Global) for the script side. Fork value deliberately left alone. **Rejected**: extension writes `home` (redundant — gitignored, never leaves the machine that already knows better; fleet bootstrap would silently reset it) |
| **T-24** | Restore honesty in shipped docs: `aldc.yaml` points at absent files (B-3), `copilot-instructions.md` promises CI that is not there (B-4), the script advertises a pin check it no longer performs (B-7) — **and the `external.bcquality` comment claims the install scripts read `url`/`ref`/`pinnedCommit` from there, which B-11 disproved for the only install path Aproda uses.** The *fix* is deferred (T-34); the *claim* must not stay false meanwhile |
| **T-25** | One-line fix: the manifest calls an Upstream workflow "ours" |
| **T-35** | **Upgrade path from the old layout — last step of the block.** Existing projects carry the pre-Block-4 state: sibling BCQuality root in `*.code-workspace`, `aldc.yaml` at the repo root with `/aldc.yaml` in the ignore block, `BCQUALITY_HOME` written into the workspace file. **Design it only after T-33/T-22/T-28/T-29 are implemented** — the target shape must exist before a migration to it can be specified. Must be idempotent and a no-op on an already-migrated project |

> **BCQuality is Upstream, not Aproda** (`fa37cf7`, Javier Armesto Gonzalez, PR #51) — but after the
> Block-4/5 split that matters mainly for **Block 5**: the upstream-owned pieces (`validate_evidence.py`,
> the CI workflow, the install scripts) all moved there. Block 4's remaining items are Aproda-owned —
> the seed, the extension, the agent prose, `aldc.yaml` — with `aldc.yaml` and the agent files as the
> known in-place edits (D-7 register rows required).

---

## Next — Block 5: BCQuality part 2 (deferred)

*Split off Block 4 on 2026-09-25. Not urgent, and each item carries real effort — deferred deliberately
rather than left unnoticed.*

| # | Item | Why deferred |
|---|---|---|
| **T-34** | **B-11** — the extension's BCQuality install ignores `aldc.yaml`: hardcoded repo URL, and **`pinnedCommit` is never checked out**, so a configured pin is inert on the only install path Aproda uses | Pinning, checkout-on-update and the surrounding update semantics are their own piece of work. **No pin is set today** (`pinnedCommit: ""`), so nothing is currently mis-resolving — the defect is latent, not active. Revisit when reproducible, pinned evidence is actually wanted |
| **T-23** | Validator **passes vacuously**: three paths to false green, all exit `0` | The validator **is not shipped to consumers** (B-3), so "fail loudly" has nothing to fail in yet. Prerequisite for T-26 — do both together |
| **T-21** | Decide the CI question (ship or declare fork-only). **Precondition resolved 2026-09-24:** `BCQuality-Aproda` is **public** (unauthenticated `git ls-remote` succeeded) — the decision is about scope, not feasibility | The CI runs nowhere today (B-1). Deciding it changes nothing until something consumes it; T-24 records the *current* truth regardless of the outcome |
| **T-26** | Agent-executed gate in `al-pr-prepare` — must evaluate `notes` not the exit code, and is a self-check, not independent verification | Depends on T-23. A gate over a validator that passes vacuously would be gate theatre |
| **T-27** | Exercise audit evidence (`.github/audits/`) end-to-end — never done | Exploratory; nothing depends on it, and it needs a real Dredd run to produce input |
| **T-39** | **Overlay → sync: carry removals through.** A file dropped from the layer lingers in every project forever — and a stale agent or catalog file is still *loaded by Copilot*, i.e. invisible drift | **Nothing breaks today** (maintainer, 2026-09-25) — but worth looking at. Must **not** be a list-diff: it abandons the deliberate *"copy only, never delete"* invariant; the synced layer is git-ignored, so a wrong deletion has no `git restore` and will not return on the next pull; "absent from the list" ≠ "ours" (projects may add their own skills alongside); and the config list does not know files delivered via `includeGlobs`/skill-folder expansion. The right shape is a **manifest of what was actually delivered** |
| **T-40** | **minor — an existing project never gets a refreshed `Start-Pull.ps1`** (B-19). `Bootstrap-AprodaProject.ps1` leaves an existing starter untouched by design and the extension never passes `-Force`, so any future fix to the pull entry point is structurally undeliverable to existing projects | **Low impact** (maintainer, 2026-09-25): ~98% of updates run through *Apply Toolkit*, which bypasses `Start-Pull.ps1` entirely and executes the **fork's** engine. Same "stale forever" class as T-39 — look at both together |

---

## Next — Block 6: upstream (independent track)

| # | Todo |
|---|---|
| **T-15** | One upstream PR finishing the v1.1 → v1.2 migration (`aldc.yaml` line 1, validator banner, catalogs, ~11 doc files) + "superseded" banner on `ALDC-Core-Spec-v1.1.md`. Upstream touched none of them in 27 commits. **Include the `extended` entrypoint mode (D-45)** — the gap is not Aproda-specific |
| **T-16** | **Q-4:** analyse the 27-commit / 340-file / ~47k-line upstream backlog (canonical Spec Agent, Codex bootstrap, BC29/AL18 workflows) *before* the next pull. `basePin` currently claims "in sync", which actively misleads |

---

## Explicitly not doing

| | Why |
|---|---|
| Sweeping the ~22 inherited v1.1 files in the fork | Converts conflict-free files into permanent D-2 merge-points for a defect Aproda did not cause → **Block 6** (upstream PR, T-15) |
| Deleting `.claude/` or `claude-plugin/` | Upstream-owned and actively maintained; deletion guarantees a pull conflict |
| Deleting `.github/agents/test.agent.md` | Confirmed 2026-09-24 (T-10/T-13) to originate from upstream commit `179e782` — same reasoning as `.claude/` |
| Deleting `instructions/copilot-instructions.md` | Q-2 — upstream-maintained, would break the validator and create a delete/modify conflict |
| Releasing before T-7 exists | Would release exactly the state whose verification is still missing |
| **T-37** — fixing `scripts/install.js`'s repo-root `aldc.yaml` write (B-14) | Decided 2026-09-25. Upstream-owned file on the `npx aldc install` channel, which Aproda does not use. A fork fix buys nothing and costs a permanent D-2 merge point — the same merge-economics argument that routed the v1.1 drift to an upstream PR. May ride along with **T-15** if that PR is opened |
| **T-38** — syncing the agent mirrors under `docs/agents/**` and `packages/foundation/agents/**` (B-17) | Decided 2026-09-25. `packages/foundation/**` is already out of E-006's scope per the maintainer; `docs/agents/**` mirrors it. Verified that neither tree reaches a consuming project, so no customer sees the superseded prose. **The mirrors lag by design** |

---

## Recommended order

```
Block 1  T-8, T-9, T-19                                -> commit + push      ✅ done 2026-09-24
Block 2  T-7, T-5, T-6                                 -> commit + push      ✅ done 2026-09-24
Block 3  T-10, T-11, T-13, T-14, T-4                   -> commit + push      ✅ done 2026-09-24
Block 4  T-33, T-22, T-28, T-29, T-24, T-25 → T-35    ✅ implemented 2026-09-25, UNCOMMITTED
Block 4  T-36 (scrape reads the source)                ✅ implemented 2026-09-25 — B-13 fixed
Block 4b T-37, T-38                                    ❌ formally excluded (decided 2026-09-25)
Block 5  T-23, T-21, T-26, T-27, T-34, T-39, T-40     BCQuality part 2 — deferred, latent / nothing depends on them
Block 6  T-15, T-16                                    upstream, parallel at any time
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

**Block 4 status (2026-09-25).** **Implemented, reviewed, uncommitted.** Eight items delivered in the
planned order; 31 files modified and 15 added. Every step was built by one subagent and reviewed by a
separate one, with fixes re-reviewed — that loop caught, among others, a reproduced **data-loss path** in
the migration script (a byte-length emptiness guard accepted a 1-byte `.github/aldc.yaml` and then
deleted the only real config) and a **containment boundary** for the new `#bcquality` tool that held
under an active attack review including a live symlink escape. Three new items (**T-36–T-38**) are
decisions, not tasks — they belong on the agenda before Block 5.
