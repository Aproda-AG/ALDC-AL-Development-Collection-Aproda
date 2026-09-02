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
