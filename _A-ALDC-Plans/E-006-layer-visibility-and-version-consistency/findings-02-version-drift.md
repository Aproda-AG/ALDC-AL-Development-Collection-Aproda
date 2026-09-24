# Findings 02 — `ALDC Core v1.1` vs `v1.2`: Drift or Design?

> Task 2: *"ALDC itself has Core v1.1 in some places and Core v1.2 in others. Is that deliberate, or is
> it inconsistent? What is your assessment and recommendation?"*
>
> **Verdict: drift, not design — and overwhelmingly *inherited from upstream*.** There is exactly one
> authoritative version — `1.2.0` — and ~24 files that were never migrated. Aproda corrected 2 of them;
> the other ~22 are unmodified ALDC Core content. Only one has real operational consequences.
>
> **Updated 2026-09-23** after auditing the local `main` branch (§3). The upstream comparison changed two
> conclusions: the `aldc-validate` edit was *never applied* (not reverted), and the documentation sweep
> belongs *upstream*, not in the fork.

---

## 1. What is authoritative

[aldc.yaml](aldc.yaml#L4) is unambiguous and is the file every agent is told to consult
(`#aldcConfiguration`, per `.github/copilot-instructions.md`):

```yaml
core:
  version: "1.2.0"
  specFile: "docs/framework/ALDC-Core-Spec-v1.2.md"
```

`docs/framework/ALDC-Core-Spec-v1.2.md` exists and declares its own conformance criteria (line 211).
`docs/framework/ALDC-Core-Spec-v1.1.md` also still exists — correctly, as the historical spec; v1.1 is
referenced by `ALDC-Migration-v1.0-to-v1.1.md` and by ADR-0001, which are historical records and **must
not** be rewritten.

**There is no evidence anywhere of an intentional dual-version scheme.** No document says "v1.1 applies
to X while v1.2 applies to Y". No `aldc.yaml` key expresses a second supported version. The split is
simply an unfinished migration.

## 2. Positive proof that it is recognised drift

[.github/decisions.aproda.md](.github/decisions.aproda.md#L154) (D-17) explicitly names it:

> The drift where `copilot-instructions.md` (and the `aldc-validate` banner) still said "ALDC Core v1.1"
> against `core.version: 1.2.0` was corrected at the same time — a candidate for an upstream PR …

And the D-7 register records two fixes:

| Line | File | Claim | Date |
|---|---|---|---|
| 523 | `copilot-instructions.md` | Drift-fix: "ALDC Core v1.1" → "v1.2" (lines 7 + footer) | 2026-06-25 |
| **524** | **`tools/aldc-validate/index.js`** | **Drift-fix: compliance banner "v1.1" → "v1.2"** | **2026-06-25** |

So the maintainers already classified this as drift and began fixing it. The migration simply stopped
after the entrypoint.

## 3. Where the drift comes from — the `main` comparison

The local `main` branch carries ALDC Core **without** the Aproda layer. Auditing it settles the question
of authorship.

### Distribution on `main` (excluding `archive/`)

| | Occurrences | Files |
|---|---|---|
| `ALDC Core v1.1` | **43** | **24** |
| `ALDC Core v1.2` | 6 | 3 — `CLAUDE.md`, `README.md`, `ALDC-Core-Spec-v1.2.md` |

Upstream carries the v1.2 label in **three files**. Everything else still says v1.1.

### The decisive evidence: `main:aldc.yaml` contradicts itself

```yaml
# ALDC Core Configuration v1.1       <- line 1
core:
  version: "1.2.0"                    <- line 5
  specFile: "docs/framework/ALDC-Core-Spec-v1.2.md"
```

The *values* were migrated to 1.2; the *label* was not — in the same file, upstream. That is the
signature of an abandoned migration, and it is exactly the pattern the fork inherited.

### It is not a transient state

`origin/main` is **27 commits ahead** of the local `main` (340 files, +46 932 / −2 788). Both defects are
still present there:

| File | `main` | `origin/main` | Upstream commits touching it |
|---|---|---|---|
| `aldc.yaml` line 1 | v1.1 | **still v1.1** | 1 (label untouched) |
| `tools/aldc-validate/index.js` | v1.1 | **still v1.1** | **0** |
| `agents/index.md` | v1.1 | still v1.1 | **0** |
| `instructions/copilot-instructions.md` | v1.1 | still v1.1 | 2 (label untouched) |

Nobody upstream is fixing this. Waiting it out is not a strategy.

### What Aproda actually changed

| File | `main` | `aproda` |
|---|---|---|
| `aldc.yaml` line 1 | v1.1 | **v1.2** ✅ (D-17) |
| `.github/copilot-instructions.md` | v1.1 | **v1.2** ✅ (D-17) |
| `docs/copilot-reference.md` | v1.1 | **v1.2** ✅ (2026-09-21/22 session) |
| everything else | v1.1 | v1.1 — untouched upstream content |

**~22 of the ~24 drifted files are unmodified upstream content.** The drift is inherited, not introduced.
This reclassifies most of the remediation as *upstream* work — see §9, R-4/R-5.

## 4. 🔴 The registered fix to `aldc-validate` was **never applied**

This is the sharpest finding of Task 2. Register line 524 claims the validator banner was migrated on
2026-06-25. Current content of [tools/aldc-validate/index.js](tools/aldc-validate/index.js):

| Line | Content |
|---|---|
| 3 | `* ALDC Core Validator v1.1` |
| 4 | `* Validates repository compliance against ALDC Core Spec v1.1.` |
| 295 | `console.log("║     ALDC Core Validator v1.1             ║");` |
| **316** | ``console.log(`✅ ALDC Core v1.1 COMPLIANT (${S.warnings.length} warning(s))`);`` |

**All four still say v1.1.** The `main` comparison (§3) decides between the two possible causes:

```text
aproda:tools/aldc-validate/index.js  ==  main:...         -> identical, byte for byte
aproda:tools/aldc-validate/index.js  ==  origin/main:...  -> identical, byte for byte
```

The file is **pristine upstream content**. It was not edited and later reverted — **the registered edit
was never applied at all**. `tools/aldc-validate/index.js` *is* listed in
[aproda-sync.json](tools/aproda-sync/aproda-sync.json) `inPlaceEdits`, so the fork variant was supposed to
win on every sync; there simply never was a fork variant, and nothing checked.

### Why this matters beyond cosmetics

`tools/aldc-validate` is the **conformance gate**. It is invoked by
`skill-aproda-aldc-release` ("Layer release checks → `tools/aldc-validate` succeeds against the fork
`aldc.yaml`") and by `.github/actions/aldc-validate/action.yml`. A release therefore certifies
`✅ ALDC Core v1.1 COMPLIANT` for a layer whose `aldc.yaml` declares `1.2.0`. **Every release note and CI
log since 2026-06-25 carries a false compliance statement.**

### How unreliable is the register, really? — 20 of 21 are genuine

A full reality-check of every `inPlaceEdits` path against `main` (2026-09-23):

| Result | Count | Paths |
|---|---|---|
| Genuinely differs from upstream (edit is real) | **20** | all 10 agents, 5 prompts, 2 skills, `README.md`, `.github/copilot-instructions.md`, `instructions/al-testing.instructions.md` |
| **Identical to upstream (edit missing)** | **1** | `tools/aldc-validate/index.js` |

The register is therefore **not** fiction — it is accurate for 20 of 21 entries. The defect is *punctual*,
not systemic, and an earlier draft of this document overstated it. What is missing is the *verification
step*, not the discipline: one unverified claim survived ~3 months because nothing ever compared the
register against the tree. That is exactly the "declarative vs falsifiable" distinction the framework
already applies to BCQuality evidence — but never to itself (R-3).

## 5. Full inventory

### ✅ Already v1.2 (correct)

| File | Reference |
|---|---|
| `aldc.yaml` | `core.version`, `specFile` |
| `.github/copilot-instructions.md` | line 7, footer |
| `README.md` | badge (line 20), 405, 463, 546 |
| `docs/copilot-reference.md` | line 1, 123 |
| `CLAUDE.md` | 3, 8, 150, 159, 164 — *version right, primitive counts wrong (see §7)* |
| `.github/onboarding.aproda.md` | line 174 |
| `docs/framework/ALDC-Core-Spec-v1.2.md` | self |

### ❌ Still v1.1 — operational (fix required)

| File | Line(s) | Impact |
|---|---|---|
| **`tools/aldc-validate/index.js`** | 3, 4, 295, 316 | **False compliance statement in every CI run and release** (§4) — *inherited from upstream* |
| **`.github/actions/aldc-validate/action.yml`** | 2 | Action description; surfaces in GitHub UI. Not in the D-7 register at all |
| **`instructions/copilot-instructions.md`** | 7, 285, 313, 333 | Declared `copilotSource` (F-6); **syncs to every project** via `aldc.yaml → required.instructions` |
| **`agents/index.md`** | 5 | Catalog header; also stale in content (F-5) |
| **`collections/al-development.collection.yml`** | 4 | Collection manifest description |
| **`scripts/install.js`** | 4, 189, 213, 383, 458, 516 | Installer banner + component map |

### ❌ Still v1.1 — documentation (fix opportunistically)

`docs/getting-started.md` (3, 36, 135) · `docs/al-development.md` (189, 213, 220, 230) ·
`docs/index.md` (403) · `docs/index-es.md` (322) · `docs/bc-agent-builder.md` (73) ·
`docs/instructions/copilot-instructions.md` (20) · `docs/framework/ALDC-Architecture-Diagrams.md`
(3, 9, 218) · `docs/framework/ALDC-Compliance-Model.md` (5) · `docs/framework/ALDC-Manifesto.md` (8) ·
`docs/framework/QUICKSTART.md` (1, 5, 72)

### ⚪ Legitimately v1.1 — historical, do **not** touch

| File | Why |
|---|---|
| `docs/framework/ALDC-Core-Spec-v1.1.md` | The v1.1 spec itself |
| `docs/framework/ALDC-Migration-v1.0-to-v1.1.md` | Historical migration guide |
| `docs/decisions/ADR-0001-apm-phase-1-restructure.md` (21, 128, 349, 350) | ADR — records the state at decision time |
| `.github/plans/claude-plugin-tool-modernization.md` (88) | Historical plan record |

### ⚫ Out of scope (maintainer instruction)

`packages/foundation/**` — `agents/index.md` (5) and `instructions/copilot-instructions.md`
(7, 285, 313, 333) carry the same drift. Listed for completeness only.

> **Ownership column.** Every file in the two ❌ tables above except `.github/copilot-instructions.md`
> is **unmodified upstream content** (§3). Read the tables as *"what is wrong"*, not as *"what Aproda
> should edit"* — the routing is decided in §9.

## 6. Why the drift persists — the structural cause

The same root cause as Findings 01 § F-7: **nothing checks it.**

- `aldc-validate` validates *file existence* and *AL naming*, never *version strings*.
- Ironically, the validator is itself one of the drifted files — it cannot flag its own banner.
- `validation.rules` in `aldc.yaml` has no rule for version coherence, though it already has the right
  pattern (`copilotEntrypointCoherence: "warn"`).

A one-line validator rule — *"every `ALDC Core vX.Y` literal outside `docs/framework/ALDC-Core-Spec-*.md`,
`ALDC-Migration-*.md`, `docs/decisions/**` and `.github/plans/**` must equal `core.version`'s major.minor"*
— would have caught all 20 occurrences on the day they drifted.

## 7. Adjacent inconsistency: primitive counts (not a version issue, same failure mode)

Even files carrying the **correct** v1.2 label state wrong primitive counts:

| File | States | Actual (this repo) |
|---|---|---|
| `CLAUDE.md` lines 8, 164 | 10 agents · 16 skills · 11 workflows · 9 instructions | 11 · 21 · 12 · 10 |
| `instructions/copilot-instructions.md` line 7 | 4 agents · 11 skills · 6 workflows · 7 instructions | 11 · 21 · 12 · 10 |
| `.github/copilot-instructions.md` line 7 | 11 · 21 · 12 · 10 ✅ | corrected in the 2026-09-21/22 session |

`CLAUDE.md` is Claude Code's entrypoint — out of scope as a *runtime*, but it sits at the repo root and is
read by humans; leaving a contradictory count there is a documentation hazard.

## 8. Assessment

**It is inconsistent, not intentional**, it is *already acknowledged* in D-17, and it is *mostly not
Aproda's*. Three distinct problems are entangled:

1. **An unfinished upstream migration** (~22 inherited files) — low individual severity, high cumulative
   confusion. New contributors cannot tell which version governs. **Not Aproda's to fix in-place.**
2. **A false compliance signal** (`aldc-validate`) — also inherited, but the only finding with real
   consequences *for Aproda*, because `skill-aproda-aldc-release` treats this binary as a release gate.
3. **One unverified register entry** — D-7 line 524 documents an edit that was never made. Punctual
   (1 of 21), but it survived ~3 months undetected.

Problem 3 is the most transferable lesson: **an in-place-edit register that is never diffed against the
upstream base cannot distinguish "edit applied" from "edit forgotten".** The framework already knows this
pattern — it built `validate_evidence.py` + the `bcquality-evidence` CI workflow precisely to make
BCQuality citations *falsifiable* rather than *declarative*. The same treatment was never applied to its
own register (R-3).

Problem 1 carries the strategic consequence: because the drifted files are **clean upstream content**,
fixing them in the fork would convert ~22 conflict-free files into ~22 permanent merge conflicts — D-2
makes every in-place edit a deliberate merge-point, and paying that price for someone else's defect is a
bad trade.

## 9. Recommendation

The `main` comparison (§3) splits the work into two tracks that must not be mixed.

### Track A — fix in the fork (Aproda-owned consequences)

| # | Action | Priority |
|---|---|---|
| **R-1** | Fix `tools/aldc-validate/index.js` (4 occurrences) + `.github/actions/aldc-validate/action.yml`. **Correct** register line 524 — do not "re-affirm" it; it documents an edit that never happened. Add the missing `action.yml` row. *Why fork an upstream file here:* the binary is the release gate in `skill-aproda-aldc-release`, so the false banner has a concrete Aproda cost that cannot wait on an external maintainer. | 🔴 now |
| **R-2** | Add a `versionCoherence` rule to `aldc-validate`. **Scope it to Aproda-owned paths first** (`*.aproda.*`, `skill-aproda-*/**`, `.github/copilot-instructions.md`, `aldc.yaml`) and allowlist the inherited upstream files — otherwise it reports ~22 failures Aproda must deliberately *not* fix (R-4/R-5). Historical paths per §5 stay permanently allowlisted. | 🔴 now |
| **R-3** | Add **register verification** to `skill-aproda-aldc-release`: before a layer release, diff each `inPlaceEdits` path against the pinned upstream base. *A path byte-identical to upstream means the registered edit is missing.* This is exactly the check that would have caught R-1 in June. | 🟠 next |
| **R-6** | Correct `aldc.yaml → aproda.basePin`. It claims `a900263…` with the comment *"upstream == fork, in sync 2026-06-25"*, but the real merge-base is **`4f3371f`** and `origin/main` is 27 commits further ahead. Neither the pin nor the "in sync" claim holds. | 🟠 next |
| **R-7** | Correct the primitive counts in `.github/copilot-instructions.md` (done in the session) and decide whether `CLAUDE.md` is maintained at all — Aproda does not use Claude Code as a runtime, yet the file sits at the repo root and contradicts the entrypoint. | 🟡 later |

### Track B — propose upstream (inherited; do *not* fix in the fork)

| # | Action | Priority |
|---|---|---|
| **R-4** | **Do not sweep `instructions/copilot-instructions.md`, `agents/index.md`, `collections/al-development.collection.yml`, `scripts/install.js` in the fork.** All four are unmodified upstream files (§3). Editing them in place converts four conflict-free files into four permanent merge-points (D-2) and adds four rows to the D-7 register — for a defect Aproda did not cause. Open an **upstream PR** instead; D-17 already calls this "a candidate for an upstream PR". | 🟠 next |
| **R-5** | Same for the ~11 documentation files (§5). Bundle them with R-4 into **one upstream PR** that finishes the v1.1 → v1.2 migration, including `aldc.yaml` line 1 and the validator banner. Upstream has touched none of them in 27 commits, so the PR should apply cleanly. | 🟡 later |
| **R-8** | In the same upstream PR: add a *"Superseded by ALDC-Core-Spec-v1.2.md — retained for ADR-0001 and the v1.0→v1.1 migration guide"* banner to `ALDC-Core-Spec-v1.1.md`. **Do not delete it.** | 🟡 later |

### Sequencing note

R-1 and R-4/R-5 overlap on `tools/aldc-validate/index.js`. If the upstream PR lands, the fork's edit
becomes redundant and should be dropped from `inPlaceEdits` at the next pull — one fewer merge-point.
Until then the fork edit stands, because the release gate cannot wait on an external maintainer. Record
this as the explicit exception when adding the register row, so a later reviewer does not "clean it up"
without checking the upstream PR status.

### One explicit non-recommendation

Do **not** "solve" this by declaring a dual-version scheme. There is no technical basis for one, and it
would legitimise the drift instead of closing it. `aldc.yaml → core.version` is and should remain the
single source of truth.
