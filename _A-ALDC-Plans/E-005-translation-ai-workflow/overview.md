# E-005 Translation AI Workflow — Status Overview

**Purpose:** single-page status snapshot. Architecture rationale lives in
`translation-architecture-options.md` / `translation-architecture-context.md`; this file only tracks
*what is built* vs. *what is planned*, so it needs re-reading, not re-deriving.

**Last checked against code:** 2026-09-23 (`tools/aproda-ps-xliffsync/Invoke-AprodaBuildXliffSync.ps1`,
`.github/decisions.aproda.md`)

---

## 1. Stage status

| Stage | Content | Status | Evidence |
|---|---|---|---|
| **0 — Delegated execution** | `al-translate-subagent` on cheap model, two-artefact batch (`batch.ai.json`/`batch.manifest.json`), `<ordinal>-<hash3>` keys, `-MaxItems`, approval gate, `ai[]`/rejection counts in run report | ✅ Implemented, validated against a real BC app (2026-09-02) | `stage-0.spec.md` header; `Apply-AprodaTranslations`, `Invoke-AprodaAtomicXliffCommit` in the tool |
| **1 — Deterministic resolution** | `Resolve` action: tier 1 invariant (no-Unicode-letter only, **no glossary yet**), tier 2 project-derived exact memory, context class parsing, ambiguity detection | ✅ Implemented, registered 2026-09-02 (D-2/D-32 row) | `Resolve-AprodaInvariantTier`, `Resolve-AprodaMemoryTier`, `Get-AprodaContextClass`; `decisions.aproda.md` line ~552; `Invoke-Stage1Tests.ps1` |
| **2 — Terminology** | Shared-repo glossary consumption (pinned SHA), glossary injection into tier 1 + AI batch, `forbidden`-term validation, project glossary override | ❌ Not started | No glossary code in the tool; no `stage-2.spec.md` yet |
| **3 — Adaptive retrieval** | Fuzzy index (Dice + Levenshtein), in-context examples (≤3), ambiguity candidates attached to the AI batch, candidate harvest/promotion (§4.11) | ❌ Not started | No fuzzy/retrieval code in the tool; no `stage-3.spec.md` yet |

**Open acceptance item (not a decision, still outstanding):** stage 0's criterion 2 — an end-to-end run
against a real BC app producing a measured correction rate — needs an AL project with symbols and a
build, so it hasn't run in the framework repo itself yet. Take it before stage 2 changes which units
reach the model (per `stage-1.spec.md` precondition, this already happened once for stage 1 — the same
discipline applies again before stage 2).

---

## 2. Resolution tiers — target vs. built today

Same tier structure as `translation-architecture-options.md` §4.1, with an added **Built?** column so
this table doesn't drift from the code silently.

| Tier | Name | Target condition (§4.1) | Built today | Gap |
|---|---|---|---|---|
| 0 | Sync | Build AL app (or `-SkipBuild` reuse), regenerate `*.g.xlf`, sync into the target-language `.xlf` | ✅ full | — |
| 1 | Invariant | Resolves a unit deterministically to `translated` if the source has **no Unicode letter** (numbers, codes, symbols) **or** an explicit glossary entry flags the full source `invariant` | ⚠️ partial | glossary half missing (stage 2) — only the no-letter check runs today |
| 2 | Memory exact | Resolves to `translated` when normalised source + context class (`ObjectType\|ElementType\|Property`) + placeholder signature match a prior approved unit **exactly once**; refuses (falls through) if the target would exceed `maxwidth` or if several distinct approved targets exist (ambiguous) | ✅ full, incl. ambiguity → fallthrough | — |
| 3 | Retrieval | Gathers ≤3 fuzzy matches (score 0.70–0.97, Dice+Levenshtein blend) and ≤5 glossary terms matching a 1–5-gram of the source; attaches both as read-only AI context, never writes | ❌ none | entire tier is stage 3 |
| 4 | AI | Sends the bounded, still-open batch (source + context + tier-3 evidence) to a delegated subagent on a cheap model; writes nothing itself, hands off to tier 5 | ✅ full | — |
| 5 | Apply | Validates the model response fully (batch ID, key coverage, source hash, placeholders, `maxwidth`) before an atomic all-or-nothing write; sets state `needs-review-translation` | ✅ full | — |
| 6 | Validate | Checks technical rules (placeholders, option members/spacing) plus `forbidden`-term usage from the glossary; `-FailOnIssues` gates delivery, `-FailOnUnapproved` gates on every unit being `translated` | ⚠️ partial | technical rules yes, `forbidden` check needs glossary (stage 2) |
| 7 | Review | Human confirms or corrects in PoEdit's Needs-Work filter; confirming sets `translated`, the only state that feeds tier 2 memory back | ✅ (manual, no code needed) | — |

**Reading this table:** every ⚠️/❌ cell traces to a specific undone stage (2 or 3), not to an
architecture gap — §4.1 itself is not stale, it describes the finished target; this table is the
delta against it.

---

## 3. What stage 2 (glossary) and stage 3 (fuzzy/TM) add, concretely

| Adds | Where it plugs in | New artefacts |
|---|---|---|
| Glossary (`invariant`, `forbidden`, per-term `domain`/`note`) | Tier 1 (invariant half), tier 6 (`forbidden` check), AI batch `terms[]` | `glossary/de-CH.jsonl` (shared, pinned SHA), optional `.aproda/translation/glossary.de-CH.jsonl` (project override, added only on first deviation) |
| Fuzzy retrieval + in-context examples | Tier 3 (new), AI batch `ex[]` | in-memory inverted-token index over approved targets, cached under `.cache/` (gitignored) |
| Candidate harvest + promotion | Outside the resolution pipeline; a periodic, human-gated step | `*.candidates.jsonl`, promoted via PR in the shared repo, never automated |

Why both together, not memory alone: memory only fires on repeated segments; glossary enforces
terminology on *new* segments and adds hard `forbidden`/`invariant` rules memory cannot express. See the
chat answer from 2026-09-23 (glossary vs. pure TM) for the full argument and the cited study numbers.

---

## 4. Doc map

| Question | Doc |
|---|---|
| Why this architecture, alternatives rejected, evidence | `translation-architecture-context.md` |
| Full target design, data contracts, decision log | `translation-architecture-options.md` |
| What stage 0 built (spec) | `stage-0.spec.md` |
| What stage 1 built (spec) | `stage-1.spec.md` |
| Delivered baseline description (pre-stage-1 wording) | `translation-ai-workflow-plan.md` |
| Cost figures per batch/model | `ai-cost-model.md` |
| This file | current status only — update alongside the code, not instead of the specs above |
