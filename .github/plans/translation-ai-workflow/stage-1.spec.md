# Stage 1 — Deterministic Resolution: Implementation Specification

**Status:** Ready to implement
**Normative reference:** `translation-architecture-options.md` §4 (target architecture), row "1 —
Deterministic resolution" in §5. This spec does **not** restate architecture decisions — it references
them and specifies only what they leave open: files, functions, parameters, messages and tests. If an
implementation detail here would contradict §4, change §4 first, exactly as stage-0.spec.md required.

**Precondition:** Stage 0 is implemented, validated against a real BC app, and its acceptance criteria
(§8 of `stage-0.spec.md`) are all met. Do not start stage 1 before that baseline correction rate is
captured — §7 of the architecture doc: *"once the deterministic tiers change which units reach the
model, the stage 0 baseline can no longer be obtained."*

---

## 1. Goal

Remove units from the AI workload *before* they reach `ExportOpen`, using only rules over data the
project already has: tier 1 (invariant) and tier 2 (project-derived exact memory). Both are
deterministic, idempotent, and write no new state model — they reuse tiers 0/5's own atomic commit and
§4.8's approval predicate unchanged.

**Deliberately not in this stage** (§5 of the architecture doc):
- Glossary (`invariant` entries, `forbidden` terms) — stage 2. Tier 1 in this stage is therefore **only**
  the "no Unicode letter" condition; the glossary-matched half of tier 1's definition in §4.1 is added in
  stage 2, additively, without touching this stage's code.
- Fuzzy retrieval, in-context examples for AI, ambiguity candidates *attached to the AI batch* — stage 3.
  This stage still *detects* and *reports* ambiguity (§4.7 `ambiguous[]`), it just does not act on it
  beyond leaving the unit for tier 4.
- Shared repository consumption — stage 2/3. Tier 2 here is **project-only**, per P-5: derived from the
  project's own approved XLIFF targets, scanned at run time, never persisted as a second store.

---

## 2. Scope correction to `translation-architecture-context.md` §2 (confirm before starting)

The context doc's "Known gaps in the baseline" table lists *"Conductor says `Sync`, not `Sync
-SkipBuild`"* as an open gap. It is not: stage 0's D8/D9 already wired `Sync -SkipBuild` into both
`al-developer.agent.md` and `al-conductor.agent.md` (verified 2026-09-02). No code or agent change is
needed for this item in stage 1 — only the context doc's gap table needs its status corrected
(sub-cycle 4, alongside the other framework surfaces this stage touches anyway).

`skill-translate` cleanup, also listed there as a gap, was substantially completed by stage 0's D7 (the
legacy patterns are marked reference-only and disclaimed). What remains for stage 1 is additive:
document `Resolve` as a new pipeline step, not a rewrite.

---

## 3. Deliverables

Numbering continues from stage 0 (D1–D12) but is local to this spec; it is not a framework `D-` decision
number.

| # | Path | Action |
|---|---|---|
| D13 | `tools/aproda-ps-xliffsync/Invoke-AprodaBuildXliffSync.ps1` | modify — context class, tier 1, tier 2, `Resolve` action, report `totals`/`ambiguous` |
| D14 | `tools/aproda-ps-xliffsync/test/fixtures/Stage1.g.xlf`, `Stage1.de-CH.xlf` | create — synthetic fixtures for tier 1/2 and context-class parsing |
| D15 | `tools/aproda-ps-xliffsync/test/Invoke-Stage1Tests.ps1` | create — self-contained suite, numbered T1–T*n* (independent of stage 0's numbering, same harness conventions) |
| D16 | `skills/skill-translate/SKILL.md` | modify — document `Resolve` in Pattern 2A and the Workflow section, between `Sync` and `ExportOpen` |
| D17 | `agents/al-developer.agent.md` | modify — invoke `Resolve` after `Sync -SkipBuild`, before the `ExportOpen` loop |
| D18 | `agents/al-conductor.agent.md` | modify — same wording, same place in the sequence |
| D19 | `prompts/al-pr-prepare.prompt.md` | modify — evidence line includes tier counts, unchanged in principle (still evidence-only) |
| D20 | `.github/decisions.aproda.md` | modify — register row for this stage's in-place edits (D-2) |
| D21 | `translation-architecture-context.md` | modify — correct the two stale "known gaps" per §2 above |

No vendor patch, no new agent, no shared-repository access in this stage.

---

## 4. Sub-cycle 1 — Context class and tier 1 (invariant)

Self-contained: no dependency on tier 2. A subagent can implement and unit-test this sub-cycle before
sub-cycle 2 exists.

### 4.1 `Get-AprodaContextClass`

```powershell
function Get-AprodaContextClass {
    param(
        [Parameter(Mandatory)] [XlfDocument]$Document,
        [Parameter(Mandatory)] [System.Xml.XmlNode]$Unit
    )
}
```

Derives the three-part class of §4.2 (`<ObjectType>|<ElementType>|<Property>`) from
`GetUnitXliffGeneratorNote($Unit)`. **Partially confirmed against a real `.g.xlf` (2026-09-02, Gustav
Gerig AG Base)** — a label unit's note reads
`Codeunit Translation Test Mgt - NamedType DeliveryNoteCreatedMsg`: dash-separated (`" - "`, not the
synthetic fixtures' `|`), each segment `<Word> <Name>`, object type / element type are each segment's
**first word**, matching the general shape assumed below. **Still unconfirmed:** whether a *field
property* note (e.g. a table field's `Caption`) carries a third `Property` segment the way §4.2's example
table shows (`Table|Field|Caption`) — the only note verified so far is a `NamedType` (label), which has
**two** segments, not three, because a label has no property to name. Confirm the field-caption case
(three segments vs. two) against the same `.g.xlf` before finalizing the regex; do not assume the
`Table MyTable - Field MyField - Property Caption` shape used below is correct until a field's own note
has been read directly. Note also: the stage-0 fixtures' `c` field passthrough was itself unaffected by
the note format (verbatim passthrough needs no parsing) — the bug found while investigating this
(`Get-AprodaXlfDocument` not setting note designations on most `LoadFromPath` calls, so `c` came back
empty for *every* unit regardless of note format) is already fixed in stage 0's codebase; this stage's
parser only needs to handle the note *content*, not chase a second bug in reading it.

**Contract:**
- Returns a string in the form `ObjectType|ElementType|Property` on success.
- Returns `$null` when the note is empty, missing, or does not parse into three segments — such a unit
  is invisible to tier 2 (never matched, never matched against), but still flows through every other
  tier unaffected. Never throw.
- Object type / element type are the **first word** of their segment (`Table`, `Page`, `Codeunit`,
  `Report`, `Field`, `Action`, `NamedType`, `Label`, …), not the object/element name.

### 4.2 `Test-AprodaInvariant`

```powershell
function Test-AprodaInvariant {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$SourceText)
}
```

`$SourceText -notmatch '\p{L}'` — true when the source contains no Unicode letter (numbers, punctuation,
placeholders, symbols only). This is the **entire** tier 1 condition in this stage; the glossary-matched
half of §4.1's tier 1 definition is stage 2's addition, appended to this same predicate later without
changing its signature.

### 4.3 `Resolve-AprodaInvariantTier`

```powershell
function Resolve-AprodaInvariantTier {
    param([Parameter(Mandatory)] [System.IO.FileInfo[]]$TargetFiles)
}
```

For every unit where `GetUnitNeedsTranslation` is true and the target is empty (i.e. genuinely open, not
merely unapproved): if `Test-AprodaInvariant` on the source is true, write the target equal to the
source and `Set-AprodaUnitState 'translated'` (§4.8's producer table: tier 1 writes `translated`
directly — a no-letter string needs no human review). Collect changes across all target files and commit
them through the **existing** `Invoke-AprodaAtomicXliffCommit` helper from stage 0 (§5.5) — do not write
a second commit mechanism. Returns the count resolved, keyed by target file, for the run report's
`totals.invariant`.

Idempotent: a unit already resolved (target = source, state `translated`) is no longer "open" (target
non-empty) and is skipped on the next run without re-writing.

---

## 5. Sub-cycle 2 — Tier 2 (project-derived exact memory)

Depends on sub-cycle 1 only for `Get-AprodaContextClass` (shared) and the atomic commit helper (shared,
already exists). Independently testable once those two are available.

### 5.1 Normalisation rule (defined here, not left to fuzzy scoring)

Tier 2 is **exact**, not fuzzy (§4.1 draws this line explicitly; fuzzy is tier 3, stage 3). Normalise a
source string for matching as: trim leading/trailing whitespace, collapse runs of whitespace to a single
space. **Do not** case-fold and **do not** mask placeholders — those are tier 3 (§4.3) techniques and
would let `Post %1` and `post %2` collide here, which is unsafe for an auto-applied tier.

### 5.2 `Get-AprodaApprovedMemoryIndex`

```powershell
function Get-AprodaApprovedMemoryIndex {
    param([Parameter(Mandatory)] [System.IO.FileInfo[]]$TargetFiles)
}
```

Scans **every** unit in every target file (not only open ones — an approved unit is memory regardless of
whether other units are still open), keeps those where `Test-AprodaApproved` is true and
`Get-AprodaContextClass` is non-`$null`, and groups them by the key:

```
<normalised source>::<context class>::<placeholder signature>
```

(placeholder signature via the existing `Get-AprodaPlaceholders` joined the same way `Apply` already
does). Returns a hashtable from key to the **distinct set** of target texts seen for that key (order
irrelevant; only cardinality matters to the caller).

Computed fresh on every `Resolve` call — never cached, never written to disk (P-5: derive, do not
duplicate). This keeps the tier correct across manual PoEdit edits without any invalidation logic.

### 5.3 `Resolve-AprodaMemoryTier`

```powershell
function Resolve-AprodaMemoryTier {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo[]]$TargetFiles,
        [Parameter(Mandatory)] [hashtable]$MemoryIndex
    )
}
```

For every unit still open after tier 1 (target empty, needs translation): compute the same key; if the
index has **exactly one** distinct target for that key **and** the target's length fits the unit's
`maxwidth` (when present), write it and `Set-AprodaUnitState 'translated'`. If the key is absent, do
nothing (the unit stays open for tier 3/4). If the key maps to **more than one** distinct target
(ambiguous) or the single candidate fails `maxwidth`, do nothing but record the unit in the
run report's `ambiguous[]` (unitId, candidate count) — never auto-apply, never silently drop it (§4.1:
"Tier 2 explicitly refuses to act when a match is ambiguous"). A unit with no parseable context class
(§4.1's `Get-AprodaContextClass` returned `$null`) can be neither a source nor a target of tier 2 and is
excluded from both the index and resolution — it is not "ambiguous", it simply never reaches this tier's
logic.

Commits through the same atomic helper as tier 1; a single `Resolve` call may commit tier 1 and tier 2
writes together in one multi-file transaction.

### 5.4 `Resolve` action (wrapper wiring)

Add to the `-Action` `ValidateSet`. Behaviour: load target files (same `Get-AprodaTargetFiles` as other
actions), run `Resolve-AprodaInvariantTier`, then rebuild `Get-AprodaApprovedMemoryIndex` from the
**post-tier-1** state (so tier 1's own writes are visible to tier 2 immediately — a unit resolved by
tier 1 can now serve as a memory source, though in practice tier 1 targets equal their source and rarely
recur as free text), then run `Resolve-AprodaMemoryTier`. Persist `totals` (`translatable`, `open` after
both tiers, `invariant`, `memoryExact`) and `ambiguous[]` into the run report (`-ReportPath`, same
default-naming convention as `Apply`/`Report`). Print the one-line evidence format already specified in
§4.7 of the architecture doc. Read from the project's target XLIFF files, but is **not** read-only:
tiers 1 and 2 write, matching §4.6's action table.

`Resolve` must run **after** `Sync` and **before** `ExportOpen` in every caller (§4.1's tier order),
never the reverse — an invariant or memory-resolved unit must not appear in an AI batch.

---

## 6. Sub-cycle 3 — Tests

New, self-contained file `test/Invoke-Stage1Tests.ps1`, same harness conventions as
`Invoke-Stage0Tests.ps1` (`Invoke-Stage0Case` / `Assert-Stage0` helpers may be reused or copied; do not
fork the assertion semantics). Fixtures are synthetic, live beside the tool, no customer XLF committed.

| # | Case | Expected |
|---|---|---|
| T1 | Source with no Unicode letter (`"123-45"`, `"%1"`, `"PDF"`) | tier 1 resolves it: target = source, state `translated` |
| T2 | Source with letters and symbols mixed (`"Item 123"`) | tier 1 does **not** resolve it; stays open |
| T3 | Two approved units share normalised source + context class + placeholder signature with one consistent target; a third open unit has the same key | tier 2 resolves the third unit to that target, state `translated` |
| T4 | Same key as T3, but the two approved units carry **different** targets | the open unit is **not** resolved; appears in `ambiguous[]` with candidate count 2 |
| T5 | A matching memory candidate exceeds the open unit's `maxwidth` | not resolved; stays open (not reported as ambiguous — a single candidate that fails `maxwidth` is a length failure, not an ambiguity) |
| T6 | Same source text, different context class (e.g. `Table\|Field\|Caption` vs `Codeunit\|NamedType\|Label`) | tier 2 does **not** cross-match |
| T7 | Same normalised source and context class, placeholder signatures differ (`"Post %1"` vs `"Post %1 %2"`) | tier 2 does **not** match |
| T8 | A unit whose `Xliff Generator` note is missing or does not parse into three segments | excluded from both the memory index and resolution; still available to `ExportOpen` unchanged |
| T9 | `Resolve` run twice in succession | second run is a no-op; target XLF SHA-256 unchanged after the first run |
| T10 | Injected failure mid multi-file commit during `Resolve` (reuse the stage-0 fault-injection hook) | both tier 1 and tier 2 writes for that call roll back together, byte-for-byte |
| T11 | `Resolve` on a fixture with a known mix of invariant/memory/open units | run report `totals.invariant`, `totals.memoryExact`, `totals.open` match the fixture exactly |
| T12 | `Get-AprodaContextClass` against the **verified real** note format (§4.1) | returns the expected three-part string for `Table`, `Page`, `Codeunit`, `Report` examples |
| T13 | `Get-AprodaContextClass` against an empty/unparseable note | returns `$null`, does not throw |

T9 is the idempotence guard specific to this stage's deterministic tiers (stage 0's T13 already guards
`Apply`'s atomicity; this is the equivalent for `Resolve`). T10 reuses stage 0's injection mechanism
(`APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT`) rather than building a second one. T12 is the regression guard
for the note-format assumption flagged in §4.1 — if the real format differs from what was verified at
implementation time, this test must be updated alongside the parser, not silently left green against a
synthetic shape.

---

## 7. Sub-cycle 4 — Framework surfaces

**D16 `skill-translate`** — insert `Resolve` between `Sync` and `ExportOpen` in Pattern 2A's code block
and in the numbered Workflow section (currently "Step 1: Sync" / "Step 2: Export and translate").
Document the one-line evidence format extension (tier counts) next to the existing approval-gate
evidence line. Do not touch Patterns 1/3/5/6 — they are already correctly disclaimed as reference-only
from stage 0's D7.

**D17/D18 callers** — insert one call between the existing `Sync -SkipBuild` line and the `ExportOpen`
loop in both agents, same wording in both, same pattern the two files already share for the rest of the
Stage 0 sequence (verified identical wording is load-bearing for consistency, not cosmetic).

**D19 `al-pr-prepare`** — extend the existing evidence line format (already documents approval-gate
result and open review count) with tier counts from the run report's `totals`. Still evidence-only,
still never runs the tool — unchanged in principle from stage 0's D10.

**D20 governance** — a single `decisions.aproda.md` register row for the files this stage edits in place,
under the existing D-2 in-place-edit convention stage 0 already used for D7–D12. No new top-level
decision number is needed: this stage does not change any decision already logged in
`translation-architecture-options.md` §7, it only implements what §5's stage table already scoped.

**D21 context doc** — correct the two "known gaps" entries described in §2 above (the `-SkipBuild`
gap is already closed; the `skill-translate` gap is substantially closed by stage 0's D7 and now fully
closed by this stage's D16).

---

## 8. Acceptance criteria

1. All of `Invoke-Stage1Tests.ps1` (T1–T13) pass, and all of stage 0's `Invoke-Stage0Tests.ps1` (T1–T28)
   still pass unmodified — this stage must not regress stage 0.
2. A `Resolve` run against Gustav Gerig AG Base, on the exact 34-open-unit corpus recorded as
   **"Run B"** in `ai-cost-model.md` §5, shows `totals.invariant > 0` and/or `totals.memoryExact > 0` —
   compare directly against that pre-stage-1 baseline (34 open, 0 invariant, 0 memoryExact, correction
   rate 0 %). A corpus with zero reused strings is not a valid demonstration of this stage's value.
3. `Get-AprodaTranslationStatistics` and the approval gate (`Validate -FailOnUnapproved`) are unaffected
   by `Resolve` having run — tier 1/2 write `translated` directly (§4.8), so the gate must pass on a
   fully `Resolve`d project with no AI involvement and no PoEdit pass, which is the whole point of a
   deterministic tier.
4. Running `Resolve` twice in a row produces zero further writes (T9, and confirmed once against the
   same real app as criterion 2).
5. `npm test` green; `git diff --check` clean; no `packages/foundation/**` changes; no vendor file
   touched (this stage needs no vendor patch).
6. The two stale "known gaps" in `translation-architecture-context.md` §2 are corrected (D21).

---

## 9. Open points

| # | Item | Needed by |
|---|---|---|
| 1 | **Partially resolved 2026-09-02** (§4.1): label notes confirmed dash-separated, two segments, first-word-per-segment. **Still open:** confirm whether a field-property note carries a third `Property` segment, using a real field's own `.g.xlf` note (not yet observed) | sub-cycle 1, before T12/T13 are written against a guessed shape |
| 2 | ~~Which real BC app supplies acceptance criterion 2's corpus~~ — **resolved 2026-09-02**: Gustav Gerig AG Base, using the extended 34-open-unit fixture set. Baseline recorded in `ai-cost-model.md` §5 ("Run B"): 34 open, 0 invariant/memoryExact (stage 0 has no tiers), correction rate 0 %. Re-run `Resolve` against this exact corpus once implemented and compare | before closing criterion 2 |

No fallback-model question, no D-number question — both stage-0 open points were specific to that
stage's subagent and its architecture registration, and do not recur here.
