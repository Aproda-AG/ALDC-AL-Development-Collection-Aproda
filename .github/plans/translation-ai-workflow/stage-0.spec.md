# Stage 0 — Delegated Execution: Implementation Specification

**Status:** Implemented and validated — all acceptance criteria (§8) met against a real BC app, 2026-09-02
**Normative reference:** `translation-architecture-options.md` §4 (target architecture). This spec does
**not** restate architecture decisions — it references them and specifies only what they leave open:
files, functions, parameters, messages and tests. If an implementation detail here would contradict §4,
change §4 first.

---

## 1. Goal

Move tier-4 translation out of the orchestrating agent into a subagent on a cheap model, put the
message contract on a diet, and make the correction rate measurable — because that number decides how
much stage 2 is worth.

**Deliberately not in this stage:** invariant tier, memory reuse, glossary, fuzzy retrieval, shared
repository. Those are stages 1–3.

---

## 2. Scope corrections to §5 (confirm before starting)

Working through the detail surfaced three items whose stage assignment in §5 is wrong. All three are
*prerequisites* for stage 0 to be correct, not scope creep.

| Item | §5 says | Why it must be in stage 0 |
|---|---|---|
| Correct state classification | stage 1 | Stage 0 writes `needs-review-translation`. The unextended vendor enum maps it to `MissingTranslation` (C-11), so statistics would report translated units as *missing* — corrupting exactly the numbers stage 0 exists to produce. Resolved by the §5.8 vendor patch. |
| `-MaxItems` + continuation | stage 1 | `ExportOpen` is unbounded today. With 600 open units the batch does not fit one subagent turn, making stage 0 unusable beyond toy apps. |
| Approval gate (`-FailOnUnapproved`) | stage 1 | Decision 14 states the gate is blocking **from stage 0**. Without it, §5's own claim that review is a blocking delivery condition from stage 0 does not hold. |

**Consequence for the stage split.** Stage 0 becomes *"delegated execution, correct contract,
measurement infrastructure"*; stage 1 becomes *"deterministic resolution tiers"* (invariant tier,
memory exact reuse, `Sync -SkipBuild`, `skill-translate` cleanup). That is a cleaner boundary than the
current one — but it is a change, so §5 needs updating alongside this spec.

---

## 3. Deliverables

| # | Path | Action |
|---|---|---|
| D1 | `agents/al-translate-subagent.aproda.agent.md` | create |
| D2 | `tools/aproda-ps-xliffsync/Invoke-AprodaBuildXliffSync.ps1` | modify |
| D3 | `tools/aproda-ps-xliffsync/vendor/XliffSync/Model/XlfDocument.ps1` | **patch** — extend the state vocabulary (§5.8) |
| D4 | `tools/aproda-ps-xliffsync/UPSTREAM.md` | record the patch |
| D5 | `tools/aproda-ps-xliffsync/test/fixtures/**` | create |
| D6 | `tools/aproda-ps-xliffsync/test/Invoke-Stage0Tests.ps1` | create |
| D7 | `skills/skill-translate/SKILL.md` | rewrite Pattern 2A to the new contract |
| D8 | `agents/al-developer.agent.md` | invoke the subagent; states; PoEdit |
| D9 | `agents/al-conductor.agent.md` | register the subagent; same wording |
| D10 | `prompts/al-pr-prepare.prompt.md` | approval-gate evidence |
| D11 | `.github/decisions.aproda.md` | D-32 (final wording) + register row |
| D12 | `tools/aproda-sync/aproda-sync.json` | register `skills/skill-translate/SKILL.md` as in-place edit |

D7–D12 replace the uncommitted work currently sitting in the working tree.

---

## 4. D1 — Translation subagent

```yaml
---
name: AL Translation Subagent
description: 'Translates a prepared XLIFF batch into the target language and writes the response file. Invoked by al-developer or al-conductor; never by the user.'
user-invocable: false
disable-model-invocation: true
argument-hint: 'Absolute path to batch.ai.json and the response path to write'
tools: [read/readFile, edit/createFile, edit/editFiles]
model: <cheap model> (copilot)
---
```

No `handoffs:` block — unlike the existing subagents this one has **two** callers, so a fixed handoff
target would be wrong (§4.9).

**Body requirements:**

- Identity: translate only; make no decisions about files, states or workflow.
- Input: `batch.ai.json` only. It never reads the manifest, the XLF files, or the project.
- Output: write the response file itself; return a **one-line summary** (`translated N/N items`), never
  the JSON. Returning the payload through the result message destroys the context isolation that is
  the point of this stage.
- Contract: response shape per §4.4. Copy `k` verbatim; never invent, reorder, drop or add keys.
- Rules to state explicitly, because they are the cheap model's known failure modes (§4.9):
  - Swiss German uses **no `ß`** — always `ss`.
  - Preserve placeholders (`%1`, `%2`, `#1###`, `@1@@@`) exactly, in the same order.
  - Respect `m` (max length) when present.
  - Translate every item; return exactly the ordinals supplied.
- Boundary rule: *"return results to the calling agent"* — not "to the Conductor".

---

## 5. D2 — Wrapper changes

### 5.1 Parameters

```powershell
[ValidateSet('Sync','ExportOpen','Apply','Validate','Report')]  # + Report
[string]$Action = 'Sync'

[int]$MaxItems = 30          # 0 = unbounded; see §5.9
[int]$Offset = 0             # continuation
[string]$ManifestPath        # defaults beside -BatchPath
[string]$ReportPath          # defaults to <AppPath>/.aproda/translation/.cache/run-<runId>.json
[switch]$FailOnUnapproved
```

### 5.2 New helpers

State handling goes **through the extended vendor enum** (§5.8), not through a parallel raw-attribute
reader. One reading path, not two.

| Function | Purpose |
|---|---|
| `Test-AprodaApproved` | Approved when the target has text and either no `state` attribute at all (legacy corpora, amended 2026-09-02, §4.8), or `$document.GetState($unit) -eq [XlfTranslationState]::Translated`. Any *present* state value other than `Translated` is not approved. |
| `Set-AprodaUnitState` | Write a state the vendor's `SetState` can now express. Use `SetState` to create a missing `<target>` node first. |
| `Test-AprodaSwissOrthography` | `$text -notmatch 'ß'`. Used by both `Apply` and `Validate` (§4.9). |
| `Get-AprodaShortKey` | `'{0}-{1}' -f $ordinal, $sourceHash.Substring(0,3)`. |
| `Write-AprodaRunReport` | Serialise the run report (§4.7) to `-ReportPath`. |

### 5.3 `Get-AprodaTranslationStatistics`

Classify per unit:

| Condition | Bucket |
|---|---|
| no target text | `missing` |
| text, `Test-AprodaApproved` | `approved` |
| text, not approved | `needsReview` |

The current implementation counts a `needs-review-translation` unit with text as `missing`, because it
tests `GetState -eq MissingTranslation` directly. **This table alone fixes that** — text presence is
checked first, and the fallback value is simply ≠ `Translated`, so the unit lands in `needsReview`. The
§5.8 vendor patch is defence in depth, not the fix.

### 5.4 `Export-AprodaOpenTranslations`

- Enumerate open units as today; apply `-Offset` then take `-MaxItems` (0 = all).
- Emit **two** files per §4.4: `batch.ai.json` and `batch.manifest.json`.
- `k` = `Get-AprodaShortKey` with the ordinal being the 1-based index **within this batch**.
- `c` (context) carries the **XLIFF generator note verbatim** — it is the most informative context for
  the model and needs no derivation. The normalised context class of §4.2 is a *matching* key for tier 2
  and is not needed here.
- `d` (developer note) only when non-empty; omit the field otherwise.
- `m` only when a `maxwidth` exists.
- Report `remaining` so the caller knows whether to continue: `total open − (offset + emitted)`.

### 5.5 `Apply-AprodaTranslations`

Validation order is normative in §4.4. Implementation notes:

- Read both artefacts; fail if the manifest is missing or its `b` differs from the response.
- Parse `k` as `^(\d+)-([0-9a-f]{3})$`; a non-matching key is a hard failure.
- **Complete coverage**: the response must contain exactly the ordinals `1…N`, each once. Missing,
  duplicate or out-of-range ordinals all reject the batch.
- Compare `hash3` against the manifest entry's `srcHash` prefix. A mismatch means the model shifted its
  numbering — reject, and name the offending ordinals in the error.
- Run `Test-AprodaSwissOrthography` on every target; reject and list the offending ordinals.
- Existing checks unchanged: unit still exists, source hash current, placeholder signature, `maxwidth`,
  non-empty target.
- On success write the target text and `Set-AprodaUnitState 'needs-review-translation'` — never
  `translated` (§4.8).
- Append the applied items to the run report as `ai[]` with `k`, `unitId` and the written `target`.
  Without this the correction rate cannot be reconstructed later (§4.7).

Atomicity is unchanged: validate everything, then write. Any failure leaves every target file
byte-identical.

**Multi-file commit.** Validation-time atomicity is not sufficient — a batch can span several XLIFF
files, and saving them sequentially to their live paths leaves the earlier ones changed if a later save
fails. This is realistic here because PoEdit may hold a file open. Write every changed document to a
temporary file on the same volume first, then replace the targets, and roll back any target already
replaced if a later replacement fails. Record the apply as successful only after the commit completes.

### 5.6 `Invoke-AprodaXliffValidation`

- Add the `ß` rule as a reported finding (not a throw) so pre-existing and manually entered text is
  caught too.
- Add the approval gate: when `-FailOnUnapproved` is set, any translatable unit whose state is not
  `translated` fails the run. Script-only, no AI (§4.6).
- `-FailOnIssues` and `-FailOnUnapproved` are independent switches.

### 5.7 `Report` action

Compare the run report's `ai[]` against the current XLF and classify per §4.7 (pending / accepted /
corrected / stale). Emit `correctionRate` and the counts. Read-only.

### 5.8 Vendor patch — map the two states we actually use

`XlfTranslationState` models three states and `GetState` returns `MissingTranslation` for everything
else (C-11). §5.3 already classifies correctly without touching the vendor, so this patch is **defence
in depth**: it prevents a future code path that branches on `GetState` from seeing `MissingTranslation`
for a unit that plainly has a translation.

Add exactly the two states that occur in our files:

| State | Written by |
|---|---|
| `needs-review-translation` | `Apply`, for AI output (§4.8) |
| `needs-l10n` | PoEdit, when a reviewer leaves an item as needs-work (§4.10) |

- **Enum**: two new members with explicit numeric values that do not collide with the existing three.
- **`GetState`**: one switch case each. The `default` fallback stays `MissingTranslation`.
- **`UpdateStateAttributes`**: symmetric cases so both can also be written.

**Not added:** `final`, `signed-off`, `new`, `needs-review-adaptation`, `needs-review-l10n`. We never
write them and decision 12 removed them from the model; mapping them would be vendor surface for states
that should not appear. Anything unmapped keeps falling back, which classifies as *not approved* — the
safe direction.

**Provenance.** This modifies vendored MIT code pinned at `3f9413d`, so:

- the patch is **additive only** — no existing mapping changes, which keeps a future upstream bump a
  re-apply rather than a merge;
- `UPSTREAM.md` records it explicitly as a local patch on top of the pin, naming the two added values;
- test T17 asserts the mapping, so re-vendoring without re-applying the patch fails loudly.

### 5.9 Batch size and retry policy

**`-MaxItems` default: 30.**

Because `Apply` requires complete coverage, a single misnumbered or dropped item rejects the whole
batch. With a per-item error probability `p`, batch success is `(1-p)^N` — at `p = 0.5 %` that is ≈ 86 %
for 30 items but ≈ 61 % for 100. Larger batches mean fewer subagent invocations but disproportionately
more rework, and rework costs turns, not just tokens.

30 is a starting value, not a tuned one. The measured rejection rate lands in the run report; revisit
once real data exists rather than theorising now.

**Retry:** on rejection the caller re-invokes the subagent on the **same** `batch.ai.json`, appending
the rejection message so the model can correct the named ordinals. Maximum **2** retries, then stop and
report — a third failure indicates a contract or model problem, not bad luck, and looping wastes turns.

---

## 6. D5/D6 — Tests

Fixtures are **synthetic**; no customer XLF is committed. A minimal `.g.xlf` + `.de-CH.xlf` pair
covering: a plain caption, a unit with two placeholders, a unit with `maxwidth`, an option caption, and
a source with no letters.

| # | Case | Expected |
|---|---|---|
| T1 | Valid full round-trip | all applied, all states `needs-review-translation` |
| T2 | One item missing from the response | reject, no writes |
| T3 | Duplicate ordinal | reject |
| T4 | Ordinal out of range | reject |
| T5 | Correct ordinal, wrong `hash3` | reject, offending ordinal named |
| T6 | Source changed after export | reject |
| T7 | Placeholder dropped | reject |
| T8 | `maxwidth` exceeded | reject |
| T9 | `ß` in a target | reject, offending ordinal named |
| T10 | Empty target | reject |
| T11 | Wrong `batchId` | reject |
| T12 | 100 open, `-MaxItems 40` | 40 emitted, `remaining` = 60; offset 40 yields the next 40 |
| T13 | After **any** rejection | target XLF SHA-256 unchanged |
| T14 | Unit with text + `needs-review-translation` | counted as `needsReview`, **not** `missing` |
| T15 | `-FailOnUnapproved` with one unapproved unit | non-zero exit |
| T16 | Report after simulated review (one target edited, both set `translated`) | `correctionRate` = 0.5 |
| T17 | `GetState` for `needs-review-translation` and `needs-l10n` | returns the matching enum member, not `MissingTranslation` |
| T18 | PoEdit-written `needs-l10n` with text | counted as `needsReview`, **not** `missing` |
| T19 | Multi-file batch, injected failure on the second commit replacement | both target files roll back byte-for-byte; rejection names the replacement |
| T20 | Manifest file missing | reject |
| T21 | Manifest file malformed JSON | reject |
| T22 | Response `v` (schema version) mismatch | reject, message names the schema version |
| T23 | Pre-existing `ß` in an already-`translated` unit | `Validate` reports it (`IssueCount > 0`), independent of approval state |
| T24 | All units set to `translated` after `Apply` | `-FailOnUnapproved` passes |
| T25 | Independent `-FailOnIssues` / `-FailOnUnapproved` gates | each fails on its own condition, unaffected by the other passing |
| T26 | `Get-AprodaAlBuildArguments` | emits `/project`, `/packagecachepath`, `/out` so the compiler resolves symbols and writes outside the project |
| T27 | Vendor `useSelfClosingTags` default + `Sync` passing it + a `Validate`-only save | patched default survives re-vendoring guard; no empty-element expansion (`</target>`/`</note>`) on an unchanged file |
| T28 | All targets filled, `state` attribute removed everywhere | `Missing=0`, `NeedsReview=0`, `Approved=5`; `-FailOnUnapproved` passes (§4.8 amendment) |

T13 is the regression guard for the atomicity property and must run after every rejection case.
T17 guards the vendor patch: re-vendoring without re-applying it must fail here.
T18 must pass **with or without** the patch — it verifies the §5.3 classification, which is the actual
fix. T19 is the regression guard for the two-phase multi-file commit (§5.5). T28 is the regression guard
for the §4.8 approval-predicate amendment (state-less filled targets).

---

## 7. D7–D12 — Framework surfaces

**D7 `skill-translate`** — rewrite Pattern 2A to the two-artefact contract and the short key; state that
AI output lands in `needs-review-translation` and that review happens in PoEdit (§4.10). Remove the
competing legacy workflow and the "check translation memory first" constraint, which describes a
mechanism that does not exist.

**D8/D9 callers** — the translation step delegates to `AL Translation Subagent`. The Conductor adds it
to `agents:`; `al-developer` invokes it directly. Both pass the batch path and the response path, run
`Apply` themselves — the subagent never writes XLF — and apply the §5.9 retry policy.

**D10 `al-pr-prepare`** — evidence-only, unchanged in principle: report the approval-gate result and the
open review count. It never runs the tool.

**D11/D12 governance** — D-32 in its final wording plus the register row, and the in-place registration
for `skills/skill-translate/SKILL.md`. Both were deliberately deferred from the foundation commit so
the register receives a single accurate entry.

---

## 8. Acceptance criteria

1. All T1–T28 pass.
2. A run against a real app produces a run report containing `ai[]`, and `Report` computes a correction
   rate from it after a PoEdit pass.
3. `Get-AprodaTranslationStatistics` reports no unit with text as `missing`.
4. `Validate -FailOnUnapproved` fails while units await review and passes after the PoEdit pass.
5. PoEdit round-trip verified once against a real BC XLF: opening, confirming one unit and saving
   produces a diff limited to that unit (§4.10). Not committed.
6. `UPSTREAM.md` documents the vendor patch and still names the upstream pin.
7. `npm test` green; `git diff --check` clean; no `packages/foundation/**` changes.

---

## 9. Open points

| # | Item | Needed by |
|---|---|---|
| 1 | Fallback behaviour when the configured model is not entitled — fail loudly or fall back to the caller's model? | D1 |
| 2 | Confirmation of the §2 stage-boundary correction | before starting |
| 3 | `D-` entry number for this architecture (§7 decision log, item 6) | D11 |

### Model identifier — verified 2026-09-01

`GPT-5.6 Luna (copilot)` resolves and runs via `runSubagent`'s `model` parameter. A four-item smoke test
against the response contract passed on the first attempt:

- returned only the JSON — no fence, no commentary;
- `v` / `b` copied, all four keys verbatim and in order, none invented or dropped;
- placeholders preserved in order (`Posted %1 of %2` → `Gebucht %1 von %2`);
- `maxwidth` respected (`Size` → `Grösse`, 6 ≤ 10);
- **de-CH orthography correct without prompting beyond the rule**: `Grösse`, `ausserhalb`,
  `schliessen` — a de-DE-leaning model would produce `ß` in all three.

This retires the availability question but is **not** a rejection-rate measurement: n = 1 with four
items, whereas production batches carry 30, where instruction-following degrades. No case forced
abbreviation under `maxwidth`. The measured rate from the first real runs remains the deciding number.
