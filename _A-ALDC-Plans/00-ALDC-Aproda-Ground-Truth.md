# ALDC × Aproda — Ground Truth

> **Fork-only orientation document.** Lives under `_A-ALDC-Plans/` (in `aproda-sync.json → neverTouch`),
> so it never reaches a consumer project. Read this first when working **on the framework**; it is not
> needed when building an AL extension *with* the framework.
>
> **Governed by [D-44](../.github/decisions.aproda.md)** — the fourth self-knowledge artifact under D-16,
> referenced from `skill-aproda-aldc`'s knowledge map.
>
> **Last verified:** 2026-09-23 · **Layer:** `1.2.0_aproda.17` · **Core:** `1.2.0`

---

## 0. How to use this file

It is deliberately **not** a fifth content store. It answers three questions the existing documents do
not:

1. **What is durably true** about this repo's structure (§2) — facts that survive every fix.
2. **Where does authoritative knowledge live** (§3) — so nothing gets duplicated here.
3. **What is currently broken or in flight** (§4) — with the commands to re-verify it (§6), because a
   state section without a verification path rots into folklore.

**Rule for maintaining this file:** §2, §3, §5 are durable — change them only when the architecture
changes. §4 expires; re-verify with §6 before trusting it, and update the "Last verified" date.

---

## 1. What this repository is

A **fork of ALDC** (AL Development Collection, upstream by Javier Armesto) carrying the **Aproda layer**
on top. Aproda uses **GitHub Copilot only** — not Claude Code, not Codex.

| Branch | Meaning |
|---|---|
| `main` | Upstream ALDC, **no** Aproda content. Tracks `origin/main`. |
| `aproda` | The fork's delivery branch. Base for releases (`v<layerVersion>` tags, CI-gated). |
| `feature/*` | Work branches. |

The layer is distributed to consumer projects by an **allowlist overlay syncer**
(`tools/aproda-sync/`) and by the internal **VS Code extension** (`tools/aproda-vscode-extension/`) —
**not** by git subtree.

---

## 2. Durable facts

### 2.1 Two layouts — the single most confusing thing in this repo

| Side | Toolkit primitives live in | `aldc.yaml → toolkitRoot` |
|---|---|---|
| **Fork** (this repo) | repo **root**: `agents/`, `skills/`, `instructions/`, `prompts/`, `docs/`, `tools/` | `"."` |
| **Consumer project** | under **`.github/`**: `.github/agents/`, `.github/skills/`, … | `".github"` |

Only a few files stay under `.github/` on **both** sides: `copilot-instructions.md`, `plans/`, and the
`*.aproda.md` companions (`readme`, `decisions`, `site-profile`, `CHANGELOG`, `onboarding`).

`aldc.yaml` is the sole **dual-variant** file: copied verbatim except the `toolkitRoot` line, which the
syncer rewrites per side. Do not hand-maintain it.

> **Consequence that bites:** documentation written in one layout is wrong in the other.
> `readme.aproda.md`'s inventory table uses *project* paths; the fork stores those files at root.
>
> **Live example (verified 2026-09-23):** every `../../…` link in
> [`../skills/skill-aproda-aldc/SKILL.md`](../skills/skill-aproda-aldc/SKILL.md) assumes the project
> layout. From `.github/skills/skill-aproda-aldc/` they resolve to `.github/readme.aproda.md` ✓; from the
> fork's `skills/skill-aproda-aldc/` they resolve to the **repo root**, where no `*.aproda.md` companion
> exists. The links are therefore **broken in the fork and correct in a project** — which is exactly why
> nobody notices. Assume nothing about a relative path until you know which layout you are in.

### 2.2 Four parallel distributions of the same primitives

| Tree | Owner | Aproda content | Touch it? |
|---|---|---|---|
| root `agents/`, `skills/`, `instructions/`, `prompts/` | **Aproda + upstream** | ✅ full | **yes — this is authoritative** |
| `.claude/agents/`, `skills/`, `rules/` | **upstream** (actively maintained) | ❌ none | no — deleting guarantees a pull conflict |
| `claude-plugin/` | **upstream** | ❌ none | no |
| `packages/foundation/` | upstream (APM packaging) | ❌ none | no — out of scope at Aproda |

Evidence that `.claude/` is alive upstream: 6 of the last 27 upstream commits touch it, and
`origin/main:.claude/agents/dredd.md` is 9 lines ahead of the fork's copy.

### 2.3 What VS Code actually loads — and where it differs by layout

| Location | Loaded in a **consumer project**? | Loaded in **this fork**? |
|---|---|---|
| `.github/copilot-instructions.md` | ✅ | ✅ |
| `.github/instructions/`, `.github/skills/`, `.github/agents/`, `.github/prompts/` | ✅ | ❌ — those folders don't exist here |
| root `agents/`, `skills/`, `instructions/`, `prompts/` | n/a | ❌ **not discovered** |
| `.claude/rules/`, `.claude/skills/`, `.claude/agents/` | — | ✅ **these are what Copilot reads** |

**So in the fork, Copilot sees the upstream Claude tree — which contains zero Aproda primitives.**
The D-16 steward guardrail therefore does **not** fire on layer edits made here. Verify with §6-C.

> `readme.aproda.md` claims discovery works "without any `.vscode/settings.json` registration" (D-5).
> That is true **for projects only**. The statement is unqualified and therefore wrong for the fork.

### 2.4 The extension rules

| Intent | Mechanism | Conflicts on upstream merge? |
|---|---|---|
| New capability | **net-new** file with `.aproda.` infix, or `skill-aproda-*` folder | ❌ never |
| "Additionally always do X" | **stacking** — new `.aproda.instructions.md` with matching `applyTo` | ❌ never |
| Change/relax upstream behaviour | **in-place edit** of the original | ✅ **deliberately** — the conflict *is* the change-log (D-2) |

The `.aproda.` infix keeps the type suffix intact (`.prompt.md`, `.instructions.md`, `.agent.md`) so
discovery and `applyTo` keep working. There is **no** `aproda/` override folder and **no** agent clones.

**The missing third rule** (E-006 F-7, proposed as D-45): a primitive is not "added" until every catalog
that enumerates it is updated — see §5.

### 2.5 Sync model — default-deny

`tools/aproda-sync/aproda-sync.json` is an **allowlist**. A path not matched is invisible in both
directions.

| Category | Ships to projects | Governed by |
|---|---|---|
| `**/*.aproda.*`, `skills/skill-aproda-*/**` | ✅ automatic | `includeGlobs` |
| Core framework files listed in `aldc.yaml` `required`/`optional` | ✅ (`includeAldcFramework: true`) | `aldc.yaml` |
| In-place upstream edits | ✅ fork variant wins | `inPlaceEdits` + D-7 register |
| `_A-ALDC-Plans/`, `plans/`, `documentation/`, `tools/aproda-vscode-extension/`, `skill-aproda-aldc-release/`, `*.code-workspace`, AL-Go files | ❌ never | `neverTouch` |
| **Anything unlisted** | ❌ silently absent | allowlist default |

> **The trap:** a file can be linked from `copilot-instructions.md` and still never reach a project
> (e.g. `docs/copilot-reference.md` today). Linked ≠ shipped.

### 2.6 Tool-name traps (verified against the live tool registry)

| Correct | Wrong but plausible | Note |
|---|---|---|
| `al_getdiagnostics` | ~~`al_get_diagnostics`~~ | The wrong form silently resolves to **nothing** — no error. Was present in 5 agent frontmatters. |
| `al-symbols-mcp/*` | — | Community MCP server, **optional**, not always registered. The wildcard resolves to zero tools when absent — again silently. |
| `bclsp_*` | — | Requires the separate `SShadowSdk.al-lsp-for-agents` extension, not the AL Language extension. |

---

## 3. Knowledge map — where the truth lives

**Link, never duplicate.** If a fact belongs in one of these, it does not belong in this file.

| Question | Authoritative source |
|---|---|
| *How* does the layer extend ALDC? (conventions, naming) | [`../.github/readme.aproda.md`](../.github/readme.aproda.md) |
| *What* has Aproda added? (inventory) | `readme.aproda.md` → "Aproda layer inventory" (D-17) |
| *Why* is it built this way? (D-1…D-41) | [`../.github/decisions.aproda.md`](../.github/decisions.aproda.md) |
| Which upstream files did we edit in place? | `decisions.aproda.md` → **Upstream edits register** (D-7) |
| Infra facts (K: drive, NST servers, SRP, remote-PS) | [`../.github/site-profile.aproda.md`](../.github/site-profile.aproda.md) |
| How do I explain/extend the layer? | [`../skills/skill-aproda-aldc/SKILL.md`](../skills/skill-aproda-aldc/SKILL.md) |
| How do I release the layer or the VSIX? | [`../skills/skill-aproda-aldc-release/SKILL.md`](../skills/skill-aproda-aldc-release/SKILL.md) — fork-only |
| Runtime deploy/test cycle against BC | [`../skills/skill-aproda-deploy-run-verify/SKILL.md`](../skills/skill-aproda-deploy-run-verify/SKILL.md) |
| ADO work items → `req_name`, PR/work-item CLI | [`../skills/skill-aproda-ado/SKILL.md`](../skills/skill-aproda-ado/SKILL.md) |
| Configuration values (versions, pins, BCQuality) | [`../aldc.yaml`](../aldc.yaml) — via `#aldcConfiguration`, never guess |
| Onboarding (de) | [`../.github/onboarding.aproda.md`](../.github/onboarding.aproda.md) |
| Consistency audit + remediation plan | [`E-006-layer-visibility-and-version-consistency/`](E-006-layer-visibility-and-version-consistency/README.md) |

---

## 4. Current state — ⚠️ expires, verify with §6

*As of 2026-09-23. Each row names the check that confirms or retires it.*

| # | Fact | Impact | Verify |
|---|---|---|---|
| S-1 | Copilot loads `.claude/` in the fork; **0 of 10 Aproda primitives visible** while working here | D-16 guardrail dead in the fork | §6-C |
| S-2 | Fork is **27 commits / 340 files / ~47k lines** behind `origin/main` | Upgrade risk grows; unreviewed upstream changes | §6-A |
| S-3 | `aldc.yaml → aproda.basePin` says `a900263` "in sync 2026-06-25"; real merge-base is **`4f3371f`** | Pin misleads upgrade planning | §6-A |
| S-4 | Version drift v1.1/v1.2 is **inherited**: on `main` 43× v1.1 (24 files) vs 6× v1.2 (3 files); even `main:aldc.yaml` contradicts itself | Fix belongs **upstream**, not in the fork | §6-B |
| S-5 | `tools/aldc-validate/index.js` is **byte-identical to upstream** — the D-7 register (line 524) claims a fix that was never applied | Every release certifies "v1.1 COMPLIANT" for a 1.2.0 config | §6-D |
| S-6 | **20 of 21** `inPlaceEdits` are genuine; only S-5 is missing | Register is sound; the *verification step* is what's missing | §6-D |
| S-7 | Catalogs drift silently: `prompts/index.md` still describes an obsolete 18-workflow set (v2.11.0 era) **and ships to every project** | Consumers get a wrong catalog | §6-E |
| S-8 | `readme.aproda.md` inventory is missing 5 of 19 layer artifacts | The self-declared index is incomplete | §6-E |
| S-9 | Decision-range claims are stale everywhere (`D-1…D-27`, `D-1..D-22`); actual max is **D-41**, and **D-42 is cited but never defined** | Cross-references mislead | §6-F |

Open design decisions blocking remediation: **Q-1** (how the fork exposes the toolkit to Copilot) and
**Q-2** (is `instructions/copilot-instructions.md` still the `copilotSource`?) — both in
[`E-006-plan.md`](E-006-layer-visibility-and-version-consistency/E-006-plan.md) Phase 0.

---

## 5. Working rules

**Before changing anything in the Aproda layer** (`*.aproda.*`, `skill-aproda-*/**`):

1. Load `skill-aproda-aldc`; identify the governing **D-entry**; state whether the change *adds* or
   *relaxes* a deliberate decision; **get explicit confirmation** (D-16).
   *Note S-1: this guardrail does not auto-fire in the fork — apply it manually.*
2. Choose the mechanism per §2.4 (net-new vs in-place).
3. **Update the catalogs** — the rule that is missing today (proposed D-45):

   | Added/removed | Update |
   |---|---|
   | Skill | `skills/index.md` · entrypoint Skills table · `readme.aproda.md` inventory (if `skill-aproda-*`) |
   | Agent | `agents/index.md` · entrypoint Agent Routing **and** Quick routing guide · inventory (if `.aproda.`) |
   | Workflow | `prompts/index.md` · `prompts/README.md` · entrypoint Workflows table · inventory (if `.aproda.`) |
   | Instruction | `instructions/index.md` · entrypoint Auto-Applied table · inventory (if `.aproda.`) |
   | Any | entrypoint header count + footer "Primitives" · `docs/copilot-reference.md` Workspace Structure · `aldc.yaml` |

4. **Record it**: D-entry in `decisions.aproda.md`; if an upstream file was edited in place, add a row to
   the D-7 register **and** to `aproda-sync.json → inPlaceEdits`.
5. **English** for all persisted `.github/**` artifacts.
6. **Flow back to the fork** — a project-local edit is not adopted until it reaches the fork.

**Inherited upstream defects:** do **not** fix them in the fork. Each in-place edit converts a
conflict-free file into a permanent merge-point. Propose an upstream PR instead. The one justified
exception is `tools/aldc-validate/index.js` (release gate).

**This is an ephemeral workspace.** `C:\_EphemeralWorkspace\...` can be reset without warning; local
commits are **not** a backup. Push to a remote branch early and often. Recovery path if it happens:
VS Code Local History at `%APPDATA%\Code\User\History` — it survives the reset and holds even
never-committed files.

---

## 6. Verification snippets

Run from the repo root. All read-only.

**A — upstream gap & base pin**
```powershell
git rev-list --count 4f3371f..origin/main          # commits behind
git merge-base main aproda                          # real base (compare to aldc.yaml basePin)
git diff --stat 4f3371f origin/main | Select-Object -Last 1
```

**B — version drift on upstream**
```powershell
git grep -n -E 'ALDC Core v1\.[0-9]' main -- ':!archive'
git show main:aldc.yaml | Select-Object -First 6    # line 1 vs core.version
```

**C — what Copilot loads here**
```powershell
Get-ChildItem .claude\agents, .claude\skills, .claude\rules -Name
# Compare against agents\, skills\, instructions\ — the delta is what is invisible in the fork.
```

**D — D-7 register reality check**
```powershell
# For each inPlaceEdits path: identical to main => the registered edit is MISSING
$p='tools/aldc-validate/index.js'
((git show "main:$p") -join "`n") -ceq ((git show "aproda:$p") -join "`n")
```

**E — catalog coherence**
```powershell
(Get-ChildItem prompts\*.prompt.md).Count           # vs the count claimed in prompts\index.md
(Get-ChildItem skills -Directory).Count             # vs skills\index.md
(Get-ChildItem agents\*.agent.md).Count             # vs agents\index.md
```

**F — decision numbering**
```powershell
(Select-String -Path .github\decisions.aproda.md -Pattern '^### D-\d+').Count
Select-String -Path .github\decisions.aproda.md -Pattern 'D-4[0-9]'
```

---

## 7. What does **not** belong in this file

- **Decisions** → `decisions.aproda.md` (a D-entry, with rationale and rejected alternative).
- **The artifact inventory** → `readme.aproda.md` (D-17 declares it the single index).
- **Infra values** (servers, paths, credentials) → `site-profile.aproda.md`.
- **How-to knowledge** → the relevant `skill-aproda-*`.
- **Findings with a remediation plan** → a folder under `_A-ALDC-Plans/`, like E-006.

If something here starts duplicating one of those, delete it here and link instead — the duplication
*is* the failure mode this repo keeps hitting.

---

## 8. Reading order for a new contributor

1. [`../.github/onboarding.aproda.md`](../.github/onboarding.aproda.md) — de, practical setup
2. This file §1–§3 — orientation and where truth lives
3. [`../.github/readme.aproda.md`](../.github/readme.aproda.md) — what the layer adds
4. [`../.github/decisions.aproda.md`](../.github/decisions.aproda.md) — skim D-1…D-7, then on demand
5. §4 here — what is currently broken, before you trip over it
