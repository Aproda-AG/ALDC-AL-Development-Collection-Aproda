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

> **Mitigation (2026-09-23, D-5 scope correction).** A settings-based fix is **not available**:
> `chat.instructionsFilesLocations` / `chat.agentFilesLocations` are deprecated and honoured only by the
> Local agent, and the supported discovery paths are fixed. Instead, the guardrail is restated as a short
> **pointer** in `.github/copilot-instructions.md` — the one channel demonstrably loaded in the fork.
> It is a pointer, not a copy; the rule itself stays in `instructions/aproda-aldc-steward.aproda.instructions.md`.
> **You still apply it consciously here** — nothing attaches it automatically to the file you are editing.

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

**The missing third rule** (E-006 F-7, proposed as D-46): a primitive is not "added" until every catalog
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

### 2.7 The UTF-8 BOM trap — a silent frontmatter killer

A byte-order mark before `---` makes the YAML frontmatter parser fail. VS Code then falls back to the
**file name**, so a custom agent shows up as `al-conductor` instead of `AL Development Conductor`, and
its `tools`, `model` and `agents` declarations are **never applied**.

What makes it vicious is that every normal way of looking finds nothing:

| Method | What it shows |
|---|---|
| VS Code editor | nothing — the BOM is invisible in the buffer |
| `Get-Content` / `Select-String` | nothing — PowerShell strips the BOM while decoding |
| `git show file \| Select-Object -First 1` | unreliable — decoding may drop it, so a naive `.StartsWith([char]0xFEFF)` test reports "clean" on a file that has one |
| **Byte inspection** | `EF BB BF 2D 2D 2D` instead of `2D 2D 2D` — **the only reliable check** |

**Found 2026-09-23: 10 toolkit files carried a committed BOM**, including
`agents/al-conductor.agent.md` and all four `skill-aproda-deploy-run-verify` files. Three of them had
already propagated into the reference project. All cleaned; verify with §6-G.

> This is **independent of F-1**. `.claude/` being loaded in the fork was proven by other evidence
> (Claude-only `model: haiku`, `.claude/rules` `paths:` dialect, 15 vs 21 skills). The BOM is a second,
> unrelated defect that would break the agent **in any layout, including a project**.

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
| S-10 | **Measured in a real project** (`straub-medical-ag-base`, 2026-09-23): its `prompts/index.md` claims 18 workflows, holds 12, and names **12 that do not exist** | 🔴 F-4 is an active customer-facing defect, not a risk | §7.5 |
| S-11 | `docs/copilot-reference.md` and `agents/index.md` are **absent** in that project | Linked ≠ shipped, proven (F-11, F-5) | §7.5 |
| S-12 | `CHANGELOG.aproda.md` and `onboarding.aproda.md` never reach a project despite matching `includeGlobs` | The onboarding guide is missing where newcomers work (**F-14**) | §7.5 |
| S-13 | **10 toolkit files carried a committed UTF-8 BOM** (incl. `agents/al-conductor.agent.md`, all 4 `skill-aproda-deploy-run-verify` files); 3 had already reached the reference project | Frontmatter silently unparsed → agent loses `name`/`tools`/`model` (**F-15**). *Cleaned 2026-09-23* | §6-G |

**Resolved since this table was written:** Q-1 → option **A′** (pointer in the entrypoint; settings route
rejected on evidence — D-5 scope correction). Q-2 → **keep** `instructions/copilot-instructions.md`
(upstream-maintained; deleting it would create a delete/modify conflict). The `trimmed` breakage that
followed is handled by **D-45** (`extended` mode). Remaining open decision: **Q-3** (release strategy).

---

## 5. Working rules

**Before changing anything in the Aproda layer** (`*.aproda.*`, `skill-aproda-*/**`):

1. Load `skill-aproda-aldc`; identify the governing **D-entry**; state whether the change *adds* or
   *relaxes* a deliberate decision; **get explicit confirmation** (D-16).
   *Note S-1: this guardrail does not auto-fire in the fork — apply it manually.*
2. Choose the mechanism per §2.4 (net-new vs in-place).
3. **Update the catalogs** — the rule that is missing today (proposed D-46):

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

**G — UTF-8 BOM (§2.7) — byte check, nothing else is reliable**
```powershell
Get-ChildItem agents,skills,instructions,prompts,.github -Recurse -File -Include *.md,*.yaml,*.json |
  Where-Object { $_.FullName -notmatch '\\node_modules\\' } | ForEach-Object {
    $fs=[IO.File]::OpenRead($_.FullName); $b=New-Object byte[] 3; $n=$fs.Read($b,0,3); $fs.Close()
    if ($n -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { 'BOM: ' + $_.FullName }
  }
```

---

## 7. Fork vs. project — what transfers, and what can only be checked in a real project

> Everything in E-006 was audited **inside the fork**. That is not the environment consumers run in.
> This section separates the three categories, so nobody chases a fork-only symptom in a customer repo —
> or, worse, assumes a shipped defect is fork-only.

### 7.1 Fork-only — do **not** look for these in a project

| Finding | Why it cannot occur in a project |
|---|---|
| **F-1** Copilot loads `.claude/`; Aproda primitives invisible | A project keeps the whole toolkit under `.github/`, which *is* a supported discovery path. Discovery works there by design. **Confirmed 2026-09-23 in `straub-medical-ag-base`: no `.claude/` folder exists at all**, and its Copilot session lists all 11 agents, ~21 skills and 10 instructions from `.github/` |
| **F-2** D-16 steward guardrail never fires | Direct consequence of F-1 |
| **F-8** Four parallel primitive trees | `.claude/`, `claude-plugin/`, `packages/foundation/` are upstream repo content; the overlay ships none of them |
| **F-12** `.github/agents/test.agent.md` | Fork-local stray file |
| Broken `../../` companion links | Those links resolve **correctly** in the project layout — they were only broken in the fork (§2.1) |

### 7.2 Ships to projects — fix once in the fork, every project benefits

| Finding | Reaches the project via | Consumer impact |
|---|---|---|
| **F-4** `prompts/index.md` lists 18 non-existent workflows | `aldc.yaml → required.catalog` | 🔴 **Highest** — every project carries a wrong workflow catalog today |
| **F-6** `instructions/copilot-instructions.md`: v1.1, no Aproda content | `required.instructions` | A second, contradicting framework description sits one folder below the real entrypoint |
| **F-3** `readme.aproda.md` inventory incomplete (5 of 19) | `includeFiles` | The self-declared index under-reports the layer |
| **F-13** `skills/index.md` incomplete | `required.catalog` | Skills catalog under-reports *(fixed this session)* |
| **F-10** stale D-ranges, dangling `D-42` | `includeFiles` | Cross-references mislead *(resolved this session)* |
| **F-9** validator blind to Aproda primitives | `inPlaceEdits` | A missing or renamed Aproda artifact is undetectable |
| v1.1 banner in `aldc-validate` | `inPlaceEdits` | Every project CI reports a false compliance version |
| **D-45** `extended` entrypoint mode | `aldc.yaml` + `inPlaceEdits` | Required wherever the entrypoint is extended — i.e. every Aproda project |

### 7.3 Only verifiable in a real project repo — **first measured 2026-09-23**

> Reference project: `straub-medical-ag-base` (AL-Go repo, layer `1.2.0_aproda.17`). Sync confirmed
> current — it already carries the A′ pointer added the same day. These rows are no longer assumptions.

| # | What to check | Result |
|---|---|---|
| P-1 | `toolkitRoot` rewritten to `.github` | ✅ `".github"` — the dual-variant rewrite works |
| P-2 | `.github/instructions\|agents\|prompts\|skills` exist | ✅ all four (13 / 11 / 14 / 22 entries) |
| P-2b | Aproda primitives arrived | ✅ 4 × `skill-aproda-*`, both `.aproda.instructions.md`, `al-translate-subagent.aproda.agent.md`, `al-doc-update.aproda.prompt.md` |
| P-3 | The two Aproda instructions fire on their globs | ⏳ needs an interactive Copilot session in that repo |
| P-4 | `.github/` at the real git root (D-19) | ✅ AL-Go repo, `.github` at root |
| P-5 | **Linked ≠ shipped** | ❌ **confirmed** — `docs/copilot-reference.md` and `agents/index.md` absent (§7.5) |
| P-6 | Relative links resolve in project layout | ⏳ open |
| P-7 | BCQuality `home` resolves | ⏳ open — needs the clone present next to that repo |
| P-8 | AL-Go coexistence | ✅ `.AL-Go/`, `AL-Go-Settings.json`, `Test *.settings.json` untouched — the project even keeps its **own** `.AL-Go/settings.aproda.md` |
| P-9 | `memory.md` + `plans/` present | ✅ `plans/memory.md` + 7 requirement folders |
| P-10 | Validator green against the project | ⏳ open |

**The allowlist behaves exactly as designed** — two confirmations worth recording:
`skill-aproda-aldc-release` is **absent** in the project (fork-only via `neverTouch`) ✅, and the
project's **own** `skill-audit-trail` survived untouched ✅. Default-deny protects project content in
both directions.

### 7.4 Two concrete path findings (verified 2026-09-23)

**(a) `aldc.yaml → external.bcquality.home` is project-correct and fork-wrong.**

```text
configured   : ../../BCQuality-Aproda
from repo    : C:\_EphemeralWorkspace\BCQuality-Aproda          [missing]
from .github : C:\_EphemeralWorkspace\<user>\BCQuality-Aproda   [EXISTS]
```

The value assumes resolution relative to `.github/` — the project layout. Same class as the broken skill
links in §2.1: **correct in a project, wrong in the fork, and therefore unnoticed.**

**(b) `aldc.code-workspace` (fork-local only) points at a folder that does not exist.** It declares
`../bcquality`, while the clone is named `BCQuality-Aproda` — the second workspace root is dead, which is
why BCQuality never surfaced during this audit. **Scope corrected 2026-09-23:** this is **fork-only**.
The template that projects actually receive, `tools/aproda-sync/templates/workspace.seed.jsonc`, already
carries the correct `../BCQuality-Aproda`, and `*.code-workspace` is in `neverTouch`, so no project is
affected.

**Path-resolution rule** (`tools/aldc-validate/index.js:54`):

```js
const root = cfg.toolkitRoot === "." ? "" : cfg.toolkitRoot + "/";
```

`aldc.yaml` therefore carries **two deliberate path conventions**; mixing them up is the trap:

| Convention | Examples | Resolution |
|---|---|---|
| **toolkit-relative** (no prefix) | `specFile`, `validator`, `copilotSource`, `required.*` | prefixed with `toolkitRoot` → correct in both layouts |
| **repo-root absolute** (`.github/…`) | `copilotEntrypoint`, `plans.root`, `inventory`, `decisions` | used as-is; correct because these files live under `.github/` in **both** layouts |

A new key must consciously pick one. `external.bcquality.home` belongs to neither — it is the exception
that currently breaks.

### 7.5 What the reference project proved (2026-09-23)

Three findings stopped being theoretical, and one is new.

| Finding | Evidence in `straub-medical-ag-base` |
|---|---|
| **F-4** wrong workflow catalog | `.github/prompts/index.md` claims **18 workflows**; the folder holds **12**. **12 listed workflows do not exist**: `al-diagnose`, `al-events`, `al-pages`, `al-permissions`, `al-translate`, `al-migrate`, `al-performance`, `al-performance.triage`, `al-copilot-{capability,promptdialog,generate,test}` |
| **F-11** linked ≠ shipped | The entrypoint links `docs/copilot-reference.md`; the file **does not exist** in the project |
| **F-5** `agents/index.md` unregistered | **Absent** in the project — it is in no `aldc.yaml` list, while its three sibling catalogs shipped |

**New — F-14: two `.aproda.` companions never reach a project.**

| File | Fork | Project |
|---|---|---|
| `readme.aproda.md` · `decisions.aproda.md` · `site-profile.aproda.md` | ✅ | ✅ |
| **`CHANGELOG.aproda.md`** | ✅ | ❌ |
| **`onboarding.aproda.md`** | ✅ | ❌ |

Both match `includeGlobs: **/*.aproda.*`, yet neither arrives. `CHANGELOG.aproda.md` is listed in
`layouts.fork.dotGithub` but **not** in `includeFiles`; `onboarding.aproda.md` is in neither. So the
onboarding guide — the document `readme.aproda.md` directs new contributors to — is unavailable in
exactly the repos where new contributors work. **Decision needed:** ship both, or declare them fork-only
and stop referencing them from shipped documents.

> **Methodical takeaway.** Every one of these was invisible from inside the fork, and three of them were
> *already suspected* but unprovable here. A reference project is not a nice-to-have for this kind of
> audit — it is the only place where "ships to projects" can be distinguished from "exists in the fork".
> Re-run §7.6 against a real repo whenever the layer changes materially.

### 7.6 Project verification checklist

```powershell
# 1 layout
Select-String aldc.yaml -Pattern '^toolkitRoot:'            # expect ".github"

# 2 discovery paths exist
Get-ChildItem .github -Directory | Where-Object Name -in 'instructions','agents','prompts','skills'

# 3 Aproda primitives arrived
Get-ChildItem .github -Recurse -Filter '*.aproda.*' | Select-Object Name
Get-ChildItem .github/skills -Directory | Where-Object Name -like 'skill-aproda-*'

# 4 catalogs match reality (F-4)
(Get-ChildItem .github/prompts/*.prompt.md).Count   # vs the count claimed in prompts/index.md

# 5 linked-but-not-shipped
Test-Path .github/docs/copilot-reference.md          # F-11

# 6 BCQuality resolves
Select-String aldc.yaml -Pattern 'home:'

# 7 validator green
node .github/tools/aldc-validate/index.js
```

Then, in Copilot, open the Agent Customizations editor and confirm the Aproda skills, agents and
instructions are listed. Discovery there proves **availability**, not that the rules are followed.

> This checklist lives in a fork-only document on purpose: it is a **maintainer** task, planned here and
> executed in a project. Copy it into the project's plan folder when you run it.

## 8. What does **not** belong in this file

- **Decisions** → `decisions.aproda.md` (a D-entry, with rationale and rejected alternative).
- **The artifact inventory** → `readme.aproda.md` (D-17 declares it the single index).
- **Infra values** (servers, paths, credentials) → `site-profile.aproda.md`.
- **How-to knowledge** → the relevant `skill-aproda-*`.
- **Findings with a remediation plan** → a folder under `_A-ALDC-Plans/`, like E-006.

If something here starts duplicating one of those, delete it here and link instead — the duplication
*is* the failure mode this repo keeps hitting.

---

## 9. Reading order for a new contributor

1. [`../.github/onboarding.aproda.md`](../.github/onboarding.aproda.md) — de, practical setup
2. This file §1–§3 — orientation and where truth lives
3. [`../.github/readme.aproda.md`](../.github/readme.aproda.md) — what the layer adds
4. [`../.github/decisions.aproda.md`](../.github/decisions.aproda.md) — skim D-1…D-7, then on demand
5. §4 here — what is currently broken, before you trip over it
