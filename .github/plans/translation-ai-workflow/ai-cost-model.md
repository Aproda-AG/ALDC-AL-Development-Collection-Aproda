# AI Cost Model and Token Learnings

**Date:** 2026-09-01
**Scope:** Reusable across ALDC — not specific to the translation workflow. Currently filed under
`translation-ai-workflow/` because it originated there; move when a better home exists.
**Source:** [GitHub Copilot — Models and pricing](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)

> Billing is **token-based (AI credits)**, not premium requests with a model multiplier.
> Token counts therefore translate directly into cost.

---

## 1. Prices

USD per 1M tokens.

| Model | Input | Output | Output / Input |
|---|---|---|---|
| Claude Opus 5 | $5.00 | $25.00 | 5× |
| Claude Sonnet 5 | $2.00 | $10.00 | 5× |
| GPT-5.6 Terra | $2.00 | $12.00 | 6× |
| **GPT-5.6 Luna** | **$0.20** | **$1.20** | 6× |

Recent generational changes: Sonnet 4.6 → 5 −33 %; GPT-5.4 → 5.6 Terra −20 %; GPT-5.4 mini → 5.6 Luna −73 %.

### Derived ratios

| Comparison | Input | Output |
|---|---|---|
| Luna vs Terra | **0.10** | **0.10** |
| Luna vs Sonnet 5 | 0.10 | 0.12 |
| Luna vs Opus 5 | 0.04 | 0.05 |

**Cost formula:** `cost = (in_tokens × p_in + out_tokens × p_out) / 1e6`

---

## 2. Cost anatomy

Output costs **5–6× input across every model**. Whether that dominates depends on volume ratio:

> Output dominates total cost whenever `out_tokens > in_tokens / 6`.

Agentic work with a large context and a short answer is input-dominated. **Generative work with
structured per-item output is output-dominated** — and that case is easy to miss.

### Worked example — XLIFF translation run

3 000 translatable units, 600 open. Prices are exact; token figures are structural estimates.

**The current message carries nine fields per unit, four of which the model has no use for** — `Key`,
`UnitId`, `TargetFileIndex` and a 64-character `SourceHash`. Together with repeated JSON field names
that is roughly **120 tokens per unit**, of which only about a third is translation-relevant. A lean
view (`k`, `s`, `c`, `m`) lands near 40.

| Stage | In | Out | Model | Cost | Index | Review items |
|---|---|---|---|---|---|---|
| current (verbose contract) | 72 000 | 21 000 | Terra | **$0.396** | 100 | 600 |
| 0 — cheap model + lean contract | 24 000 | 9 600 | Luna | **$0.016** | 4 | 600 |
| 1 — deterministic resolution | 7 200 | 2 880 | Luna | **$0.005** | 1.2 | 180 |
| 2 — glossary context | 9 900 | 2 880 | Luna | **$0.005** | 1.4 | 180 (fewer corrections) |
| 3 — fuzzy retrieval | 7 650 | 1 440 | Luna | **$0.003** | 0.8 | ~90 |

**Decomposing stage 0** — the two changes are independent and multiply:

| Change | Cost | Factor |
|---|---|---|
| current | $0.396 | 1× |
| model swap only (Terra → Luna) | $0.040 | 10× |
| contract lean only (still Terra) | $0.163 | 2.4× |
| **both** | **$0.016** | **24×** |

At stage 1, **70 % of the cost is output** — the response, not the batch.

### The number that actually matters

| | Model cost | Human review (15 s/item, CHF 120/h) |
|---|---|---|
| current | ~CHF 0.36 | 2.5 h ≈ **CHF 300** |
| stage 1 | ~CHF 0.004 | 45 min ≈ **CHF 90** |
| stage 3 | ~CHF 0.003 | 22 min ≈ **CHF 45** |

**Human attention outweighs model cost by roughly a factor of 1000.**

---

## 3. Learnings

**L1 — Model tier is a 10× lever, on both axes.**
Luna costs one tenth of Terra for input *and* output. High-volume mechanical work belongs on the cheap
tier whenever correctness is enforced outside the model.

**L2 — Design the message contract in both directions.**
What the receiver does not need does not belong in the message.

*Input — separate the model's view from the tool's bookkeeping.* Validation fields, internal
identifiers and file indices are for the tool, not the model. Emit two artefacts: an AI view the
subagent reads, and a manifest only the applying code reads. A 64-character hash costs ~20 tokens per
item and buys the model nothing.

*Output — never echo the input.* Output is 5–6× the input price, so response design matters more per
token than prompt design. A long correlation key can easily exceed the payload it labels:

```json
{ "key": "0:Table 2328808854 - Field 1 - Property 2879900210", "target": "…" }   ← key ≫ payload
{ "k": "7-a3f", "t": "…" }                                                      ← ~50 % less output
```

**Prefer an ordinal plus a check fragment over either extreme.** `7-a3f` is the ordinal plus the first
hex characters of a hash the tool already computes. It is ~4× cheaper than a full identifier and
*stronger* than a bare ordinal: a shifted or corrupted ordinal silently hits a valid neighbour, whereas
a mismatched check fragment fails hard (collision odds 1:4096 for three characters). Combined with a
completeness rule — exactly the ordinals `1…N`, each once — this detects drop, duplication and shift.

Avoid *semantic* short keys (`7:Posting`): the item already carries its source text, so the key needs
no meaning, and a natural-language key invites the model to translate it — costing a whole rejected
batch. An opaque fragment is not tempting.

**L3 — Check the volume ratio before optimising.**
Trimming input is pointless when `out > in / 6`. Measure both directions first.

**L4 — At ALDC volumes, token cost is not a business case.**
Whole runs cost cents. Optimise for human attention, context budget and correction rate. Quote token
savings as a side effect, never as the justification.

**L5 — Context isolation is usually worth more than the price difference.**
Delegating to a subagent keeps bulk payloads out of the orchestrator's window. That protects the
scarce resource, and the cost saving comes along for free.

**L6 — Deterministic pre-resolution pays on both axes at once.**
Every item resolved by a rule or an exact match disappears from the token bill *and* from the review
queue. This is the only lever that reduces the expensive resource.

**L7 — More context per item can lower total cost.**
Adding glossary terms or examples raises tokens per item but reduces item count and correction rate.
Judge cost per *accepted result*, not per request.

**L8 — Routing decisions are script rules.**
With a 10× tier ratio, a model call to decide whether to make a model call can never pay for itself.
Route on data the pipeline already computed.

**L9 — Correctness belongs in deterministic code, not in the model tier.**
When a script validates the output completely, a weaker model cannot corrupt state — the worst case is
a rejected batch. That is what makes L1 safe.

---

## 4. Caveats

- Prices change; re-check the source before relying on the ratios.
- Token counts above are **structural estimates from the message shape**, not measurements. The first
  version of this document understated the current state by ~2.5× because it ignored bookkeeping
  fields and repeated JSON field names. Instrument a real run before quoting figures externally.
- A cheaper contract and a cheaper model are independent factors and multiply. Evaluate them
  separately, or the wrong one gets the credit.
- Cheaper models are weaker at register, idiom and disambiguation. Those failures are *not*
  machine-detectable and must be covered by context (L7) or review.
- The CHF figures assume 15 s per review item; calibrate against actual correction rates.

---

## 5. Measured baselines (real runs, for comparison against stage 1)

Unlike §2's structural estimates, these are **actual** `Validate`/`Report` outputs from the same real
app (Gustav Gerig AG Base), recorded so a stage 1 run against the *same* corpus can be compared
before/after the deterministic tiers exist. Record the app's total/open counts at measurement time,
because both change as fixtures are extended.

### Run A — 2026-09-02, 20-unit fixture set (first round-trip)

- Corpus at the time: 3860 translatable units total, 20 open (first version of the test fixtures).
- `ExportOpen` → subagent (`AL Translation Subagent`, `GPT-5.6 Luna`) → `Apply`: 20/20 applied, 0
  rejected.
- Pre-review `Validate`: 20 `needsReview`, 0 `missing`.
- Post-review (PoEdit pass) `Report`: 18 accepted, 2 corrected, 0 pending, 0 stale —
  **correction rate 0.1 (10 %)**. The 2 corrections were both `Hans Maßrichter` → the subagent had
  written `ss` per the de-CH rule; a human reviewer restored `ß` because it is a proper noun.

### Run B — 2026-09-02, 34-unit fixture set (extended fixtures, stage 1/2/3 test material)

Corpus after extending the AL source fixtures (§ this repo's `stage-1.spec.md` test-fixture work):
3874 translatable units total, 34 open (the fixture extension's new units).

- `Sync` → `ExportOpen -MaxItems 80` (cap unused; only 34 were open) → subagent → `Apply`: **34/34
  applied, 0 rejected**.
- Anomaly, non-impacting: the subagent's own one-line chat summary said `translated 35/35`, but the
  written `response.json` contained the correct 34/34 entries matching the batch exactly. `Apply`'s
  completeness check (exact ordinals `1…N`, each once) does not trust that summary at all — it re-derives
  the count from the response file itself, so the wrong spoken number had no effect on the applied data.
  This is the design working as intended (L9): the model's self-report is not a source of truth anywhere
  in the pipeline.
- Pre-review `Validate`/XML check: 3874 units, 0 missing, 34 `needsReview`, no BOM, correct namespace.
- Post-review (PoEdit pass) `Validate -FailOnUnapproved`: 0 missing, 0 needsReview, 3874 valid, 0
  unapproved, gate **passed**, exit 0.
- Post-review `Report`: **34 accepted, 0 corrected, 0 pending, 0 stale — correction rate 0 (0 %)**.
- 2 pre-existing `ß` warnings remain in unrelated, previously-approved units (down from 4 before Run A's
  PoEdit pass fixed two) — outside this batch's scope, not blocking (`-FailOnIssues` not set).

**Reading these two together:** correction rate varies a lot at n = 20/34 (10 % vs 0 %) — both samples
are too small to treat as *the* correction rate; they are two data points, not a trend. What is stable
across both: `Apply`'s validation caught everything it is designed to catch, no XLIFF corruption
occurred, and PoEdit round-tripped cleanly both times.

**Use for stage 1:** this fixture set (34 open units, deliberately containing the invariant/ambiguity/
glossary-overlap/fuzzy-pair cases from `stage-1.spec.md`) is the intended pre-stage-1 baseline referenced
in that spec's §9 open point 2. Re-run `Resolve` against this exact corpus once stage 1 exists and
compare `totals.invariant` / `totals.memoryExact` against the "34 open, 0 invariant, 0 memory" baseline
implied here (stage 0 has no such tiers, so every open unit reached AI).

### Run C — 2026-09-02, second-wave duplicates (real tier-2 exact-reuse candidates), re-run after the note-designation fix

After Run B, its 34 units were `translated`/approved, so a second wave of 7 fields/labels was added to
the AL source, each reusing the exact source + context class of an already-approved unit from Run B
(`Second Release`, `Alt Posting Date`, `Third Description`, `ReleaseStatusAltTxt`,
`CustomerNotFoundAltErr`, `SecondReleaseAction`, plus its `ToolTip`) — this is the corpus that turns
tier 2 into a real, non-trivial win instead of a first-occurrence no-op (see the analysis that led to
this second wave, above §9's open point 2 discussion). This run used the fixed tool (`c` field populated
— see "second finding" below) and is the version to treat as the recorded stage 0 result; the earlier
same-day attempt with the empty-`c` bug is superseded by it.

- New batch, after the fix was deployed to the project's tool copy: `393582c6-f7fa-4390-a9df-9f1e23f7da8f`.
- `Sync` → `ExportOpen -MaxItems 80` → subagent → `Apply`: **41/41 exported, translated and applied, 0
  rejected**. Technical response check passed (batch ID, key order, no `ß`).
- Pre-review `Validate`: 3881 units, 0 missing; 43 units in review (41 from this batch + 2 pre-existing,
  unrelated).
- Post-review (PoEdit pass) **strict** `Validate -FailOnIssues -FailOnUnapproved`: 3881/3881 valid, 0
  missing, 0 needsReview, 0 unapproved, 0 technical issues, gate **passed**, exit 0.
- Post-review `Report`: **41 accepted, 0 corrected, 0 pending, 0 stale — correction rate 0 (0 %)**.
- Base app build: succeeded, 0 warnings.
- 2 pre-existing `ß` warnings remain (unchanged from Run B), unrelated to this batch, non-blocking.
- Evidence saved: `evidence/run-c-batch.ai.json`, `run-c-batch.manifest.json`, `run-c-response.json`,
  `run-c-report.json` (all four artefacts of this run; supersede the earlier, pre-fix `run-c-batch.ai.json`).

**The 41-vs-7 anomaly, now fully explained from the manifest.** Cross-referencing `evidence/run-c-batch.manifest.json`'s
`unitId`s against the batch's `c` (context) values shows the 41 open units are **exactly** every
translatable unit belonging to the three touched AL objects — `Codeunit 4157415965` ("Translation Test
Mgt", 18 units), `PageExtension 4123091762` ("Item Card Transl. Test", 10 units), `TableExtension
3276313895` ("Item Translation Test", 13 units) — 18 + 10 + 13 = 41 exactly. This includes units that
predate *all* of today's fixture work (`Region Responsible`, `Translation Remark`, `Run Translation
Test`) and units approved earlier the same day in Run B (`CustomerNotFoundErr`, `ReleaseStatusTxt`,
`PostingDateLbl`, …) — not a mix of "new + a few stale leftovers", but the **entire** translation surface
of these three objects, every time. The earlier duplicate-file hypothesis is confirmed disproven (only
one copy of each fixture file exists). Practical consequence for future test-corpus planning: editing
any of these three specific AL objects reopens their whole translation surface for review, not just the
newly added units — realistic for "this object changed, re-review it", but it means a stage-1 comparison
against this corpus must count `totals.memoryExact` against *all 41*, not just the 7 intentionally
duplicated ones, when judging whether tier 2 resolved the right subset.

**Second finding — confirmed as a real script bug, now fixed.** The first same-day attempt at this run
had every item carrying `"c": ""`. This was **not** an empty note in the real project — a raw excerpt of
the actual `.g.xlf` confirmed a correctly populated
`<note from="Xliff Generator">Codeunit Translation Test Mgt - NamedType DeliveryNoteCreatedMsg</note>`.
The bug was in `Invoke-AprodaBuildXliffSync.ps1`: every direct `[XlfDocument]::LoadFromPath(...)` call
outside the two vendor functions (`Sync-XliffTranslations`, `Test-XliffTranslations`) left
`developerNoteDesignation`/`xliffGeneratorNoteDesignation` unset, so every note lookup silently matched
nothing. Fixed by routing all five call sites through a new `Get-AprodaXlfDocument` helper that sets both
designations after loading; regression-guarded by Stage0 test T29 (`ExportOpen`'s `c` field must equal the
fixture's actual note). This re-run, using the fixed tool copy, confirms the fix: every one of the 41
items in `evidence/run-c-batch.ai.json` now carries its real, non-empty context note. This was more
consequential than the duplicate-count anomaly above: without the fix, `Get-AprodaContextClass`
(`stage-1.spec.md` §4.1) would have seen an empty note on **every** unit in **every** real project, not
just this one, and tier 2 would never have resolved anything anywhere.

**Third finding — the real `Xliff Generator` note format, now confirmed for both cases stage-1.spec.md's
open point 1 needed.** From this run's batch:
- **Codeunit label (`NamedType`), two segments, no `Property`:** `Codeunit Translation Test Mgt -
  NamedType CustomerNotFoundAltErr` — a label has nothing to name a property after.
- **Field/control/action, three segments, explicit `Property <Name>`:** `TableExtension Item Translation
  Test - Field Region Responsible - Property Caption` and `PageExtension Item Card Transl. Test - Action
  ReleaseAction - Property ToolTip`.
- Separator is `" - "` (space-dash-space); each segment is `<Word> <Name>`, and the object-type word for
  an *extension* object is the extension type itself (`TableExtension`, `PageExtension`), not the base
  type (`Table`, `Page`) `translation-architecture-options.md` §4.2's example table shows — a base
  object's own field (never seen in this project, which only ships extensions) would presumably read
  `Table|Field|Caption`, but that is unverified; every note observed so far is from an extension object.
