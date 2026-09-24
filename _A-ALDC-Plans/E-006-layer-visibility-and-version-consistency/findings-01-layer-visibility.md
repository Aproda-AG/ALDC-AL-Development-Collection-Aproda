# Findings 01 — Aproda Layer Visibility & Catalog Consistency

> Task 1: *"Is the repo consistent, and is the Aproda ALDC layer cleanly contained in the corresponding
> instructions and indexes?"*
>
> Verdict: **No.** One blocker-class structural finding (F-1/F-2) plus a consistent pattern of catalog and
> inventory drift, all traceable to a single missing governance rule (F-7).

---

## F-1 🔴 In the fork repo, VS Code Copilot loads `.claude/` — not the root toolkit folders

### The two layouts

`tools/aproda-sync/aproda-sync.json` (lines 18–42) documents the intended split:

| Side | Toolkit primitives live at |
|------|----------------------------|
| **Fork** (this repo) | repo **root**: `agents/`, `skills/`, `instructions/`, `prompts/` |
| **Consumer project** | under **`.github/`**: `.github/agents/`, `.github/skills/`, … |

This is confirmed by `aldc.yaml → toolkitRoot: "."` (fork) vs the manifest's `layouts.project.base: ".github"`.

**Consequence:** VS Code's default customization discovery targets `.github/…`. In a *consumer project*
that matches perfectly. **In the fork it matches nothing** — `.github/` here contains only
`copilot-instructions.md`, `plans/`, the `*.aproda.md` companions, `actions/`, `workflows/`, `audits/`,
and a stray `agents/test.agent.md`. There is no `.github/instructions/`, no `.github/skills/`,
no `.github/prompts/`.

### What Copilot actually loaded in this session

Empirical evidence from this very conversation's customization listing:

| Primitive | Loaded from | Count | Matches |
|-----------|-------------|-------|---------|
| Instructions | `.claude/rules/*.md` | 8 | `.claude/rules/` exactly |
| Skills | `.claude/skills/*/SKILL.md` | 15 | `.claude/skills/` exactly |
| Agents | `.claude/agents/*.md` | 10 | `.claude/agents/` exactly |
| Agents (extra) | `.github/agents/test.agent.md` | 1 | appeared as agent **`test`** |
| Entrypoint | `.github/copilot-instructions.md` | 1 | ✅ correct |
| Root `agents/`, `skills/`, `instructions/`, `prompts/` | — | **0** | **never loaded** |

Three independent confirmations that the source is `.claude/`, not root:

1. **Agent names.** The listing showed `al-conductor`, `al-architect`, `dredd`, … (lowercase, file-style).
   `.claude/agents/al-conductor.md` line 2 declares `name: al-conductor`.
   Root [agents/al-conductor.agent.md](agents/al-conductor.agent.md#L2) declares
   `name: AL Development Conductor` — that string **never appeared**.
2. **Frontmatter dialect.** `.claude/agents/al-conductor.md` carries `model: haiku` and
   `tools: Read, Glob, Grep, Write, Edit, Bash, Task, WebSearch, WebFetch` — Claude Code vocabulary.
   The root file carries `model: GPT-5.6 Terra (copilot)` and VS Code tool-group identifiers.
3. **Instruction dialect.** `.claude/rules/al-agent-toolkit.md` uses `paths:` frontmatter (Claude Code);
   VS Code reported it as `applyTo: **/*.al`, i.e. it parsed the Claude dialect.

### Why this is a blocker, not a curiosity

The maintainer's own constraint — *"we use GitHub Copilot only, not Claude Code or Codex"* — makes this
worse, not better. The tree that is **not** maintained for Aproda's runtime is the one the runtime reads.
Concretely, while working **in the fork**, Copilot sees:

| Aproda artifact | In root tree | In `.claude/` tree | Visible to Copilot in fork |
|---|---|---|---|
| `skill-aproda-aldc` | ✅ | ❌ | **no** |
| `skill-aproda-aldc-release` | ✅ | ❌ | **no** |
| `skill-aproda-deploy-run-verify` | ✅ | ❌ | **no** |
| `skill-aproda-ado` | ✅ | ❌ | **no** |
| `skill-aproda-fkh` | ✅ | ❌ | **no** |
| `skill-manifest` | ✅ | ❌ | **no** |
| `hitl-validation.aproda.instructions.md` | ✅ | ❌ | **no** |
| `aproda-aldc-steward.aproda.instructions.md` | ✅ | ❌ | **no** |
| `al-translate-subagent.aproda.agent.md` | ✅ | ❌ | **no** |
| `al-doc-update.aproda.prompt.md` | ✅ | ❌ | **no** |

**0 of 10 Aproda primitives are available to Copilot inside the fork.** Only
`.github/copilot-instructions.md` — which *describes* them in prose — is loaded.

> **Important scoping note:** consumer projects are **not** affected. There the layer is applied under
> `.github/` by the syncer / VS Code extension and discovery works as designed (D-5 is correct *for
> projects*). The defect is fork-local — but the fork is exactly where the layer is developed, which is
> what makes F-2 bite.

### Contradiction with the layer's own documentation

[.github/readme.aproda.md](.github/readme.aproda.md#L266) states:

> **Key property:** the `.aproda.` infix keeps the type suffix intact … so VS Code's default discovery and
> `applyTo` matching keep working **without any `.vscode/settings.json` registration**.

True in the project layout. **False in the fork layout**, which the document never distinguishes. D-5
("No `.vscode` discovery registration needed") is stated unconditionally and is therefore wrong for half
its own scope.

---

## F-2 🔴 The D-16 steward guardrail does not fire in the fork — self-evidenced

[instructions/aproda-aldc-steward.aproda.instructions.md](instructions/aproda-aldc-steward.aproda.instructions.md#L8)
declares `applyTo: "**/*.aproda.*, **/skill-aproda-*/**"` and mandates a **hard HITL stop** before any
Aproda-layer edit: surface the D-entry, confirm intent, then edit.

**During this session, two files matching that glob were edited:**

- `skills/skill-aproda-aldc/SKILL.md`
- `skills/skill-aproda-aldc-release/SKILL.md`

**The guardrail never fired.** No D-entry was surfaced, no confirmation was requested — because the
instruction lives in root `instructions/`, which Copilot does not load in the fork (F-1). The guardrail
protecting the layer is inoperative precisely where layer edits happen.

This is a falsifiable, reproducible demonstration of F-1's impact, not a theoretical risk.

---

## F-3 🟠 The self-declared Aproda index is incomplete (5 of 19 artifacts missing)

[.github/readme.aproda.md](.github/readme.aproda.md#L272) declares:

> This table **is** the Aproda index (D-17) — the one place to answer "what has Aproda added?". Keep it current.

The "Net-new artifacts" table (lines 276–292) lists **14** items. On disk there are **19**.

### Missing from the index

| Artifact | Path (fork layout) | Evidence it is live |
|---|---|---|
| ADO integration skill | `skills/skill-aproda-ado/` | Named in the Features table (line 18) and in D-38 of `decisions.aproda.md`; loaded by 3 agents |
| Fkh transport skill | `skills/skill-aproda-fkh/` | Named in the Features table (line 20); owns D-26, D-33, D-34, D-37 |
| Translation subagent | `agents/al-translate-subagent.aproda.agent.md` | Invoked by `al-conductor` (`agents:` frontmatter) and `al-developer` |
| Onboarding guide | `.github/onboarding.aproda.md` | Linked from `README.md` line 10 and from the VS Code extension walkthrough |
| Sync tool README | `tools/aproda-sync/README.aproda.md` | Present on disk, carries the `.aproda.` infix |

`skill-aproda-ado` and `skill-aproda-fkh` appear in the **Features** table at the top of the same file but
not in the **inventory** table — so the document contradicts itself.

### Secondary defect: the index uses consumer paths without saying so

Rows read `.github/skills/skill-aproda-deploy-run-verify/`, `.github/instructions/…`, `.github/prompts/…`
— the **project** layout. In the fork these live at `skills/…`, `instructions/…`, `prompts/…`. Three rows
in the same table (`tools/aproda-sync/fleet/`, `tools/aproda-vscode-extension/`,
`skills/skill-aproda-aldc-release/`) use fork paths. The table silently mixes both conventions.

---

## F-4 🟠 `prompts/index.md` is a v2.11.0 relic — and it ships to every project

[prompts/index.md](prompts/index.md) claims **"Available Workflows (18 files)"**, version `2.11.0`,
last updated 2026-02-06, and lists:

`al-diagnose`, `al-events`, `al-pages`, `al-permissions`, `al-translate`, `al-migrate`,
`al-performance`, `al-performance.triage`, `al-copilot-capability`, `al-copilot-promptdialog`,
`al-copilot-generate`, `al-copilot-test`

**None of these files exist.** The actual `prompts/` folder holds 12 workflows
(6 core + 5 BC Agents Pack + 1 Aproda). The obsolete set corresponds to `archive/v2.11.0/`.

**This is not fork-local cosmetics.** `aldc.yaml` lines 127–130:

```yaml
  catalog:
    - "skills/index.md"
    - "prompts/index.md"
    - "prompts/README.md"
```

With `aproda-sync.json → includeAldcFramework: true`, everything in `aldc.yaml`'s required/optional lists
is carried by the layer sync. **Every consumer project therefore receives a workflow catalog describing
18 workflows that do not exist**, while the 12 that do exist are undocumented there.

---

## F-5 🟠 `agents/index.md` is stale *and* unregistered

[agents/index.md](agents/index.md#L5) says `# Agents - ALDC Core v1.1`, lists **4 public + 3 subagents**.

Missing: `al-triage`, `dredd`, `al-agent-builder`, `al-translate-subagent.aproda`.

Additionally, `agents/index.md` appears **nowhere** in `aldc.yaml` — not in `required.catalog`
(which lists `skills/index.md`, `prompts/index.md`, `prompts/README.md`) and not in `required.agents`.
Consequences:

- `aldc-validate` never checks it → the staleness is structurally undetectable.
- It is **not part of the synced framework set** → consumer projects get `skills/index.md`,
  `prompts/index.md` and `instructions/index.md` but **no** `agents/index.md`. Asymmetric and unexplained.

---

## F-6 🟠 The declared entrypoint **source** carries none of the Aproda content

`aldc.yaml` lines 80–85:

```yaml
copilotEntrypoint: ".github/copilot-instructions.md"
copilotSource: "instructions/copilot-instructions.md"
copilotEntrypointMode: "trimmed"
```

So [instructions/copilot-instructions.md](instructions/copilot-instructions.md) is **not an orphan
duplicate** — it is the declared *source* from which the entrypoint is a deliberate lean subset
(`validation.rules.copilotEntrypointCoherence: warn`).

However:

| | Source (`instructions/copilot-instructions.md`) | Entrypoint (`.github/copilot-instructions.md`) |
|---|---|---|
| Core version | **v1.1** | v1.2 |
| Aproda skills rows | **none** | 5 (🟦) |
| Aproda instructions rows | **none** | 2 (🟦) |
| Aproda workflow row | **none** | 1 (🟦) |
| Primitive counts | 4 agents / 11 skills / 6 workflows / 7 instructions | 11 / 21 / 12 / 10 |

The D-7 register records **6 separate in-place edits** to `copilot-instructions.md`
([decisions.aproda.md](.github/decisions.aproda.md#L511) 511, 512, 523, 548 …) — all applied to the
**trimmed entrypoint only**. The source was never touched.

Because `instructions/copilot-instructions.md` **is** in `aldc.yaml → required.instructions` (line 137),
it syncs to consumer projects as `.github/instructions/copilot-instructions.md`. Projects therefore
receive a second, contradictory, Aproda-free, v1.1-labelled description of the framework sitting one
folder below the correct one.

> **Open design question for the maintainer:** is "trimmed subset" still the intended relationship, or
> has the entrypoint de facto become the source of truth? The answer decides whether the fix is
> *"back-port the Aproda rows into the source"* or *"retire `copilotSource` and make the entrypoint
> authoritative"*. Recommendation in `E-006-plan.md` § Phase 2.

---

## F-7 🟠 No rule requires catalog upkeep — this is the root cause of F-3…F-6

Searched for a documented obligation to update `*/index.md` when a primitive is added:

| Document | Mentions catalog/index upkeep? |
|---|---|
| `.github/readme.aproda.md` ("TL;DR — Extend Aproda ALDC — the two rules", lines 246–252) | ❌ — only "net-new vs in-place" |
| `.github/readme.aproda.md` § Naming convention (lines 256–266) | ❌ |
| `skills/skill-aproda-aldc/SKILL.md` Extend mode (Steps 0–4) | ❌ *(a Step 2.5 was added during this session — see Appendix A)* |
| `tools/aproda-sync/aproda-sync.json` | ❌ — only `inPlaceEdits` upkeep is called out |
| `.github/decisions.aproda.md` | ❌ — no D-entry covers catalogs |
| `skills/index.md` § "Creating New Skills" (original text) | ❌ — 5 steps, none about catalogs |

The two-rule TL;DR is *complete for conflict-avoidance* and *silent on discoverability*. An artifact that
follows both rules perfectly is still invisible to every reader and to routing until ~4 catalogs are
updated by hand — with nothing reminding anyone to do it.

**All of F-3, F-4, F-5, F-6 and the (now-fixed) gaps in `skills/index.md` / `instructions/index.md` /
`.github/copilot-instructions.md` are instances of this one missing rule.**

---

## F-8 🟡 Four parallel distributions of the same primitives

| Tree | Agents | Skills | Instructions | Purpose | Aproda content |
|---|---|---|---|---|---|
| root `agents/`,`skills/`,`instructions/`,`prompts/` | 11 | 21 | 10 | **GH Copilot distribution (authoritative)** | ✅ full |
| `.claude/agents/`,`skills/`,`rules/` | 10 | 15 | 8 | Claude Code distribution | ❌ none |
| `claude-plugin/agents/`,`skills/` | 10 | 15 | — | Claude Code *plugin* distribution | ❌ none |
| `packages/foundation/…` | 10 | 16 | 8 | APM package distribution — **out of scope** | ❌ none |

Aproda uses GitHub Copilot only, so the three non-authoritative trees look like dead weight at first
glance. **They are not — corrected 2026-09-23:**

- `.claude/` and `claude-plugin/` are **actively maintained upstream**. Six of the last 27 upstream
  commits touch `.claude/` (canonical Spec Agent, plugin packaging, BC29/AL18 workflows, Codex
  bootstrap), and `origin/main:.claude/agents/dredd.md` is already 9 lines ahead of the fork's copy.
- Deleting them in the fork would therefore **guarantee a conflict on the next upstream pull** and would
  be an in-place deletion of upstream-owned content (D-2) for no Aproda benefit.
- The real problem is not their existence but F-1: in the fork, Copilot reads `.claude/` **instead of**
  the authoritative root tree. Fix the discovery (Q-1), not the tree.

There is still no documented generator, sync, or drift check between root and `.claude/` — but that is
upstream's concern, not Aproda's.

> `packages/foundation/**` excluded from all recommendations per maintainer instruction. Note only that
> it carries the same class of defects (e.g. `packages/foundation/agents/index.md` also says v1.1), so if
> it is ever revived the same audit applies.

---

## F-9 🟡 Aproda primitives are invisible to `aldc-validate`

`aldc.yaml`'s `required`/`optional` inventory enumerates **10 agents, 16 skills, 11 workflows,
8 instructions** — i.e. exactly the ALDC Core set. The 10 Aproda primitives (F-1 table) appear **nowhere**.

Correct by one reading (Core manifest ≠ layer manifest; the layer is carried by
`aproda-sync.json → includeGlobs`). But the practical effect is that `tools/aldc-validate` **cannot
detect a missing, deleted, or renamed Aproda artifact**. The 2026-07-07 `skill-ado` → `skill-aproda-ado`
rename ([decisions.aproda.md](.github/decisions.aproda.md#L571) line 571) needed a manual "sync layer
audit" to catch exactly that class of problem.

**Recommendation:** add an `aproda:` inventory block to `aldc.yaml` (it already hosts
`aproda.layerVersion`, `basePin`, `inventory`, `decisions`) and have a validator check it — see
`E-006-plan.md` § Phase 3.

---

## F-10 🟡 Decision-range references are stale everywhere; D-42 is referenced but undefined

Actual state of [.github/decisions.aproda.md](.github/decisions.aproda.md): **41 `### D-N` headings**
(D-1 … D-41, numbered non-sequentially).

| Claim | Location | Reality |
|---|---|---|
| "live (D-1…D-27)" | `readme.aproda.md` line 279 | D-1…D-41 |
| "full decision record D-1…D-22" | `readme.aproda.md` line 385 | D-1…D-41 |
| "(why — decisions D-1..D-25)" | `skills/skill-aproda-aldc/SKILL.md` line 8 | D-1…D-41 |
| "every design decision, D-1..D-22" | `skills/skill-aproda-aldc/SKILL.md` line 26 | D-1…D-41 |

Additionally, the D-7 register line 558 cites **`D-2 / D-39 / D-42`** — but **no `### D-42` heading
exists**. A register row points at a decision that was never written down.

---

## F-11 🟡 `docs/copilot-reference.md` is linked from the entrypoint but never ships

`.github/copilot-instructions.md` § "Further Reference" links `[docs/copilot-reference.md](../docs/copilot-reference.md)`.

- The file is **not** in `aldc.yaml` `required`/`optional` (only `docs/templates/*` is listed).
- It is **not** in `aproda-sync.json` `includeFiles`/`includeGlobs`.

→ It never reaches a consumer project. Furthermore the relative link `../docs/…` resolves from
`.github/copilot-instructions.md` to **repo-root `docs/`**, whereas in the project layout the toolkit's
docs would live under `.github/docs/`. The link is therefore doubly broken downstream: wrong target and
missing file.

Since the 2026-09-21/22 session moved substantive reference content there (AL/BC tool inventory,
`al-symbols-mcp` caveats, workspace tree), this silently widens the gap.

---

## F-12 🟡 `.github/agents/test.agent.md` is a live stray agent

`.github/agents/` contains a single file, `test.agent.md`, described as
*"Describe what this custom agent does and when to use it."* — an unmodified template. It **is** loaded
and offered to users as agent `test` (confirmed in this session's agent listing).

It is not referenced by `aldc.yaml`, `readme.aproda.md`, `aproda-sync.json`, or any index.

---

## F-13 🟡 `skills/index.md` classification predates half the catalog

Before the session edits, `skills/index.md` listed **11 of 21** skills under "Required (7)" /
"Recommended (4)". Missing entirely: `skill-manifest`, the 3 BC Agents Pack skills,
`skill-contribution-assistant`, and all 5 Aproda skills.

Note the classification also disagrees with `aldc.yaml`, which places `skill-manifest` and
`skill-contribution-assistant` under `optional.skills` — the index had no "optional" tier at all.

---

## F-14 🟠 Two `.aproda.` companions never reach a consumer project

*Added 2026-09-23 after the first measurement against a real project (see "Reference-project verification" below).*

| File | Fork | Project |
|---|---|---|
| `readme.aproda.md` · `decisions.aproda.md` · `site-profile.aproda.md` | ✅ | ✅ |
| **`CHANGELOG.aproda.md`** | ✅ | ❌ |
| **`onboarding.aproda.md`** | ✅ | ❌ |

Both match `includeGlobs: "**/*.aproda.*"`, yet neither arrives:

- `CHANGELOG.aproda.md` is listed in `layouts.fork.dotGithub` but **not** in `includeFiles`.
- `onboarding.aproda.md` appears in **neither** list.

Consequence: `readme.aproda.md` — which *does* ship — points new contributors at an onboarding guide that
does not exist in their repo. The curated release notes (D-27) are likewise fork-only in practice,
although nothing says they are meant to be.

**Decision needed:** ship both, or declare them fork-only and remove the references from shipped
documents. Silently half-shipping is the worst of the three.

---

## F-15 🔴 Committed UTF-8 BOM silently disabled a custom agent

*Found 2026-09-23, triggered by a report from the reference project's own Copilot session.*

`agents/al-conductor.agent.md` started with `EF BB BF 2D 2D 2D` — a byte-order mark **before** the `---`
frontmatter delimiter. The YAML parser therefore never recognised the frontmatter, so VS Code fell back
to the file name: the agent appeared as `al-conductor` instead of `AL Development Conductor`, and its
declared `tools`, `model`, `agents` and `handoffs` were **never applied**.

**Scope:** 10 toolkit files carried a committed BOM.

| Files | |
|---|---|
| `agents/al-conductor.agent.md` | 🔴 frontmatter broken |
| `skills/skill-aproda-deploy-run-verify/` — `SKILL.md`, `references/build-deploy.md`, `references/runner.md`, `scripts/README.md` | `SKILL.md` has frontmatter → same risk |
| `.github/` — `copilot-instructions.md`, `decisions.aproda.md`, `readme.aproda.md`, `site-profile.aproda.md`, `onboarding.aproda.md` | no frontmatter → cosmetic, but propagates |

**It reached the reference project.** `.github/skills/skill-aproda-deploy-run-verify/SKILL.md`,
`.github/copilot-instructions.md` and `.github/readme.aproda.md` all carry the BOM in
`straub-medical-ag-base` — so this is not a fork-only artifact.

**Why it survived so long — every ordinary check is blind to it:**

| Method | Result |
|---|---|
| VS Code editor | invisible in the buffer |
| `Get-Content` / `Select-String` | invisible — PowerShell strips the BOM while decoding |
| `git show \| Select-Object -First 1` + `.StartsWith([char]0xFEFF)` | **reports "clean" on a file that has one** — this test was used first here and gave a false negative |
| Byte inspection | `EF BB BF` — the only reliable method |

The decisive proof of provenance was indirect: after stripping the BOMs, `git diff` listed **8 files that
had not been modified otherwise** — so the BOM was committed, not a local editor artifact.

**Resolved:** all 10 files rewritten as UTF-8 without BOM; `al-conductor.agent.md` now starts
`2D 2D 2D 0D 0A`. Detection command added as Ground-Truth §6-G.

> **This is independent of F-1.** `.claude/` being the discovery source in the fork was established by
> separate evidence (Claude-only `model: haiku`, the `.claude/rules` `paths:` dialect, 15 vs 21 skills).
> F-15 would break the agent **in any layout, including a consumer project** — which is exactly why it
> must not be filed under "fork-only".

---

## Reference-project verification (2026-09-23)

Everything above was found **inside the fork**. A real consumer repo — `straub-medical-ag-base`
(AL-Go, layer `1.2.0_aproda.17`, sync confirmed current) — was then measured for the first time. Three
findings stopped being theoretical:

| Finding | Status before | Evidence in the project |
|---|---|---|
| **F-4** wrong workflow catalog | suspected | `.github/prompts/index.md` claims **18** workflows, folder holds **12**, and **12 named workflows do not exist** (`al-diagnose`, `al-events`, `al-pages`, `al-permissions`, `al-translate`, `al-migrate`, `al-performance`, `al-performance.triage`, `al-copilot-{capability,promptdialog,generate,test}`) |
| **F-11** linked ≠ shipped | suspected | `docs/copilot-reference.md` is linked from the entrypoint and **absent** in the project |
| **F-5** `agents/index.md` unregistered | suspected | **Absent** in the project, while its three sibling catalogs shipped |

Equally important, two design properties were **confirmed working**: `skill-aproda-aldc-release` is
correctly absent (fork-only via `neverTouch`), and the project's own `skill-audit-trail` survived
untouched — the allowlist protects project content in both directions, exactly as D-18 intends.

> **Methodical conclusion.** "Ships to a project" cannot be verified from the fork. Three suspicions sat
> unresolved in this document until a reference repo was available. Any future layer audit should include
> one — the checklist is in Ground-Truth §7.7.

---

## Cross-cutting assessment

The layer's **governance design is sound**: an allowlist syncer with a self-identifying convention (D-4,
D-18), an explicit in-place-edit register (D-7), a HITL steward (D-16), a pinned base (D-17) and
CI-gated releases (D-25). That is a genuinely well-thought-out fork architecture.

What is missing is the **closing of the loop between "the artifact exists" and "the artifact is
discoverable"**:

1. No rule obliges catalog updates (F-7) →
2. so catalogs drift (F-3, F-4, F-5, F-6, F-13) →
3. no validator covers catalogs or Aproda artifacts (F-5, F-9) →
4. so the drift is never detected →
5. and it **ships**, because catalogs are in the synced framework set (F-4).

Plus one orthogonal structural defect (F-1/F-2) in which the fork's own runtime reads a different,
Aproda-free tree.

Remediation in [E-006-plan.md](E-006-plan.md).
