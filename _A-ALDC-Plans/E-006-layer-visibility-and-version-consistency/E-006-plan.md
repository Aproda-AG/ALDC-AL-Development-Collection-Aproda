# E-006 — Remediation Plan

> **⚠️ Superseded as a status document (2026-09-24).** This file is the **original proposal**; the live
> tracker is [`action-plan.md`](action-plan.md). Phases 1–3 have been executed (Blocks 1–3, commit
> `5f7d042`), so the "nothing has been executed" note below applies only to the moment of writing.
> Kept for its rationale — the option tables and the *why* behind each rule — not for its status.
>
> **One recommendation was overruled, deliberately:** **Q-2** recommends *retiring* `copilotSource`
> (option B). The decision taken in **T-3** was the opposite — **keep it**: upstream actively maintains
> it (2 of 27 commits), the fork never modified it, and deleting it would produce a delete/modify
> conflict plus a `missingToolkitFiles: error`. **Q-1** was decided as recommended (option A′).
> Read the Q-2 section below as the argument that was *weighed and rejected*, not as guidance.

> **Nothing in this plan has been executed.** It is a proposal for maintainer approval.
> Edits already made during the 2026-09-21/22 session (before this plan existed) are listed in
> **Appendix A** — they must be reviewed under the D-16 steward guardrail, which did **not** fire (F-2).

**Guiding principle:** fix the *rule* before the *files*. Every individual defect found is an instance of
one missing governance rule plus one missing validator. Repairing only the files guarantees a repeat.

---

## Phase 0 — Decide the two open questions (maintainer, no code)

Both are design decisions that change the shape of later phases. Each needs a `decisions.aproda.md`
D-entry.

### Q-1 — How should the fork repo expose the toolkit to Copilot? (blocks F-1/F-2)

| Option | Mechanism | Pros | Cons |
|---|---|---|---|
| **A** | Add `.vscode/settings.json` to the fork with `chat.instructionsFilesLocations` / `promptFilesLocations` / agent + skill locations pointing at the root folders | Minimal, reversible, fork-only, no file duplication | **Contradicts D-5** ("no `.vscode` discovery registration needed") → D-5 must be amended to be *project-scoped* |
| **B** | Mirror root → `.github/` in the fork (as in projects) | Fork behaves exactly like a project | Massive duplication; the syncer's whole layout-remap design exists to avoid this |
| **C** | Do nothing; accept that the layer is invisible while developing it | Zero effort | Leaves the D-16 guardrail dead in the only repo where it matters. **Not recommended.** |

**Recommendation: A**, plus amending D-5 to read *"…needed **in a consuming project**"*. This is the
smallest change that restores the guardrail and costs one new fork-only file
(`.vscode/settings.json` — already in `aproda-sync.json → neverTouch`? **verify**: it is not currently
listed; add it so it never leaks into projects).

### Q-2 — Is `instructions/copilot-instructions.md` still the source? (blocks F-6)

| Option | Consequence |
|---|---|
| **A — keep "trimmed source" model** | Back-port all 6 registered Aproda entrypoint edits + the v1.2 label into the source; add a validator rule that the Aproda rows exist in both |
| **B — retire `copilotSource`** | Remove the key from `aldc.yaml`, drop `copilotEntrypointCoherence`, delete or archive `instructions/copilot-instructions.md`, stop syncing it |

**Recommendation: B.** Evidence that A has already failed in practice: 6 in-place edits over 3 months,
**zero** propagated to the source; the source is a full version behind and describes 4 agents where 11
exist. A two-file model with no generator and no enforcement has demonstrably not held. Retiring it also
removes a contradictory document from every consumer project. If A is chosen instead, it **requires** a
generator — hand-maintaining two copies is what produced F-6.

> Both options are upstream-affecting (`aldc.yaml` and `instructions/` are Core-owned). Record as a D-2
> in-place edit and flag as an upstream-PR candidate, as D-17 already does for the v1.2 drift-fix.

---

## Phase 1 — Install the missing rule (governance first)

### 1.1 New decision: **D-46 — Catalog synchronisation is part of a primitive change**

Proposed text for `.github/decisions.aproda.md`:

> ### D-46 — Adding or removing a primitive includes updating every catalog that enumerates it
>
> **Context.** The layer's two extension rules (D-2 net-new / in-place, D-4 `.aproda.` convention) are
> complete for *conflict avoidance* and silent on *discoverability*. An artifact can satisfy both
> perfectly and still be invisible to routing and to every reader, because ~4 catalog files enumerate
> primitives by hand and nothing obliges their update. The E-006 audit (2026-09-22) found this had
> happened to 5 of 19 layer artifacts in `readme.aproda.md`, to 10 of 21 skills in `skills/index.md`,
> to 4 of 11 agents in `agents/index.md`, and — shipped to consumers — to 12 of 12 workflows in
> `prompts/index.md`.
>
> **Decision.** A change that adds, removes, or renames a primitive is **not complete** until every
> catalog in the canonical list (below) reflects it. Enforced by `aldc-validate` (D-47) and re-checked
> at release time by `skill-aproda-aldc-release`.
>
> **Rejected alternative.** "Generate all catalogs from `aldc.yaml`." Attractive, but `aldc.yaml`
> deliberately does **not** enumerate Aproda primitives (F-9) and the catalogs carry prose value
> (routing hints, "loaded by", rationale) that no generator produces. A validated hand-maintained
> catalog is the pragmatic middle ground.

### 1.2 Canonical catalog list (the artefact the rule points at)

| Primitive added/removed | Catalogs that MUST be updated |
|---|---|
| **Skill** | `skills/index.md` · `.github/copilot-instructions.md` → Skills table · `.github/readme.aproda.md` → inventory (if `skill-aproda-*`) · `aldc.yaml` → `required`/`optional` (Core only) or `aproda` inventory (D-47) |
| **Agent** | `agents/index.md` · `.github/copilot-instructions.md` → Agent Routing + Quick routing guide · `.github/readme.aproda.md` → inventory (if `.aproda.`) · `aldc.yaml` |
| **Workflow** | `prompts/index.md` · `prompts/README.md` · `.github/copilot-instructions.md` → Workflows table · `.github/readme.aproda.md` → inventory (if `.aproda.`) · `aldc.yaml` |
| **Instruction** | `instructions/index.md` · `.github/copilot-instructions.md` → Auto-Applied Instructions table · `.github/readme.aproda.md` → inventory (if `.aproda.`) · `aldc.yaml` |
| **Any of the above** | `.github/copilot-instructions.md` header count + footer "Primitives" line · `docs/copilot-reference.md` → Workspace Structure tree |
| **In-place Upstream edit** | `.github/decisions.aproda.md` → D-7 register · `tools/aproda-sync/aproda-sync.json` → `inPlaceEdits` |

### 1.3 Wire the rule into the two skills

Concrete text in **§ Proposed skill content** below.

---

## Phase 2 — Make it falsifiable (validator)

### 2.1 New decision: **D-47 — `aldc-validate` covers catalogs, versions, and the Aproda inventory**

Three new rules, all starting as `warn` and promoted to `error` after the Phase 3 sweep:

| Rule | Check | Catches |
|---|---|---|
| `catalogCoherence` | Every file matching `agents/*.agent.md`, `skills/skill-*/SKILL.md`, `prompts/*.prompt.md`, `instructions/*.instructions.md` appears **by name** in its catalog, and every catalog row resolves to an existing file | F-3, F-4, F-5, F-13 |
| `versionCoherence` | Every `ALDC Core vX.Y` literal equals `core.version` major.minor. **Scope to Aproda-owned paths first** (`*.aproda.*`, `skill-aproda-*/**`, `.github/copilot-instructions.md`, `aldc.yaml`); allowlist inherited upstream files, otherwise it reports ~22 failures Aproda must deliberately not fix (Phase 4). Permanent allowlist for historical paths (`ALDC-Core-Spec-*.md`, `ALDC-Migration-*.md`, `docs/decisions/**`, `.github/plans/**`, `archive/**`, `packages/foundation/**`) | Findings 02 §5, R-2 |
| `aprodaInventoryCoherence` | Every `**/*.aproda.*` file and `skills/skill-aproda-*/` folder appears in `.github/readme.aproda.md`'s inventory table, and vice versa | F-3, F-9 |

### 2.2 Add an `aproda.inventory` block to `aldc.yaml` (optional but recommended)

`aldc.yaml` already carries `aproda.layerVersion`, `basePin`, `inventory`, `decisions`. Extending it with
an explicit primitive list makes the Aproda layer machine-checkable without polluting the Core
`required`/`optional` sets:

```yaml
aproda:
  # … existing keys …
  primitives:
    agents:      ["agents/al-translate-subagent.aproda.agent.md"]
    skills:      ["skills/skill-aproda-aldc/SKILL.md", "skills/skill-aproda-aldc-release/SKILL.md",
                  "skills/skill-aproda-ado/SKILL.md", "skills/skill-aproda-deploy-run-verify/SKILL.md",
                  "skills/skill-aproda-fkh/SKILL.md"]
    workflows:   ["prompts/al-doc-update.aproda.prompt.md"]
    instructions:["instructions/hitl-validation.aproda.instructions.md",
                  "instructions/aproda-aldc-steward.aproda.instructions.md"]
```

### 2.3 Register verification (R-3 from Findings 02)

Add to `skill-aproda-aldc-release`: before a layer release, **diff each `aproda-sync.json → inPlaceEdits`
path against the pinned upstream base**. A path that is byte-identical to upstream means the registered
edit is missing — that single comparison is stronger than any fingerprint heuristic, needs no extra
metadata, and is exactly what exposed the `aldc-validate` gap (Findings 02 §4) once it was finally run.
It would have caught it in June instead of three months later.

---

## Phase 3 — Sweep the files (fork-owned only)

Ordered by blast radius. Each step is one commit; each touching an Upstream file needs a D-7 register row.

> **Scope boundary (added 2026-09-23).** The `main` audit showed that ~22 of the drifted files are
> **unmodified upstream content** (Findings 02 §3). Those are deliberately **excluded** here and routed
> to Phase 4 instead. Editing them in the fork would trade conflict-free files for permanent merge-points
> (D-2) to fix a defect Aproda did not cause. Only `tools/aldc-validate/index.js` is forked anyway — it
> is the release gate, and that cost is justified.

| # | Action | Findings | Ships to projects? |
|---|---|---|---|
| 3.1 | Rewrite `prompts/index.md` from scratch — 12 actual workflows, correct version/date | F-4 | **yes** (`required.catalog`) |
| 3.2 | Fix `tools/aldc-validate/index.js` (4×) + `.github/actions/aldc-validate/action.yml` (1×). **Correct** register line 524 — it documents an edit that was never applied, so do not merely re-date it. Add the missing `action.yml` row and note the Phase-4 overlap | Findings 02 §4, R-1 | yes |
| 3.3 | Complete `.github/readme.aproda.md` inventory: add the 5 missing artifacts; unify paths to **one** layout with an explicit note about fork vs project; update the D-range claims (lines 279, 385) | F-3, F-10 | yes |
| 3.4 | Rewrite `agents/index.md` — 11 agents; add it to `aldc.yaml → required.catalog` so it is validated and synced like its siblings. **Leave the `v1.1` header to Phase 4** unless the content rewrite makes it unavoidable | F-5 | yes (after registration) |
| 3.5 | Execute Q-2's decision for `instructions/copilot-instructions.md`. Note: option B (retire `copilotSource`) also removes one inherited v1.1 file from the fork's surface without editing it | F-6 | yes |
| 3.6 | Execute Q-1's decision (`.vscode/settings.json` + D-5 amendment); add `.vscode/**` to `aproda-sync.json → neverTouch` | F-1, F-2 | no (fork-only) |
| 3.7 | Decide `docs/copilot-reference.md`: register it in `aldc.yaml` + fix the entrypoint's relative link, **or** fold its content into the entrypoint and delete it | F-11 | yes |
| 3.8 | Fix D-range references in `skills/skill-aproda-aldc/SKILL.md` (lines 8, 26); write the missing `### D-42` heading or correct register line 558 | F-10 | yes |
| 3.9 | Delete or document `.github/agents/test.agent.md` | F-12 | no |
| 3.10 | **`.claude/**` and `claude-plugin/**` are upstream-owned — do not delete.** 6 of the last 27 upstream commits touch `.claude/`, and `origin/main:.claude/agents/dredd.md` is already 9 lines ahead of the fork's copy. Deleting them guarantees a conflict on the next pull. Instead: (a) document in `readme.aproda.md` that they are upstream distributions Aproda does not maintain, and (b) resolve F-1 via Q-1 so Copilot stops reading them in the fork | F-1, F-8 | no |
| 3.11 | Correct `aldc.yaml → aproda.basePin` to the real merge-base **`4f3371f`** and drop the stale *"upstream == fork, in sync 2026-06-25"* comment; note that `origin/main` is 27 commits ahead | Findings 02 R-6 | yes |
| 3.12 | Decide whether `CLAUDE.md` is maintained at all (Aproda uses no Claude Code runtime). If kept, correct its primitive counts; if not, say so in one line at the top | Findings 02 §7 | no |

---

## Phase 4 — Upstream PR (inherited defects, not fixed in the fork)

Added 2026-09-23 after the `main` audit. These are **clean upstream files**; the fork must not touch them.

**Contents of one PR against ALDC Core**, finishing the abandoned v1.1 → v1.2 migration:

| Group | Files |
|---|---|
| Self-contradiction | `aldc.yaml` line 1 (`# ALDC Core Configuration v1.1` vs `core.version: "1.2.0"`) |
| Operational | `tools/aldc-validate/index.js` (4×), `.github/actions/aldc-validate/action.yml`, `scripts/install.js` (6×), `collections/al-development.collection.yml` |
| Catalogs | `agents/index.md`, `instructions/copilot-instructions.md`, `docs/instructions/copilot-instructions.md` |
| Documentation | `docs/getting-started.md`, `docs/al-development.md`, `docs/index.md`, `docs/index-es.md`, `docs/bc-agent-builder.md`, `docs/copilot-reference.md`, `docs/framework/{ALDC-Architecture-Diagrams,ALDC-Compliance-Model,ALDC-Manifesto,QUICKSTART}.md` |
| Explicitly **excluded** | `ALDC-Core-Spec-v1.1.md`, `ALDC-Migration-v1.0-to-v1.1.md`, `docs/decisions/**`, `.github/plans/**` — historical records; add a "superseded" banner to the v1.1 spec instead (R-8) |

**Why a PR and not a fork sweep** — three reasons, in order of weight:

1. **Merge economics.** ~22 files that currently merge cleanly would become permanent D-2 merge-points.
2. **Register load.** Each would need a D-7 row, inflating a register whose value depends on being short
   and reviewable.
3. **It is not Aproda's defect.** `origin/main` proves upstream has not fixed it in 27 commits and is
   unlikely to conflict with the PR — 0 commits touched `aldc-validate` or `agents/index.md`.

**Fallback if the PR is rejected or stalls:** keep the drift, and rely on R-2's allowlist so
`aldc-validate` does not report inherited failures as Aproda's. Do **not** sweep in the fork as a
consolation prize.

---

## Proposed skill content

### A. `skills/skill-aproda-aldc/SKILL.md` — replace the session's provisional Step 2.5

The session already inserted a "Step 2.5 — Update the catalogs" (Appendix A). It should be **replaced**
by this version once D-46/D-47 exist, so the skill cites decisions rather than anecdotes:

> ### Step 2.5 — Update the catalogs (D-46, mandatory)
>
> A primitive that follows D-2 and D-4 perfectly is still **invisible** until every catalog that
> enumerates it is updated. D-46 makes catalog synchronisation part of the change, not a follow-up.
>
> | You added/removed/renamed | Update these |
> |---|---|
> | Skill | `skills/index.md` · entrypoint Skills table · `readme.aproda.md` inventory (if `skill-aproda-*`) |
> | Agent | `agents/index.md` · entrypoint Agent Routing **and** Quick routing guide · `readme.aproda.md` inventory (if `.aproda.`) |
> | Workflow | `prompts/index.md` · `prompts/README.md` · entrypoint Workflows table · `readme.aproda.md` inventory (if `.aproda.`) |
> | Instruction | `instructions/index.md` · entrypoint Auto-Applied Instructions table · `readme.aproda.md` inventory (if `.aproda.`) |
> | Any | entrypoint header count + footer "Primitives" line · `docs/copilot-reference.md` Workspace Structure tree · `aldc.yaml` (`required`/`optional` for Core, `aproda.primitives` for layer) |
>
> **Verify, don't recall.** Re-open each catalog and confirm the row and the count. `aldc-validate`'s
> `catalogCoherence` rule (D-47) is the backstop; `skill-aproda-aldc-release` re-checks at release time.
> Neither substitutes for doing it here.
>
> **Two layouts, one table.** Catalog paths differ between fork (`skills/…`) and project
> (`.github/skills/…`). `readme.aproda.md`'s inventory uses the **project** layout; keep it consistent
> and never mix the two in one table.

Additionally in the same file:

- **Knowledge map** — add a row: *"Which catalogs must I update when adding a primitive? → D-46 +
  Step 2.5"*.
- **Lines 8 and 26** — replace the hard-coded `D-1..D-25` / `D-1..D-22` with `D-1…D-N (see the file)`
  so this class of drift cannot recur (F-10).
- **Explain mode** — add the fork-vs-project discovery asymmetry (F-1) as a core onboarding fact. It is
  currently stated only in `aproda-sync.json` comments, which no agent reads.

### B. `skills/skill-aproda-aldc-release/SKILL.md` — replace the session's provisional gate

Replace the provisional "Catalog consistency check" (Appendix A) with a decision-backed, two-part gate:

> ## Pre-release consistency gate (mandatory — D-46 / D-47)
>
> A layer release ships whatever is on disk to every consumer project, **including drift**. Run all three
> checks before bumping `aproda.layerVersion`. Any mismatch is a **release blocker**, fixed in the same
> change — never a follow-up PR.
>
> 1. **Catalog coherence.** `tools/aldc-validate` must pass its `catalogCoherence` rule. If the rule is
>    not yet implemented, diff the four primitive folders against `skills/index.md`, `agents/index.md`,
>    `prompts/index.md`, `instructions/index.md`, `.github/copilot-instructions.md`, and
>    `docs/copilot-reference.md` by hand.
> 2. **Version coherence.** `versionCoherence` must pass: no `ALDC Core vX.Y` literal outside the
>    historical allowlist may disagree with `aldc.yaml → core.version`.
> 3. **Register verification.** Every `aproda-sync.json → inPlaceEdits` path must still carry its
>    registered edit. *Why this exists:* on 2026-09-22 the D-7 register (line 524) was found claiming a
>    2026-06-25 fix to `tools/aldc-validate/index.js` that was absent from the file — so ~3 months of
>    releases certified `v1.1 COMPLIANT` for a `1.2.0` layer. An unverified register is a claim, not a
>    fact.
>
> Record the outcome in `.github/CHANGELOG.aproda.md` (e.g. *"catalogs, versions and D-7 register
> verified"*) so a reviewer need not re-derive it.

Also add a short **"What ships vs what stays"** section — currently implicit in `aproda-sync.json` and a
recurring source of confusion (F-3, F-11):

> | Category | Ships to projects | Source of truth |
> |---|---|---|
> | `.aproda.*` files, `skill-aproda-*/` folders | ✅ automatic | `includeGlobs` |
> | Core framework (`aldc.yaml` required/optional) | ✅ if `includeAldcFramework: true` | `aldc.yaml` |
> | In-place Upstream edits | ✅ fork variant wins | `inPlaceEdits` + D-7 register |
> | `skill-aproda-aldc-release`, `tools/aproda-vscode-extension/`, `tools/aproda-sync/fleet/`, `_A-ALDC-Plans/` | ❌ fork-only | `neverTouch` |
> | Anything unlisted (incl. `docs/copilot-reference.md`) | ❌ silently absent | allowlist default-deny |
>
> The last row is the trap: a file can be linked from the entrypoint and still never reach a project.

---

## Sequencing summary

```
Phase 0  Q-1 (fork discovery) + Q-2 (copilotSource)      <- maintainer decision, blocks 3.5/3.6
Phase 1  D-46 + canonical catalog list + skill wiring     <- the rule
Phase 2  D-47 validator rules + aproda.primitives + R-3   <- the enforcement
Phase 3  3.1 -> 3.12 fork-owned cleanup                   <- protected against recurrence by 1+2
Phase 4  one upstream PR (inherited v1.1 drift)           <- independent, can run in parallel
```

Phases 1 and 2 are the durable value. Phase 3 without them is a one-off cleanup that the next audit will
have to repeat. **Phase 4 is independent of all of them** — it can be opened at any time and should not
block the fork work; its only coupling is the `aldc-validate` overlap noted in 3.2.

---

## Appendix A — Edits already made in the 2026-09-21/22 session

Made **before** this plan existed, and **without** the D-16 guardrail firing (F-2). They need retroactive
steward review and D-7 register rows where they touch Upstream files.

| File | Change | Upstream? | Register row needed |
|---|---|---|---|
| `agents/al-conductor.agent.md` | Added `microsoft-learn` to `tools:` | ✅ | **yes** |
| `agents/al-triage.agent.md` | `al_get_diagnostics` → `al_getdiagnostics` (frontmatter + prose) | ✅ | **yes** |
| `agents/al-developer.agent.md` | Same rename (frontmatter + 3 prose sites) | ✅ | **yes** |
| `agents/dredd.agent.md` | Same rename; added missing `todo` tool | ✅ | **yes** |
| `agents/al-review-subagent.agent.md` | Removed duplicate `al_get_diagnostics` | ✅ | **yes** |
| `.github/copilot-instructions.md` | Agent Routing (+`al-triage`, +`al-agent-builder`), Workflows (+`al-doc-update` 🟦), Skills (+`skill-manifest`, +3 Aproda 🟦), Instructions (+`al-agent-toolkit`, +2 Aproda 🟦), header + footer counts | ✅ | **yes** (extends the existing D-7 rows) |
| `instructions/index.md` | 7 → 10 instructions incl. both Aproda rows | ✅ | **yes** |
| `skills/index.md` | Added `skill-manifest`, 3 BC Agents Pack, 5 Aproda 🟦, 1 meta; catalog-update step | ✅ | **yes** |
| `docs/copilot-reference.md` | Title v1.1 → v1.2; rewrote Workspace Structure tree; new "AL/BC Tools & MCP Servers" section; BC Agents Pack additions | ✅ | **yes** |
| `skills/skill-aproda-aldc/SKILL.md` | Provisional Step 2.5 | ❌ Aproda net-new | no — **supersede** with § A above |
| `skills/skill-aproda-aldc-release/SKILL.md` | Provisional catalog gate | ❌ Aproda net-new (`neverTouch`) | no — **supersede** with § B above |

### A note on the tool-name fix

`al_get_diagnostics` (with the extra underscore) does **not** exist; the registered tool is
`al_getdiagnostics`. The wrong name was present in `al-triage`, `al-developer`, `dredd` and — duplicated
alongside the correct one — in `al-review-subagent`, i.e. those agents' `tools:` grants silently resolved
to nothing for diagnostics. `al-conductor` and `al-implement-subagent` were already correct.

**The identical defect still exists in `packages/foundation/agents/`** (`al-developer`,
`al-review-subagent`, `al-triage`, `dredd`) — left untouched per the maintainer's out-of-scope
instruction, and noted here only so the exclusion is a recorded decision rather than an oversight.
