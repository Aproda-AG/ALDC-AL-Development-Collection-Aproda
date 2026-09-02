# Aproda ALDC Translation Handling — Solution Options and Recommendation

**Status:** Architecture accepted 2026-09-01 — implementation unblocked, one item open (§7)
**Companion:** `translation-architecture-context.md` (evidence, constraints, principles)
**Decision owner:** Florian Köll

---

## 1. Decision axes

The realistic design space is defined by four independent choices. Everything else follows from them.

| Axis | Options | Comment |
|---|---|---|
| **A — Reuse source** | none / project XLIFF only / project + shared repository | Determines how fast the token curve drops |
| **B — Role of fuzzy matches** | not used / auto-applied / **used only as AI context** | Auto-applying fuzzy matches is the classic quality trap |
| **C — Model access** | agent-mediated (batch file) / direct provider API | Affects cost model, secrets, prompt caching |
| **D — Knowledge flow** | consume only / consume + human-reviewed publish | Public repository makes this a governance question |
| **E — Model tier** | one model / script-routed tiers / model-decided routing | Routing must be a decision table, never a model call (P-11) |

Axis B is fixed at **AI context only**. Auto-applying a 90 % match is precisely how `Post`/`Release`/`Item` errors become permanent.

---

## 2. Alternatives considered

Recorded so the reasoning is not re-litigated later. Git history is not a substitute — nobody reads it
for rationale.

**A deterministic extension only** — invariant tier, exact reuse, bounded batches, no shared knowledge
and no retrieval. Not rejected but *absorbed*: it is exactly stages 0–1 (§5). Treating it as the
destination would have capped quality at today's level and left the prepared shared repository unused,
for the same implementation effort.

**A full localisation platform** — direct provider API (DeepL / Azure / LLM) with prompt-caching-aware
prefixes and Batch API, automated publishing back to the shared repository, CI gates, and a
multi-language matrix in one run. Deferred, not dismissed:

- A write token to a **public** repository would have to live in every project repo (C-8), and customer
  source text would pass through automation that publishes there. The ACT tool shows this failure
  concretely — a live API credential sat in its README and its request logging printed full headers.
- A provider API moves customer strings outside the approved tool boundary. That is a data-protection
  question, not an engineering one.
- Prompt caching only becomes a lever once we call an API directly; in the agent-mediated flow the
  harness controls it, so the design gains nothing from it today.

Every element stays a clean extension point: the provider adapter sits behind the existing batch
contract, and publishing remains a human pull request (§4.11).

**Auto-applying fuzzy matches** — rejected in every variant. A 90 % match applied without review is
precisely how `Post`, `Release` and `Item` errors become permanent and then propagate through the
memory. Fuzzy matches are in-context evidence only (axis B).

---

## 3. Decision — accepted 2026-09-01

**Adopt the Adaptive Waterfall as the target architecture, delivered in staged increments, with the deterministic tiers as its core.**

Rationale:

1. The deterministic core is a strict subset of the full design, so stages 0–1 deliver value immediately without a throwaway step.
2. The largest *quality* lever in the evidence — fuzzy in-context examples plus curated glossary terms — is exactly the mechanism that also removes the largest number of units from the AI workload. One mechanism, both goals.
3. The platform variant's differentiators are the parts with the worst risk/benefit ratio right now: a public repository plus automated publishing plus API credentials.
4. Nothing in this design blocks that variant later; each of its elements remains an additive extension point.

**Deferred deliberately:** provider adapter, automated publish, CI gate. They stay documented as extension points and remain compatible with the contracts below.

---

## 4. Target architecture

### 4.1 Resolution tiers

Executed strictly in order. A unit leaves the pipeline at the first tier that resolves it.

| Tier | Name | Condition | Writes XLIFF | Deterministic |
|---|---|---|---|---|
| 0 | **Sync** | Build (or `-SkipBuild`) → `*.g.xlf` → target sync | yes | yes |
| 1 | **Invariant** | Source contains no Unicode letter, **or** an explicit glossary entry marked `invariant` matches the full source | yes | yes |
| 2 | **Memory exact** | Normalised source + context class + placeholder signature match, exactly one approved target, target fits `maxwidth` | yes | yes |
| 3 | **Retrieval** | Gather ≤3 fuzzy matches (70–97 %) and ≤5 glossary terms matching a 1–5-gram of the source | no | yes |
| 4 | **AI** | Bounded batch → compact response, executed by a delegated subagent (§4.9) | via tier 5 | no |
| 5 | **Apply** | Full validation of the response, then all-or-nothing write | yes | yes |
| 6 | **Validate** | Technical rules + `forbidden` terminology; `-FailOnIssues` for delivery, `-FailOnUnapproved` for the approval gate | states/notes only | yes |
| 7 | **Review** | Reviewer confirms or corrects in PoEdit → `translated` | yes (PoEdit) | — |

Tier 2 explicitly refuses to act when a match is **ambiguous** (several distinct approved targets). Such units fall through to tier 3, and the competing candidates are attached as context for tier 4.

### 4.2 Context class

Derived from the XLIFF Generator note, normalised to three parts:

```
<ObjectType>|<ElementType>|<Property>
Table|Field|Caption
Page|Action|Caption
Codeunit|NamedType|Label
Report|Label|Caption
```

Two units are memory-equivalent only if their context classes are equal. This is what makes reuse of `Post`, `Release` or `Item` safe.

### 4.3 Fuzzy scoring (no external dependencies)

Pure .NET / PowerShell, three stages, so it stays fast and explainable:

1. **Prefilter** — candidates whose normalised length ratio is within `[0.6, 1.6]` and that share at least one rare token (inverted index over normalised tokens).
2. **Score** — `0.6 × tokenDiceCoefficient + 0.4 × (1 - normalisedLevenshtein)`, computed on the normalised source (case-folded, placeholders masked to `§`, whitespace collapsed).
3. **Rank & cut** — descending, keep ≤3 above 0.70; treat ≥0.98 with identical context class and a unique target as a tier-2 exact match.

Normalising placeholders before scoring means `Post %1 of %2` and `Post %1 of %3` are recognised as near-identical, which is exactly the desired behaviour for UI strings.

### 4.4 Data contracts

**Glossary entry** (`JSONL` — one object per line, clean diffs, append-friendly, no merge conflicts inside a large object):

```json
{"source":"Item","target":"Artikel","lang":"de-CH","domain":"inventory","forbidden":["Gegenstand","Position"],"note":"BC standard entity"}
{"source":"PDF","target":"PDF","lang":"de-CH","invariant":true}
```

**Memory entry** (`JSONL`) — approval is implied by the file it lives in (§4.5), not by a field:

```json
{"source":"Post the selected lines?","target":"Ausgewählte Zeilen buchen?","lang":"de-CH","ctx":"Codeunit|NamedType|Label","srcHash":"9f2c…","ph":"","max":null,"origin":"project-x","rev":"2026-09-01"}
```

**Batch — two artefacts.** What the model needs and what the tool needs are separated, so bookkeeping
fields never enter the message. The subagent reads only the first file.

`batch.ai.json` — the model's view:

```json
{"v":1,"b":"<batchId>","lang":"de-CH","items":[
  {"k":"7-a3f","s":"Posting Date","c":"Table MyTable|Field|Caption","m":30,
   "terms":[{"s":"Posting","t":"Buchungs"}],
   "ex":[{"s":"Posting Time","t":"Buchungszeit"}]}
]}
```

`batch.manifest.json` — tool-internal only, never sent to a model:

```json
{"v":1,"b":"<batchId>","files":["…/App.de-CH.xlf"],"items":[
  {"k":"7-a3f","file":0,"unitId":"Table 2328808854 - Field 1 - Property 2879900210","srcHash":"a3f…","ph":[]}
]}
```

The old single-file batch sent `Key`, `UnitId`, `TargetFileIndex` and a 64-character `SourceHash` to the
model — roughly two thirds of the payload, none of it useful for translating.

**Response contract:**

```json
{"v":1,"b":"<batchId>","t":[{"k":"7-a3f","t":"Buchungsdatum"}]}
```

**Key format `<ordinal>-<hash3>`.** The ordinal correlates; the three hex characters are the leading
digits of the `srcHash` the tool already computes. This costs roughly a quarter of the full unit
identifier and is *stronger* than a bare ordinal — a shifted or corrupted ordinal would otherwise land
silently on a valid neighbour, whereas a mismatched fragment fails hard (collision odds 1:4096).

A *semantic* short key (`7:Posting`) is deliberately avoided: the item already carries its source, so
the key needs no meaning, and a natural-language key invites the model to translate it — costing a
whole rejected batch.

**`Apply` validation, in order:** key parses → ordinal in range and unseen → `hash3` matches that
manifest entry → **complete coverage** (exactly `1…N`, each once) → batch ID → unit still exists →
source unchanged → placeholder signature → `maxwidth`. Only then is anything written, atomically.

### 4.5 Repository layout

Shared, `Aproda-AG/shared-bc-dev-resources` (public, read-only consumption, pinned by SHA):

```
bc-translation/
  glossary/de-CH.jsonl                 # approved, consumed
  glossary/de-CH.candidates.jsonl      # harvested, ignored by consumers
  memory/de-CH.jsonl                   # approved, consumed
  memory/de-CH.candidates.jsonl        # harvested, ignored by consumers
  schema/*.schema.json
  CONTRIBUTING.md                      # review rules, "no customer content" gate
```

**Approval is expressed by the file, not by a status field.** Appending to `*.candidates.jsonl` is
low-risk because nothing reads it. Promotion is a pull request whose diff moves lines from candidates
to approved — maximally readable, and it decouples *capturing* the data from *blessing* it.

Project:

```
.aproda/translation/
  config.jsonc             # language, thresholds, pinned shared SHA
  glossary.de-CH.jsonl     # optional override, added only on first real need
  .cache/                  # gitignored: retrieval index, batch artefacts, run reports
```

The project glossary is **not created up front**. It is needed only when a project must deviate from
shared terminology; precedence (project wins) is defined so it can be added later at no cost. Newly
discovered terms go straight into the candidate export and need no local staging file.

Project memory is *derived* from the project's own approved XLIFF targets and never stored as a second
source of truth (P-5).

### 4.6 Action surface

```
Sync         build (unless -SkipBuild) + sync *.g.xlf → target        writes
Resolve      tier 1 + tier 2, reports counts per tier                 writes   [new]
ExportOpen   bounded batch incl. terms/examples/candidates            read-only
Apply        validate everything, then write atomically               writes
Validate     technical rules + forbidden terminology, -FailOnIssues   states
             + approval gate: every translatable unit `translated`,
               -FailOnUnapproved (script-only, no AI)
Report       emit the run report; compare ai[] against the reviewed    no XLIFF writes [new]
             XLF to derive accepted / corrected / pending
```

Parameters added: `-MaxItems` (default 30), `-Language`, `-SharedRoot`, `-NoShared`, `-MinFuzzy` (default 0.70), `-MaxExamples` (default 3), `-MaxTerms` (default 5).

### 4.7 Run report

Written to `.aproda/translation/.cache/`, consumed by review, metrics and PR evidence:

```json
{
  "schemaVersion": 1,
  "runId": "2026-09-01T14-22-05Z",
  "language": "de-CH",
  "sharedSha": "…",
  "totals": {"translatable": 3012, "open": 604, "invariant": 96,
             "memoryExact": 318, "ai": 190, "unresolved": 0},
  "batches": [{"batchId": "…", "items": 40, "applied": 40, "rejected": 0, "rejectReason": null}],
  "ai": [{"k": "7-a3f", "unitId": "…", "target": "Buchungsdatum", "tier": "simple"}],
  "validation": {"issues": 0, "strict": true},
  "ambiguous": [{"unitId": "…", "candidates": 2}]
}
```

**Measuring the correction rate.** No fixture and no extra tooling are needed — review changes both the
state *and*, when corrected, the text. Because `ai[]` records what the model actually wrote, a later
`Report` run compares it against the current XLF:

| Current state | Current target | Outcome |
|---|---|---|
| `needs-review-translation` | — | pending |
| `translated` | equals `ai[].target` | accepted |
| `translated` | differs | **corrected** |
| unit gone, or source changed | — | stale, excluded |

`correctionRate = corrected / (accepted + corrected)`. This is the number that decides how much stage 2
is worth, so it must be collectable from stage 0 onward.

**Retention matters:** `.cache/` must survive between the run and the review, otherwise the comparison
basis is gone. Reports are therefore named per `runId` and not overwritten. `Report` never writes to an
XLIFF file, but it does persist its computed metrics back into the cached report — "read-only" refers to
the translation files, not to the cache.

One-line evidence for the phase-complete / PR sections:

```
XLIFF de-CH: 604 open → 96 invariant, 318 memory, 190 AI (5 batches, 0 rejected), 0 issues (strict)
```

### 4.8 Approval state model — **decided**

The governing rule (P-12):

> A machine-produced translation must not become a source for future translations until an explicit approval step exists.

This is carried entirely by the XLIFF `state` attribute. No sidecar, no custom notes, no vendor patch — the XLF file remains the single source of truth (P-5).

**One predicate, two sets.** The pipeline asks exactly one question per unit: approved or not?

| | States |
|---|---|
| **Approved** | `translated` — and nothing else |
| **Not approved** | everything else, including any unknown value |

**The state is written by the tier that produced the unit — never by model self-assessment.**

| Producer | State written |
|---|---|
| Sync, no translation found | `needs-translation` *(vendor)* |
| Validate, technical problem detected | `needs-adaptation` *(vendor)* |
| Tier 1 invariant | `translated` |
| Tier 2 memory exact | `translated` |
| **Tier 4 AI** | **`needs-review-translation` — always** |
| PoEdit, reviewer confirms | `translated` |
| PoEdit, reviewer leaves as needs work | `needs-l10n` |

AI output is *never* auto-approved, regardless of how confident the model claims to be. Self-reported confidence is weak evidence; the producing tier is not.

**`final` / `signed-off` are not used at all.** PoEdit cannot emit them, and the project file needs to
answer only one question: is this good enough to ship? A three-step translator/reviewer/lead ladder
encodes a distinction nothing branches on. **Unknown states classify as not approved** — so if `final`
ever appeared in a file, the gate would block rather than silently pass. That is the correct direction
for a failure, and re-admitting it later is one line in the classifier.

The question *"should this become organisation-wide knowledge?"* is a different question with a
different risk profile, and it is answered in Git, not in the XLF (§4.11).

**Why this resolves C-11.** The vendored `GetState` models only three states and returns `MissingTranslation` for anything else. The fix is in our own classification: check target text first, then compare against `translated`. A unit with a translation and an unmapped state therefore lands in *needs review*, never in *missing*. On top of that, the vendored enum is patched additively for the two states that actually occur in our files — `needs-review-translation`, which `Apply` writes, and `needs-l10n`, which PoEdit writes — so a future code path branching on `GetState` cannot see `MissingTranslation` for a translated unit. `final` and `signed-off` are **not** mapped: decision 12 removed them from the model. The patch is recorded in `UPSTREAM.md` and guarded by a test. Verified as safe:

- `Sync-XliffTranslations` imports the existing `<target>` node wholesale and only forces `translated` when it *newly* finds a translation — foreign states survive a sync.
- `Test-XliffTranslations` decides "missing" on the translation **text**, not the state — a `needs-review-translation` unit with text is neither flagged nor overwritten.

**No cut-over needed.** Existing translations already carry `translated`, written by the current toolchain, and they are in production. They are approved by definition. Projects without existing translations start with an empty memory, which is correct.

**The feedback loop is closed by construction.** Memory reads approved units only. AI output is not approved. No filter logic, no provenance record, no promotion path is required to keep the loop shut.

### 4.9 Model execution and routing

**Execution.** Tier 4 runs in a dedicated subagent on a fast, inexpensive model rather than in the orchestrating agent. Two gains, the second usually the larger:

1. **Cost** — translation is the highest-volume token consumer in the workflow.
2. **Context isolation** — batch, examples and terminology never enter the Conductor's context window.

This is safe because **correctness is enforced by PowerShell, not by the model**: `Apply` verifies batch ID, known unique keys, current source hash, placeholder signature and `maxwidth` before any write. A weaker model cannot corrupt an XLF file; the worst case is a rejected batch or a mediocre translation.

The model's realistic failure modes are largely machine-detectable, and those checks are mandatory whenever a cheap model is used:

| Failure mode | Deterministic check |
|---|---|
| `ß` instead of `ss` (de-CH uses no `ß`) | Regex in **both** `Apply` (rejects the batch) and `Validate` (reports a finding) |
| Terminology drift | `forbidden` list per glossary entry |
| Malformed response | `Apply` rejects the whole batch |
| Placeholder loss or reordering | already implemented |
| Register, idiom, disambiguation | **not detectable** — residual risk, addressed by tier 3 context |

**Why the `ß` check sits in two places.** In `Apply` it rejects the whole batch, consistent with the
all-or-nothing contract and cheap to retry — the rejection message names the offending items so the
retry is targeted. In `Validate` it is a reported finding, which also catches pre-existing and
manually entered text in units the tool never wrote. It is deliberately **not** auto-normalised:
`ß`→`ss` is unambiguous for ordinary text, but German proper nouns keep their original spelling, and a
silent fix would be wrong exactly there.

**Implementation.** The repository already mixes models per agent (`Claude Sonnet 5 (copilot)`, `GPT-5.6 Terra (copilot)`, `GPT-5.3-Codex (copilot)`), so this follows the established pattern: an `agents/al-translate-subagent.aproda.agent.md` with the cheap model in `model:` frontmatter (the `.aproda.` infix marks it as net-new in the Aproda layer, so the sync manifest picks it up by glob). Display name **`AL Translation Subagent`** — the file uses the short form and the display name the noun form, exactly as `al-implement-subagent` / `AL Implementation Subagent` and `al-review-subagent` / `AL Code Review Subagent` already do. `runSubagent` additionally accepts a per-call `model` override. The subagent **writes `response.json` itself** and returns only a short summary — otherwise the response JSON travels back through the result message and the context-isolation gain is lost.

**Boundary rule — return to the *calling* agent.** Unlike the existing subagents, this one has two
callers: `al-developer` on the LOW-complexity path and `al-conductor` for MEDIUM/HIGH. Its boundary
rules must therefore say *"return results to the calling agent"*, not *"return results to the
Conductor"* — copying the existing wording verbatim would be wrong on the LOW path. It is registered in
the Conductor's `agents:` list and invoked directly by `al-developer`.

**Routing is a script rule, not a model decision (P-11).** Every signal is already computed by the retrieval tier, so the marginal cost is effectively zero:

```
+2  no example with score >= 0.85
+2  uncovered content words > 30 %
+3  Candidates present (ambiguity)
+1  >= 2 placeholders
+2  maxwidth tight (< source length * 1.15)
+1  > 12 words

<= 2  -> simple (cheap model)      >= 3  -> complex (strong model)
```

**Measure before splitting.** A whole run costs cents — see `ai-cost-model.md` for the exact figures — so the price difference between tiers is negligible in absolute terms; the dominant costs are review time and context budget. Model routing is therefore primarily a **quality and context decision, not a cost decision**. Accordingly: start with a single cheap model for everything, emit `Tier` and the rejection/correction rates in the run report, and introduce the second model path only once the data shows a class that systematically underperforms. Building the two-tier router speculatively would be exactly the over-engineering this design otherwise avoids.

### 4.10 Review in PoEdit — **decided**

Review needs no custom artefact. PoEdit is already the manual translation tool, it reads XLIFF 1.2 natively, and its "Needs Work" filter is exactly the queue we produce.

**Verified from `catalog_xliff.cpp` (PoEdit source):**

- Reads as *Needs Work*: `needs-adaptation`, `needs-l10n` unconditionally; `new`, `needs-translation`, `needs-review-translation`, `needs-review-l10n` when a target text is present.
- Writes for XLIFF 1.2 exactly three values: `translated` (confirmed), `needs-l10n` (still needs work), `needs-translation` (empty). **It never writes `final` or `signed-off`**, so C-11 cannot be triggered from the review side.
- Does **not** map `needs-review-adaptation` to Needs Work — we therefore never write that state.
- Keeps `state-qualifier` on units the reviewer does not touch (measured; the source drops it only where it rewrites the target).
- Does **not** surface `maxwidth` to the reviewer (measured on 3.9.1), even though BC emits it with `size-unit="char"`. The length limit is therefore enforced by tooling only — the batch carries `maxwidth`, `Apply` rejects overlength targets and `Validate` reports them. A reviewer typing an overlong text is caught at `Apply`/`Validate`, not in PoEdit.
- Surfaces the `Developer` and `Xliff Generator` notes as comments — the reviewer gets the BC context for free.

**Workflow:** open the target `.xlf` in PoEdit → filter to Needs Work → confirm or correct → save. Confirmation sets `translated`, which is precisely the approval predicate the gate and the memory read.

This removes the review worksheet, the `Promote` round-trip and the markdown parser from the design entirely.

**Empirically verified (PoEdit 3.9.1, BC-shaped XLF, 2026-09-02):** opening the file, confirming one unit and saving produced exactly one semantic change — that unit's `state` from `needs-review-translation` to `translated`. All six other units were byte-identical in content, including placeholders, Swiss orthography, `maxwidth`, `size-unit`, `xml:space`, the namespace declarations and both note kinds. The only further difference was serialization of empty elements (`<note …></note>` written as `<note …/>`), which is semantically identical and does not grow the diff beyond the affected lines. The Needs-Work queue contained exactly the five expected units: the four `needs-review-translation` entries plus the `needs-l10n` entry, while the empty `needs-translation` unit counted as untranslated rather than Needs Work — confirming that PoEdit treats that state as fuzzy only when a target text is present.

### 4.11 Promotion to shared knowledge — **decided**

Two questions have been conflated so far. They have different risk profiles and belong in different
places:

| Question | Who | When | Medium |
|---|---|---|---|
| Is the translation good enough **for this project**? | whoever ships | per delivery | PoEdit → `translated` |
| Should it become **organisation-wide knowledge**? | whoever owns terminology | batched, asynchronous | Git pull request |

The second question does not need answering per delivery. A translation can be perfectly correct in its
project and wrong as a general rule — a customer may want *Beleg* where the BC standard is *Dokument*.
Project `translated` therefore makes a unit a **candidate**, never an approved shared entry.

**Harvest (local, automated).** Against the pinned shared clone:

- identical to an approved entry → dropped silently
- new → written to `*.candidates.jsonl`
- **conflicts** with an approved entry (same source and context class, different target) → *not* a
  candidate; reported separately. This short list is the highest-value review artefact, because it is
  exactly where terminology drifts between projects.

**Kept small by construction**, otherwise a large PR gets rubber-stamped and creates false confidence:
terms before whole segments; project-specific content excluded mechanically (customer/app prefixes,
identifiers, digit sequences); cross-project frequency used to *rank* the list, never to auto-approve —
three projects can copy the same mistake.

**Where the automation lives.** CI belongs in the **shared** repository, validating pull requests — not
in project repositories extracting data. A project-side job would need a write token to a *public*
repository in every project repo, and would push customer strings through automation.

| Step | Where | Automated |
|---|---|---|
| Harvest, deduplicate, detect conflicts | local, against the pinned clone | yes |
| Open the pull request | human | no — deliberately |
| Validate schema, duplicates, conflicts, forbidden patterns, `ß` rule | shared-repo CI | yes |
| Promote (move lines candidates → approved) | human, in the PR | no |

**Cadence:** periodic, not per delivery — cross-project frequency only becomes a signal once several
projects have contributed. The run report surfaces the candidate count as information, never as a gate.

**Conflict resolution:** approved wins; a project may deviate locally through its own glossary; the
conflict is reported, never auto-resolved.

**Retroactivity:** none. Correcting a shared entry does not rewrite shipped projects. A later `Validate`
run may report the divergence as a hint, but nothing writes back into delivered translations.

---

## 5. Delivery stages

| Stage | Content | Human review | Gate |
|---|---|---|---|
| **0 — Delegated execution and contract** | `al-translate-subagent` on the cheap model; **two-artefact batch** (`batch.ai.json` / `batch.manifest.json`) and `<ordinal>-<hash3>` keys; `-MaxItems` (default 30) + continuation; AI output written as `needs-review-translation`; corrected state classification plus an additive vendor patch for the two states in use; `ß` check; approval gate; `ai[]` and rejection counts in the run report | PoEdit Needs-Work pass | Round-trip tests against synthetic fixtures in `tools/aproda-ps-xliffsync/test/fixtures/`; `Apply` validation proves model-independence. PoEdit formatting verified once against a real BC XLF (not committed) |
| **1 — Deterministic resolution** | Invariant tier, project-derived exact reuse, `Sync -SkipBuild` fix, `skill-translate` cleanup | PoEdit Needs-Work pass | Smoke tests on synthetic XLIFF; `npm test`; no Foundation changes |
| **2 — Terminology** | Shared repo consumption (pinned), glossary injection, `forbidden` validation, unknown-term list in the run report. **No project glossary** until a project actually needs to deviate | unchanged — additional effort shifts to glossary curation, amortised across all projects | Seeded `de-CH` glossary reviewed by a human; deterministic term-selection tests |
| **3 — Adaptive retrieval** | Fuzzy index, in-context examples, ambiguity candidates, candidate harvest with duplicate and conflict detection (§4.11) | unchanged — the state model already gates reuse | Measured before/after on a real app: units-to-AI, correction rate |

Each stage is independently shippable and independently revertible. Stage 0 is deliberately placed first: it is the most isolated change, delivers context isolation immediately, and its measured correction rate is what tells you how much stage 2 is actually worth.

Two honest notes on ordering:

- In stage 0/1 the cheap model has **no** glossary or fuzzy support yet, so its quality risk is at its highest there. That is precisely why the `ß` check and the correction metric belong in stage 0 rather than later.
- Because AI output lands in `needs-review-translation`, translation review is a **blocking delivery condition from stage 0**, not from stage 3 — decided, `-FailOnUnapproved` is on. This is affordable because PoEdit does the work and because the deterministic tiers keep the queue small: the units that reach review are exactly the ones no rule could resolve.

---

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Wrong reuse of ambiguous terms | Context class + uniqueness requirement; ambiguity routed to AI with candidates (never auto-applied) |
| Shared glossary contains a bad entry | Candidates live in a file consumers ignore; promotion is a human PR; the SHA pin means a new entry cannot appear mid-project unnoticed; a project glossary can override |
| Customer content leaking into a public repo | No automated publish; harvest filters customer/app prefixes and identifiers mechanically; only `translated` units become candidates; promotion is a human PR |
| Retrieval slows large apps down | Inverted-index prefilter; index cached in gitignored `.cache/`; hard cap on candidates |
| Injected terminology damages grammar | Max 5 terms, longest-match-wins, overlapping shorter terms dropped; terminology is a hint plus a `forbidden` check, never search/replace |
| Batch grows beyond a usable AI turn | `-MaxItems` enforced in the tool, not in the prompt |
| Cheap model degrades quality unnoticed | `ß` / placeholder / `maxwidth` / `forbidden` checks are mandatory; rejection and correction rates tracked per run; escalation threshold defined before rollout |
| A state the vendor cannot read enters the file | Classification checks target text first and compares against `translated`, so an unmapped state cannot be counted as missing; the enum patch covers the two states we use (§4.8). Anything else classifies as **not approved**, blocking the gate instead of passing silently. A test asserts the mapping so a lost patch fails loudly |
| PoEdit reformats the whole XLF on save | pugixml round-trip preserves existing whitespace nodes; verify once against a real BC file before adopting the workflow |
| Unreviewed AI output blocks delivery | Intended — the gate is blocking. Kept affordable by the deterministic tiers (only unresolved units reach review), by PoEdit's Needs-Work filter, and by the open count being visible in the run report |
| Framework drift vs. Foundation | Register the in-place edits under `D-2`; Foundation stays untouched |

---

## 7. Decision log

### Confirmed (2026-09-01)

| # | Decision |
|---|---|
| 1 | **Adaptive Waterfall** is the target architecture, delivered in stages (§3) |
| 2 | **JSONL** is the format for glossary and memory |
| 3 | `Aproda-AG/shared-bc-dev-resources` is consumed **read-only and SHA-pinned**; publishing is deferred to a separate approved plan |
| 5 | The glossary seed is authored fresh and reviewed — **no import from the ACT dataset** (its repository exposed a live credential and its entries carry no context, provenance or approval state) |
| 7 | Tier 4 runs in a **delegated subagent on a fast, inexpensive model**, backed by mandatory deterministic checks |
| 8 | Review is kept **minimal by tooling, not by postponement**: no bespoke worksheet, no promotion round-trip |
| 9 | Model selection is a **script rule** (§4.9), never a model call |
| 4 · 10 | **Approval is carried by the XLIFF `state` attribute** (§4.8). `translated` = approved; AI output always writes `needs-review-translation`. No provenance sidecar, no notes, no cut-over — the vendored enum is patched additively for the two states in use (decision 21). The feedback loop is closed by construction |
| 11 | **PoEdit is the review surface** (§4.10). Its native Needs-Work filter is the queue; confirming sets `translated`. The review worksheet and `Promote` action are dropped |
| 12 | **`final` / `signed-off` are not used.** `translated` is the only approved state; unknown values classify as not approved, so a stray state blocks rather than passes |
| 13 | The approval gate is a **script check** in `Validate` — every translatable unit must be `translated`, controllable via `-FailOnUnapproved`. `al-pr-prepare` consumes its recorded result and never runs the tool itself |
| 15 | **The batch is split into an AI view and a tool manifest** (§4.4). Bookkeeping fields never enter the model message; the old contract sent roughly two thirds useless payload |
| 16 | **Correlation key is `<ordinal>-<hash3>`** — about a quarter the cost of the full identifier and stronger than a bare ordinal, because a shifted ordinal fails the check fragment |
| 17 | **Shared knowledge is promoted in Git** (§4.11): `*.candidates.jsonl` → `*.jsonl` by human PR, validated by shared-repo CI. No write tokens in project repositories |
| 18 | **No project glossary up front** — added only when a project must deviate from shared terminology |
| 19 | **The `ß` check runs in `Apply` (rejects the batch) and in `Validate` (reports a finding)**, and is never auto-normalised — German proper nouns keep their spelling |
| 20 | **Correction rate is measured from the run report** (§4.7): `ai[]` records what the model wrote, a later `Report` compares it against the reviewed XLF. No fixture required |
| 14 | **The approval gate is blocking** (`-FailOnUnapproved` on) from stage 0 |
| 21 | **The vendored state enum is patched additively** for `needs-review-translation` and `needs-l10n` only (§4.8) — defence in depth, not the primary fix. `final`/`signed-off` stay unmapped per decision 12. Recorded in `UPSTREAM.md`, guarded by a test |
| 22 | **`-MaxItems` defaults to 30**, with at most two retries per batch (§5). A starting value to be tuned once the measured rejection rate exists |

### Open

None. Item 6 (the `D-` entry recording this architecture) is closed — `D-32` is authored and registered.

One stage 0 acceptance criterion is still outstanding, and it is not a decision: criterion 2, an end-to-end run against a real BC app producing `ai[]` and a measured correction rate. It needs an AL project with symbols and a build, so it cannot run in the framework repository. Take that measurement before stage 1 lands — once the deterministic tiers change which units reach the model, the stage 0 baseline can no longer be obtained.

### Verified sources

| Claim | Source |
|---|---|
| Vendor maps only three states; unknown → `MissingTranslation` | `vendor/XliffSync/Model/XlfDocument.ps1` |
| Sync preserves foreign states; Test decides "missing" on text, not state | same file, merge and `HasMissingTranslation` paths |
| PoEdit Needs-Work read set; writes only `translated` / `needs-l10n` / `needs-translation`; ignores `needs-review-adaptation` | `vslavik/poedit`, `src/catalog_xliff.cpp` |
| Round trip changes only the confirmed unit; `maxwidth` is not shown to the reviewer; `state-qualifier` survives on untouched units | Measured against a BC-shaped XLF, PoEdit 3.9.1, 2026-09-02 |
| Fuzzy in-context examples and glossary terms improve quality and terminology adherence | Moslem et al., EAMT 2023 (arXiv:2301.13294) |

### Next step

Stage 0 is the smallest independently valuable increment and is ready to specify: one subagent definition, Conductor registration and `al-developer` invocation, the two-artefact batch with `<ordinal>-<hash3>` keys, AI output written as `needs-review-translation`, the `ß` check in `Apply` and `Validate`, the state classifier over the raw attribute, and `ai[]` plus `Tier` in the run report so the correction rate becomes collectable.

Test fixtures are synthetic and live with the tool; no customer XLF is committed. The PoEdit round-trip formatting check is a one-off manual verification against a real file.
