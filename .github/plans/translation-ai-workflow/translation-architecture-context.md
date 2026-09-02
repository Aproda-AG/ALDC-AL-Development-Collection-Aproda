# Aproda ALDC Translation Handling — Context, Findings and Principles

**Status:** Reference document for the architecture decision
**Scope:** XLIFF translation of Business Central AL extensions, primary target `de-CH`, later `fr-CH` / `it-CH`
**Related:** `translation-architecture-options.md` (solution options), `translation-ai-workflow-plan.md` (current implementation), decisions `D-31`, `D-32`, backlog `E-005`

---

## 1. Problem statement

Two goals that are usually in tension must both hold:

| Goal | Consequence |
|---|---|
| **Token efficiency** — as much as possible resolved by script and rules, as little as possible by AI | Every unit an algorithm can resolve deterministically must never reach a model |
| **Quality** — context-aware, terminologically consistent, reviewable | The units that *do* reach a model must carry enough context to be translated correctly the first time |

These are not opposites. The same mechanism serves both: **retrieval of approved prior translations and terminology**. It removes units from the AI workload *and* it improves the quality of the units that remain. This is the central architectural insight of this document.

---

## 2. Current implementation baseline

Already implemented and validated (see `translation-ai-workflow-plan.md`, `D-31`, `D-32`):

- `tools/aproda-ps-xliffsync/Invoke-AprodaBuildXliffSync.ps1` — SRP-safe content-loaded PowerShell wrapper
- Vendored minimal `rvanbekkum/ps-xliff-sync` runtime (3 files, MIT, pinned to `3f9413d`)
- Four actions: `Sync`, `ExportOpen`, `Apply`, `Validate`
- Compact AI batch contract: batch lists file paths once, items reference them by index; response is `{key, target}` only
- `Apply` is **atomic with respect to validation**: batch ID, unique known keys, current source hash, non-empty target, placeholder signature, XLIFF `maxwidth` — all verified before *any* file is written
- `Validate -FailOnIssues` as a strict gate (`Placeholders`, `OptionMemberCount`, `OptionLeadingSpaces`, `ConsecutiveSpacesConsistent`)
- Agent integration: `al-developer` executes conditionally, `al-conductor` delegates per phase and gates before `review`, `al-pr-prepare` consumes evidence only

### Known gaps in the baseline

| Gap | Impact |
|---|---|
| `ExportOpen` has no size limit | A large app can produce a batch too big for one AI turn; contradicts the plan's own "bounded batch" requirement |
| No reuse layer (stage 0) | Every open unit goes to AI, even ones translated identically ten times before — closed by stage 1's tier 1/2 (`Resolve`) for the deterministic subset; fuzzy retrieval remains stage 3 |
| No terminology injection | Consistency depends entirely on model memory across turns |
| ~~Conductor says `Sync`, not `Sync -SkipBuild`~~ — **not a gap**: stage 0's D8/D9 already wired `Sync -SkipBuild` into both `al-developer.agent.md` and `al-conductor.agent.md` (verified 2026-09-02, stage-1.spec.md §2) | — |
| ~~`skill-translate` contains a competing legacy workflow~~ — **substantially closed**: stage 0's D7 marked the legacy patterns reference-only and disclaimed; stage 1's D16 documents `Resolve` as the new pipeline step between `Sync` and `ExportOpen` | — |
| No structured run report | Evidence for review/PR is prose, not machine-readable |

---

## 3. External evidence

### 3.1 Fuzzy matches as in-context examples

Moslem et al., *Adaptive Machine Translation with Large Language Models*, EAMT 2023 ([arXiv:2301.13294](https://arxiv.org/abs/2301.13294)).

Retrieving similar approved segments from a translation memory and passing them as few-shot examples substantially outperforms both zero-shot and random-example prompting:

| Language pair | zero-shot spBLEU | random 2-shot | fuzzy 5-shot | zero-shot COMET | fuzzy 5-shot COMET |
|---|---|---|---|---|---|
| EN-ES | 53.91 | 54.78 | 61.24 | 84.0 | 91.51 |
| EN-FR | 44.87 | 45.91 | 51.94 | 58.67 | 62.81 |
| EN-AR | 27.60 | 28.94 | 41.33 | 41.28 | 62.65 |

German behaves like the high-resource pairs (ES/FR), so those rows are the relevant analogue.

Additional findings:
- Gains continue from 2 → 5 → 10 matches but with **clearly diminishing returns**; ~5 is the practical sweet spot for cost/quality.
- With fuzzy matches present, the model also uses correct terminology more often *even without an explicit glossary*.

### 3.2 Terminology injection

Same study, terminology-constrained MT:

| Setting | EN-ES spBLEU | EN-AR spBLEU |
|---|---|---|
| zero-shot | 53.91 | 27.60 |
| zero-shot + max 5 glossary terms | 55.99 | 35.38 |
| fuzzy 2-shot | 59.64 | 38.41 |
| fuzzy 2-shot + max 5 glossary terms | 60.50 | 41.27 |

Human evaluation of term adherence (0–1 scale):

| Language | zero-shot | zero-shot + glossary | fuzzy 2-shot | fuzzy 2-shot + glossary |
|---|---|---|---|---|
| EN-AR | 0.67 | 0.94 | 0.80 | 0.94 |
| EN-ES | 0.87 | 0.96 | 0.89 | 0.97 |
| EN-FR | 0.89 | 0.97 | 0.91 | 0.92 |

Operationally relevant details:
- Terms from a **curated glossary outperform terms extracted from the fuzzy matches**.
- Only terms actually matching an n-gram (1–5) of the source segment are injected — not the whole glossary.
- **Overlapping/contradictory terms hurt.** Prefer longer n-grams and drop shorter terms that overlap them.
- Forcing terminology occasionally degrades grammar; therefore terminology is a *constraint plus review signal*, not a silent search/replace.

### 3.3 Prompt caching (relevant only for a direct-API path)

Anthropic prompt caching documentation:
- Cache reads cost **10 %** of base input tokens; 5-minute writes cost 1.25×.
- Minimum cacheable prefix is **512–4096 tokens** depending on model.
- Cache hits require a **byte-identical prefix**; the breakpoint must sit on the last block that is stable across requests.
- With the Batch API, a shared prefix plus a 1-hour cache write, then the remaining requests, is the cost-optimal pattern.

**Implication for our design:** in the *agent-mediated* flow the harness controls caching, so we cannot engineer it directly. Our lever there is simply *making the batch small*. Prompt caching only becomes a design parameter if a direct provider adapter is added later — and then the stable prefix must be rules + glossary, with only the item list varying.

---

## 4. Learnings from the ACT translation tool (external, not adopted)

Reviewed: `Aproda Copilot Template (ACT)-1/Base/.github/translation-tool/`. **Decision: not adopted.** Its data (`translation-memory-*.json`) is explicitly excluded — the repository exposed a live API credential, and the entries carry no context, provenance or approval state.

### Concepts worth keeping

| Concept | Adapted form for our design |
|---|---|
| Bounded provider batches (50 texts/request) | Generic `-MaxItems` limit plus continuation, provider-independent |
| Reuse before external translation | Kept, but as a strict tier order with correctness conditions |
| Explicit export of unresolved units | Kept, but keyed by stable XLIFF unit ID + source hash, not `{id, source}` |
| Retry with exponential backoff | Only relevant if a provider adapter is added; belongs in that adapter |
| Terminology priority over raw MT | Kept as glossary injection + `forbidden` term validation |
| Statistics per phase | Kept and upgraded to a machine-readable run report |

### Anti-patterns to avoid (observed there)

1. **Credentials in the repository** and full request/header debug logging.
2. **Context-free TM** (`source → target` map) — makes `Post`, `Release`, `Item` unsafe to reuse.
3. **Auto-promoting machine output into the TM** without human approval — errors become permanent and spread.
4. **Regex "pattern translation"** of whole sentences — grammatically fragile.
5. **Comma-splitting** composite strings and reassembling translated parts.
6. **Blanket source==target whitelists** driven by a hard-coded regex list.
7. **Per-batch writes** without an all-or-nothing contract — partial state on failure.
8. **Hard-coded project paths and app names**.
9. **Validation that reports but does not fail** — unusable as a CI/delivery gate.
10. **Documentation/CLI drift** (documented commands that do not exist; dependency claims that are wrong).

---

## 5. Constraints

| # | Constraint | Source |
|---|---|---|
| C-1 | No `Import-Module`, no path-based dot-sourcing — SRP blocks it. Content-load only. | Aproda estate policy |
| C-2 | `.g.xlf` is compiler-generated; never hand-edited; AL build is the only legitimate producer | Microsoft AL documentation |
| C-3 | Translation unit `id` is stable; XML line numbers are not | XLIFF 1.2 / AL |
| C-4 | `Apply` must remain atomic — validate everything, then write | `D-31` |
| C-5 | `al-pr-prepare` consumes evidence only, never mutates XLIFF | `D-32` |
| C-6 | Framework changes to `skill-translate` / agents are in-place edits under `D-2` and must be registered | `decisions.aproda.md` |
| C-7 | Foundation distribution stays untouched for this capability | `D-32` |
| C-8 | `Aproda-AG/shared-bc-dev-resources` is **public** — no customer-identifying content may be published there automatically | Repository visibility |
| C-9 | NAB AL Tools is not in use; compatibility is explicitly not a requirement | Product decision |
| C-10 | Manual translation work currently uses the `rvanbekkum.xliff-sync` VS Code extension; the automated path must not fight its state model | Current practice |
| C-11 | **The vendored runtime knows only three states.** `XlfTranslationState` maps `needs-translation`, `needs-adaptation`, `translated`. `GetState` returns `MissingTranslation` for *any* unrecognised value. Resolution: classify on target text first and compare against `translated`; additionally patch the enum for the two states we use (`needs-review-translation`, `needs-l10n`) and record it in `UPSTREAM.md` | `vendor/XliffSync/Model/XlfDocument.ps1` (verified) |
| C-12 | **PoEdit is the manual review tool.** For XLIFF 1.2 it writes exactly `translated`, `needs-l10n`, `needs-translation` — never `final`/`signed-off`. It shows `needs-adaptation`, `needs-l10n`, `needs-review-translation`, `needs-review-l10n`, `new` and `needs-translation` as "Needs Work" when a target exists, but **not** `needs-review-adaptation`, which must therefore never be written | `vslavik/poedit`, `src/catalog_xliff.cpp` (verified) |

---

## 6. Design principles

**P-1 — Deterministic first, AI last.**
A unit reaches a model only after every rule-based and retrieval-based tier has failed to resolve it safely.

**P-2 — Reuse is a quality mechanism, not only a cost mechanism.**
What cannot be auto-applied is still valuable as in-context evidence. Nothing retrieved is wasted.

**P-3 — Never auto-apply an ambiguous match.**
Identical source text with differing approved targets is a *signal*, not a failure. Such units go to AI **with all candidates attached**.

**P-4 — Approval is a state transition, not a side effect.**
`needs-translation → needs-review-translation → translated`. Machine output enters at `needs-review-translation`; only a human review promotes it to `translated`, and only `translated` may feed the memory. This structurally prevents the ACT failure mode.

**P-5 — Derive, do not duplicate.**
The project's own approved XLIFF targets *are* the project translation memory. No parallel per-project TM file that can drift.

**P-6 — Atomic, idempotent writes.**
Tiers 0–2 are deterministic and idempotent. Only the AI tier is non-deterministic. Any batch either applies fully or not at all.

**P-7 — Context class is part of identity.**
A memory hit requires matching source *and* context class (object type / element type / property) *and* placeholder signature *and* length feasibility.

**P-8 — Evidence is machine-readable.**
Every run emits a structured report. Review and PR consume it; they do not re-derive it.

**P-9 — Shared knowledge is read-only by default, pinned by commit.**
Consumption is reproducible and auditable — the same model already used for BCQuality. Publishing back is a human-reviewed pull request, never an automated push.

**P-10 — Small, explainable rules over clever heuristics.**
Every automatic decision must be expressible in one sentence a reviewer can check.

**P-11 — Routing decisions are script rules, never model calls.**
Choosing a batch size, a model tier or a resolution tier is a decision table over data the pipeline already computed. Paying a model to decide whether to call a model is an anti-pattern.

**P-12 — Close the feedback loop before opening it.**
A machine-produced translation must not become a source for future translations until an explicit approval step exists. The approval predicate lives in the XLIFF `state` attribute: `translated` means approved, machine output does not. No parallel provenance store is needed.

**P-13 — Emit only what every tool in the chain understands; fail safe on the rest.**
A narrow write vocabulary keeps the toolchain interoperable. Unknown values classify as *not approved*,
so an unexpected state blocks a gate rather than passing silently.

**P-14 — Ship-quality and organisation-wide-quality are different decisions.**
The first is answered per delivery, in the file. The second is answered asynchronously, in Git. Merging
them forces either rushed curation or blocked deliveries.

**P-15 — What the receiver does not need does not belong in the message.**
Separate the model's view from the tool's bookkeeping. Output costs 5–6× input, so response contracts
deserve at least as much design attention as prompts.

---

## 7. Token model (why this pays off)

Order-of-magnitude comparison for one app with ~3 000 translatable units, ~600 of them open after a change:

| Approach | Input tokens (approx.) |
|---|---|
| Whole target `.xlf` into context (~120 tok/unit XML) | ~360 000 |
| Current baseline: all 600 open units, source + notes (~45 tok) | ~27 000 |
| Target design: 600 open → invariants + memory resolve ~70 % → 180 units to AI, each with source + context + ≤3 fuzzy pairs + ≤5 glossary terms (~80 tok) | ~14 400 |
| Steady state after the memory matures (~85 % resolved) | ~7 000 |

The per-unit payload *grows* (45 → 80 tokens) because of fuzzy and glossary context — and total cost still falls sharply, because the number of units reaching the model falls faster. That trade is the whole point: **fewer, better-informed calls**.

---

## 8. Explicit non-goals

- No regex-based sentence translation.
- No automatic promotion of AI or MT output into any memory.
- No comma-splitting / partial-match assembly.
- No blanket `source == target` fill outside the narrow invariant rule (§ Options doc).
- No complete `.xlf` file ever sent to a model.
- No secrets in any repository; no request/header logging.
- No NAB AL Tools dependency.
- No changes to Foundation distribution for this capability.
