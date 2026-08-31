# Aproda ALDC Layer — Design Decisions

> Decision record for **how Aproda customizes and maintains its ALDC fork**.
> Companion to [`readme.aproda.md`](readme.aproda.md). This file captures the **why**; the README captures the **how/what**.
> Format: append-only. Newer decisions may supersede older ones — mark, don't delete.

Fork: <https://github.com/Aproda-AG/ALDC-AL-Development-Collection-Aproda>

---

## Context

ALDC is a vendor framework (4 agents + 3 subagents + 11 skills + 6 workflows + 7 instructions) that Aproda **uses**, not owns. We want to:

- **extend** it (add our own skills/agents/workflows), and occasionally
- **change** its behaviour (adjust an existing agent/workflow),

while staying **upgradeable** — able to pull Upstream improvements with minimal friction, ideally automated, human only on genuine conflicts.

The decisions below were reached by working through the trade-offs explicitly (verification of ALDC's internal path assumptions + VS Code discovery mechanics).

---

## Verified facts that drove the decisions

These were **checked against the actual repo**, not assumed:

- **F-1 — ALDC uses absolute `.github/...` paths.** `aldc.yaml` hardcodes `plans.root: ".github/plans"`, `copilotEntrypoint: ".github/copilot-instructions.md"`, evidence globs `.github/plans/**`, etc. The agents reference skills/instructions in prose by absolute path (29 occurrences), e.g. al-developer: "Load on demand from `.github/skills/<name>/SKILL.md`"; al-conductor: "the 7 always-on instructions `.github/instructions/al-*.instructions.md`".
  → **Moving ALDC out of `.github/` (e.g. into `vendor/aldc/`) would break all these references.** The "inverted model" was therefore rejected.
- **F-2 — Discovery runs on VS Code defaults, nothing registered.** No `chat.instructionsFilesLocations` / `promptFilesLocations` / `modeFilesLocations` anywhere; no `aldc.code-workspace` present. VS Code finds `.agent.md` / `.prompt.md` / `.instructions.md` at the **default** locations under `.github/`.
  → A net-new file must either sit at a default location **or** be registered. We chose to sit at the default location (see D-4).
- **F-3 — `applyTo` is location-independent.** An instruction's `applyTo` glob matches the **edited workspace file**, not the instruction's own location. So an instruction fires regardless of which subfolder it lives in.
- **F-4 — Skills are not VS Code "skills".** A `SKILL.md` has no VS Code discovery; it is plain Markdown that an agent **reads by path**. It can live anywhere an agent points to.
- **F-5 — There is no native "override by name".** VS Code/Copilot does not replace an Upstream file with a same-named custom file. The only real mechanisms are **stacking** (instructions add up) and **indirection** (an agent points at a different path). Therefore "silently override an Upstream rule without touching the original" is **not reliably possible**.

---

## Decisions

### D-1 — Keep ALDC in place; Aproda is a fork, not a relocation
ALDC stays under `.github/` exactly where its absolute paths expect it (F-1). Aproda maintains a **fork** with `upstream` as a remote, embedded via **git subtree** under `.github/`. The "inverted model" (`vendor/aldc/` + Aproda at root) is **rejected** because it contradicts F-1 and F-2.

### D-2 — Changes to Upstream behaviour: edit in place, accept the merge conflict
When we need to **change** existing ALDC behaviour, we **edit the original file in place** in the fork. The merge conflict on the next `subtree pull` is **desired** — it is the change-log that tells us "Upstream also touched this, review it" (F-5 means there's no clean override anyway). 
**Explicitly rejected: agent clones.** A cloned `aproda-conductor.agent.md` would silently miss Upstream improvements to the original. In-place edit + conflict surfacing is safer.

### D-3 — No separate override layer folder
Because D-2 puts changes in-place and D-4 puts net-new files in the default folders, there is **no `aproda/` (half-sibling, nested, or sibling) override folder**. It would solve a problem we don't have (we *want* the conflicts, per D-2) and add a second path structure for users to search.

### D-4 — Net-new primitives: same Upstream folder + `.aproda.` infix
New Aproda files live in the **same default folders** as Upstream, named with an **`.aproda.` infix** that preserves the type suffix:
- `prompts/<name>.aproda.prompt.md`, `instructions/<name>.aproda.instructions.md`, `agents/<name>.aproda.agent.md`
- new skills: `skills/skill-aproda-<name>/`; extending an existing skill: a new file `skills/skill-x/aproda-*.md`

**Why infix, not `-custom` suffix:** the suffix would break the type ending (`*-custom.md` is not a `*.prompt.md`), defeating discovery. The infix keeps discovery + `applyTo` working (F-2, F-3) with **no `.vscode/settings.json` registration**, and **co-locates** custom variants next to their Upstream counterparts (one path structure for the user — answers "is there an Aproda variant?" at a glance). Collision-proof: Upstream never creates `.aproda.` files, so they survive every pull untouched.

### D-5 — No `.vscode` discovery registration needed
Direct consequence of D-4 + F-2/F-3/F-4: every Aproda file sits at a default-discovered location with a valid type suffix, so **no settings registration is required**. (If we ever move custom files out of default folders, D-5 must be revisited.)

### D-6 — Upstream sync via aproda-sync tool (not subtree pull)
`git subtree pull` was **rejected**: it causes conflicts in `.github/` shared with AL-Go system files and other project infrastructure that are outside the Aproda layer. The sync mechanism is the **allowlist-based overlay tool** (`tools/aproda-sync/Sync-AprodaLayer.ps1` + manifest `aproda-sync.json`, D-18).

Upgrade pipeline:
1. `git checkout main && git merge upstream/main --ff-only` — keep `main` as clean upstream mirror
2. `git checkout aproda && git merge main` — rebase Aproda layer on top of new upstream
3. Conflicts arise **only** at deliberate in-place edits (D-2 / D-7 register) — small, predictable, review-worthy
4. Resolve conflicts manually (keep Aproda additions, adopt upstream improvements)
5. `git push origin aproda`

`.aproda.` files **never** conflict (D-4). Distribution to projects happens via `Start-AprodaPull.ps1` (D-18) — not git subtree.

### D-7 — One accepted Upstream touch-point: `copilot-instructions.md`
`copilot-instructions.md` is always loaded and fixed at `.github/copilot-instructions.md`. To surface Aproda skills/agents in its routing/skills tables we make **one additive, in-place edit** (a Skills-table row). This is a conscious D-2 merge-point (chosen over the alternative of only `@`-calling Aproda agents and leaving the file untouched). Kept additive and minimal to stay merge-light.

### D-8 — Reusable scripts: immutable engine in the skill + project-local config
The Deploy-Run-Verify Cycle scripts are packaged as a **parameter-driven engine** under `skills/skill-aproda-deploy-run-verify/scripts/` (`AprodaDeployRunVerify.psm1` + thin entry + `deploy-run-verify.config.template.jsonc`). The **engine is immutable** — the agent never edits it per project; it copies the config template and fills the few non-derivable values (apps in dependency order, runner dir, server-side Mgmt DLL). Everything else auto-derives from `launch.json` + each `app.json`. This is the reusable-across-projects goal: new project = a ~3-line config, not a rebuilt script.
**Origin:** generalized from the proven project-local `Test/PowerShell/_Cycle.ps1` + `_RunTests.ps1` (Audit Trail 26/26), which stay in place as the validated reference (single-source-of-truth; the engine is their parameterized form, not a duplicate). Environment-specific scripts are **not** put under `.github/` — only the generic engine is; concrete instances stay project-local.

### D-9 — Agents must be wired in-place to actually apply the skill ("Voll A")
A global row in `copilot-instructions.md` (D-7) is **not enough**: each agent follows its **own** skill table, so the skill must be added to the agents that use it. Chosen approach: **Voll A — both agents edited in-place** (not an additive instruction), because the conductor change is a **flow change** (a phase gate), which F-5 says stacking cannot achieve.
- **al-developer**: `skill-aproda-deploy-run-verify` added to the Domain-skills table + workflow step 4 — **LOW-complexity trigger: run once, after implementation, before PR.**
- **al-conductor**: skill added + new **step 2B-bis runtime Deploy-Run-Verify Cycle gate** + 2C hard-gate clause — **MEDIUM/HIGH trigger: run per phase**, bound to the existing phase boundary (a phase is not complete until green or a service blocker is acknowledged).
- **Trigger policy** is deliberately bound to the existing LOW / MEDIUM-HIGH complexity tiers, not a new heuristic (matches the skill's `When to Load`).
- **Cost accepted:** the Upstream-touch register grows from 1 to 3 files (more D-2 merge-points). Justified because soft stacking could not enforce the conductor phase gate (F-5).

### D-10 — Delivery boundary defines pre- vs post-delivery handling
The **delivery boundary** is the moment a requirement is **accepted** (UAT sign-off / merge+deploy to the target environment). It splits the change lifecycle in two regimes with different document rules (D-11) and change-classification (D-12):
- **Pre-delivery** = still iterating toward first acceptance. Many HITL Validation rounds are normal and expected.
- **Post-delivery** = the requirement was accepted; any further change is a *new* effort.

ALDC itself has **no** post-delivery amendment workflow (verified: reactive tier routes unknown bugs via `@AL Triage`, but there is no patch/amendment spec type). D-10..D-13 fill that gap for Aproda **without** touching Upstream — they are documentation/convention only, enforced by a stacking instruction (D-4), not by editing ALDC agents.

### D-11 — Pre-delivery: spec edited in-place + a separate `hitl-validation-issues.md` work-item
While pre-delivery, the requirement's `{req}.spec.md` is a **draft** and stays the **single source of truth for the target state** — it is **edited in-place** each HITL Validation round (git history is the change log). The spec describes *how the system should be*; it carries **no status and no checklist**.

*What is still to do* lives in a **separate** `{req}-hitl-validation-issues.md` work-item, NOT in the spec:
- A **Status-Board** (index table) at the top: `ID | Title | Loop | Priority | Type | Status`.
- One **detail block** per issue below, each with a `Status:` field (`TODO` / `IN-PROGRESS` / `DONE`).
- **HITL Validation rounds are headers within the one file** (`## Loop 1 — <date>`), **not** separate `loop1.md`, `loop2.md` files — one file = one work-source for the agent.
- **Issue numbers are global and monotonic** (I-1, I-2, … I-n) across all loops, never reset per loop, so every git/commit reference stays unique.
- **Agent contract**: *read the Status-Board → take the next `TODO` (respect implementation order) → load only that issue's detail block (token-efficient) → fix → run the Deploy-Run-Verify Cycle → set `DONE`.* The agent only fixes/extends/adjusts; the spec is the target reference, never a checklist.

**Rejected**: (a) a second sibling spec per loop (two specs = no source of truth); (b) one file per loop (splits the work-source, breaks global numbering, clutters the folder); (c) a spec `git diff` as the to-do signal (mixes typo-fixes with behaviour changes, and "already implemented" is not in the diff). An explicit `Status:` field beats an implicit diff.

> **Splitting is pain-driven, not prophylactic**: keep it one file until the Status-Board itself is drowned out; only then archive old `DONE` loops into `{req}-hitl-validation-issues-archive.md`. The real token lever is the agent contract ("board, then one TODO block"), not file count.

### D-12 — Post-delivery: new plan folder; Bug vs Enhancement classified against the frozen spec
At the delivery boundary (D-10) the spec is **frozen**. Any later change starts a **new plan folder** and is classified by comparing against that frozen spec:
- **Bug** = behaviour deviates from what the (frozen) spec demanded → SemVer **Revision** bump.
- **Enhancement / new scope** = behaviour the spec never promised → SemVer **Minor** bump (or its own requirement).

This classification also applies **within** pre-delivery loops to label each issue (Type column), but only post-delivery does it force a *new plan*. Example from `audit-trail-extension-1` loop 1: I-4/I-7 are **Bugs** (the spec demanded the gate / the translations); I-1/I-3 are **Enhancements / under-spec** (D-04 explicitly stated "Allowed + untracked", so the new "start Blocked" behaviour is a scope change, not a bug).

### D-13 — Naming & placement: transient plans vs durable module docs
Two distinct lifecycles get two distinct homes:
- **Transient, per-requirement** (spec, hitl-validation-issues, architecture, test-plan, phase/plan-complete) → `.github/plans/{req}/`. Post-delivery follow-ups: `{req}-2/` (new scope) or `{req}-fix-{n}/` (post-delivery bug).
- **Durable, per-module** (lives across all requirements/loops) → `.github/documentation/<Module>/`:
  - `<Module>.reference.md` — technical module reference (**English**). Lean: links to the `.al` files + the module SKILL as source-of-truth, never mirrors IDs/paths.
  - `<Module>.Handbuch.de-CH.md` — user handbook (**de-CH**, Aproda standard for end-user docs).

`.github/documentation/` is **distinct from** `.github/docs/` (the latter is ALDC framework templates + schema — not module content). Module docs reflect the **target state**; while related HITL Validation issues are still `TODO`, the reference may describe the soll-state ahead of the code — acceptable for a reference, by design.

> **Agent awareness of D-11**: agents do not know this convention natively. It is surfaced additively via a stacking instruction (`instructions/*.aproda.instructions.md`, D-4) — **not** by in-place agent edits (D-9), because the HITL Validation instruction (`hitl-validation.aproda.instructions.md`) is purely additive ("additionally, when a `hitl-validation-issues.md` exists, consume it this way"), which Stacking can express (F-5). The `hitl-validation-issues.md` file is also self-describing (carries the agent contract in its header) as a second, redundant safeguard.

### D-14 — Module documentation maintenance: a workflow, not a doc-agent
The durable per-module docs (D-13: `<Module>.reference.md` EN + `<Module>.Handbuch.de-CH.md`) are kept current by a **net-new `.aproda.` workflow** `al-doc-update` (`prompts/al-doc-update.aproda.prompt.md`, D-4 — no Upstream conflict), **not** by a dedicated documentation agent.

**Why a workflow, not an agent**: generating docs is a **deterministic procedure** (read code/spec → render → write the two files), not a role with judgment. ALDC models such procedures as *workflows* (`al-context.create`, `al-memory.create`), not agents. A doc-agent would be a persona with nothing to decide — overkill. Rejected.

**Trigger — the delivery boundary (D-10)**, alongside `al-pr-prepare`: docs should mirror the **final** target state, so regenerating them per individual HITL Validation fix is waste; the spec only stabilizes at acceptance. Wiring (extends the **existing** D-9 touch-points, so the register does not grow new *files*):
- **al-developer**: the workflow-step-4 "Before handing off for PR" sentence gains a delivery-boundary clause — *if a documented module changed, run `al-doc-update`.* (LOW trigger.)
- **al-conductor**: the post-completion recommendation table gains an `al-doc-update` row next to `al-pr-prepare`. (MEDIUM/HIGH trigger.)

The workflow is **documentation-only**: it must not edit `.al`, the spec, or the `hitl-validation-issues.md`, and must not duplicate IDs/paths/signatures (D-13 — link, don’t mirror). It does not commit (that is `al-pr-prepare`).

### D-15 — Deploy-Run-Verify Cycle standardized on the own engine: central glue + DVD-materialized runner DLLs + SRP-safe loading
The Deploy-Run-Verify Cycle is standardized on the **own engine** (D-8); `jamespearson/al-test-runner` is **fallback only** (its Newtonsoft.Json fix lives outside the workspace, unversioned — the instability that motivated this). Validated end-to-end: **27/27 green** via the engine against BC 28 OnPrem. Three refinements to D-8, all **skill-internal** (no new Upstream touch-points, register unchanged):

- **Central glue.** The 3 version-agnostic glue scripts (`ClientContext.ps1`, `PsTestFunctions.ps1` — MS canonical, MIT; `AprodaRunner.ps1` — Aproda wrapper) ship **once** in `scripts/runner-glue/`, not per project, not per runner version. The engine resolves `glueDir` from its own module location. `New-DeployRunVerifyRunner` is **DLL-only**.
- **Runner DLLs materialized from the K: BC DVD.** `Initialize-DeployRunVerifyRunner` + `Resolve-DeployRunVerifyClientSource` derive the 4 version-pinned client DLLs from the deterministic DVD layout `<bcDvdRoot>\<major>\<bcCountry>.<major>.<minor>\Applications\TestFramework\TestRunner\Internal` (config `bcDvdRoot` + `bcCountry`; highest minor wins). Alternatives: explicit `runnerClientSource` (wins) or `runnerClientFromServer` (remote-PS pull, fallback). The **whole `_runner/` folder is git-ignored** — nothing under it is committed.
- **SRP-safe script loading.** This estate's Group Policy / Software Restriction Policy **blocks path-based PowerShell execution** (`. <path>.ps1`, `Import-Module`) workspace-wide → `PSSecurityException`. Everything is loaded **content-based** via `[ScriptBlock]::Create((Get-Content -Raw))`: the entry point loads the engine; the run-bootstrap loads all 3 glue files, `Add-Type`s the client DLLs **before** the `ClientContext` scriptblock (its class references `Microsoft.Dynamics.Framework.UI.Client.*` at parse time), and regex-neutralizes PsTestFunctions' internal `. $clientContextScriptPath`. `Get-Content` (reading) is not SRP-blocked; only path-based *execution* is.

### D-16 — Self-knowledge: a site profile, a meta-skill, and a steward guardrail
The layer must carry **its own infrastructure facts** and **its own how-to-extend knowledge**, so a fresh chat / new repo isn't blind to the estate (K:, NST servers, SRP, remote-PS) or to the `.aproda.` conventions. Three net-new artifacts (all `.aproda.` / `skill-aproda-*` → **no Upstream touch-points**, register unchanged), plus one personal fallback:

- **`site-profile.aproda.md`** (net-new doc) — concrete, org-wide **infrastructure facts**: topology (VS Code local, BC on `apd-svw-nst0x`, `D:\` server-only, `K:\` local), remote-PS, the **SRP path-execution block + content-based workaround**, the **K: BC DVD** layout, the web-client port-80 rule, paste mangling. It is **referenced on demand** by the Aproda skills, **never auto-loaded** (the user's constraint: most users only apply, few change). Site facts only — project-specific values stay in `deploy-run-verify.config.jsonc` / `launch.json` (link, don't duplicate, D-13).
- **`skill-aproda-aldc`** (net-new meta-skill) — **Explain** (what is the layer / why decision D-N) for the many onboarding questions, and **Extend** (the stacking-vs-in-place decision tree + record + flow-back procedure) for the few who change it. It **links** `readme.aproda.md` / `decisions.aproda.md` / `site-profile.aproda.md`; it never copies them. **Not a new agent** — explaining is Q&A from a knowledge body, extending is a procedure with judgment, which ALDC models as a *skill/workflow*, not a persona (same reasoning that rejected a doc-agent in D-14).
- **`aproda-aldc-steward.aproda.instructions.md`** (net-new stacking instruction, `applyTo: **/*.aproda.*, **/skill-aproda-*/**`) — the **HITL guardrail**. Because an Upstream-behaviour change could be made by a user who doesn't know it's deliberate, the trigger must be **invocation-independent**: only an auto-applied `applyTo` glob fires when *any* layer file is edited, even in a normal chat that never `@`-calls a steward. It **stops and requires confirmation** before changing/relaxing anything, surfaces the relevant D-entry, and reminds that the change must **flow back to the fork**. Stacking only strengthens (F-5) — it adds a gate, revokes nothing.
- **User-memory fallback** (`/memories/aproda-infra.md`, personal, cross-workspace) — a redundant condensed copy of the infra facts that travels with the developer’s account into repos that don’t carry the full `.github/` subtree. Redundancy is deliberate (same principle as the self-describing `hitl-validation-issues.md`, D-11).

**Distribution (the user's decision):** everything ships to **every project** via the subtree; **reading/applying** happens everywhere, **changing** happens where the need arises (with live validation), and the change is only adopted once it is **pushed back to the aproda-aldc fork** — the inverse direction of the D-6 upgrade pull. Fork = source of truth; project copies = working copies.

### D-17 — Sub-versioning the fork: `<ALDC core.version>_aproda.<n>` + a recorded base pin
The Aproda layer had **no version of its own** and the ALDC base it sits on was an unfilled placeholder — so "how far is the fork from Upstream?" was unanswerable. Adopted a composite version: `<ALDC core.version>_aproda.<revision>` (current: `1.2.0_aproda.4`), URL-safe and unambiguous; where the left side is the adopted ALDC `core.version` and the right side is the Aproda revision counter, bumped each time the layer is pushed to the fork. The **ALDC base commit** is pinned in `aldc.yaml → aproda.basePin` and echoed in the Version/pin changelog (current: `a900263f51e416762cc7f85575deb9b30cd5b1e3`; at this SHA upstream == fork, i.e. all our `.aproda.` work is the working-tree delta on top of a synced base). Single source of truth for the numbers = `aldc.yaml → aproda` (mirrors the `external.bcquality` pin pattern). The drift where `copilot-instructions.md` (and the `aldc-validate` banner) still said "ALDC Core v1.1" against `core.version: 1.2.0` was corrected at the same time — a candidate for an upstream PR, registered below.

**Index, not a new file:** the question "does the fork need an index?" resolves to **no new artifact** — the existing `readme.aproda.md` inventory table ("What lives here") **is** the Aproda index. It is refreshed to list every net-new primitive with live status. Upstream per-type `index.md` files are deliberately **not** touched (would multiply merge-points, against D-7).

### D-18 — Layer sync by ALLOWLIST manifest, not subtree (coexists with AL-Go + project files)
A project's `.github/` has **three owners**: AL-Go (`workflows/*`, `AL-Go-Settings.json`, `.AL-Go/`), the Aproda toolkit (this layer), and the project itself (`plans/`, `documentation/`, app). `git subtree --prefix=.github` treats the whole tree as one unit — it would overwrite AL-Go/project files on pull and upload them on push. **Rejected.** Instead the layer is synced by a small script (`tools/aproda-sync/Sync-AprodaLayer.ps1`) driven by an **allowlist manifest** (`tools/aproda-sync/aproda-sync.json`).

**Why allowlist (include), not blocklist (exclude) — the user's argument:** the decisive question is the *default* for an **unknown future file**. A blocklist defaults to *touch it* (must remember to exclude every new AL-Go/project file — default-unsafe, constant upkeep, one miss = an accident). An allowlist defaults to *leave it alone* (a miss merely means a new Aproda file isn't synced yet — visible, harmless, destroys nothing). The Aproda layer is **self-identifying** (D-4): the convention globs `**/*.aproda.*` + `skills/skill-aproda-*/**` grow automatically, so the allowlist needs almost no upkeep. AL-Go and project files need **no manifest entry at all** — not being on the list = invisible to the sync in both directions.

**Allowlist sources** (resolved by the script): (1) convention globs (self-growing); (2) named net-new files without the infix (`readme.aproda.md`, `decisions.aproda.md`, `site-profile.aproda.md`, the syncer itself); (3) **`inPlaceEdits`** — the Upstream files we edited, kept **redundant** in the JSON (user's choice: explicit beats parsing the markdown register; it mirrors the D-7 table, which is updated for governance anyway); (4) ALDC framework files scraped from `aldc.yaml required`/`optional` (toggle `includeAldcFramework`). A `neverTouch` tripwire (`plans/**`, `documentation/**`, `workflows/**`, `AL-Go-Settings.json`, `.AL-Go/**`) is a redundant belt-and-suspenders, with `workflows/bcquality-evidence.yaml` as the one Aproda-owned exception.

**Two safety properties:** (a) **overlay-only** — sync copies, never deletes a destination file it doesn't own, so AL-Go/project files survive even a manifest gap; (b) **push filters through the same allowlist** — `plans/`/`documentation/` physically cannot reach the fork because they aren't listed. The script is SRP-safe (cmdlet-only, no path-based dot-sourcing) and supports `-WhatIf` dry-run. During `-WhatIf`, byte-identical regular files are skipped by SHA-256 and dual-variants are compared with their computed destination content; the stable summary reports one combined count of actual changes. Flow mirrors D-16: pull (fork→project) overlays the layer; push (project→fork) stages only layer files for a PR — the change is real once merged into the fork.

**Asymmetric layout (fork ≠ project).** The two ends do **not** store the layer at the same path: the **fork** keeps the toolkit primitives at **repo root** (`agents/`, `skills/`, `instructions/`, `prompts/`, `docs/`, `tools/`) with only a handful of files under its own `.github/` (`copilot-instructions.md`, `plans/`, and our net-new `*.aproda.md`); a **consuming project** keeps the *entire* toolkit under `.github/`. The manifest therefore carries a `layouts` block (`project.base = ".github"`; `fork.base = "."` plus a `dotGithub` exception list) and the script maps every file through a **logical path** (project-layout, relative to `.github/`): on enumerate it reverse-maps physical→logical for the source side, applies the allowlist on the logical path, then forward-maps logical→physical for the destination side. So `agents/x.md` lives at `.github/agents/x.md` in a project but `agents/x.md` at the fork root, while `copilot-instructions.md` / `*.aproda.md` stay under `.github/` on **both** ends via `dotGithub`.

**Dual-variant files (`aldc.yaml`).** One file resists both the logical-path machinery *and* a verbatim overlay: `aldc.yaml` lives at the **repo root on both sides** (so there is no `.github/` remap to do) yet its **content must diverge on one line** — `toolkitRoot` is `".github"` in a consuming project but `"."` in the fork. A plain copy in either direction would break the destination's toolkit discovery. It is therefore handled by a dedicated **copy + per-side line-rewrite** step (manifest `dualVariant`): the file is copied verbatim, then each `rewrites[]` entry replaces the first line matching its `match` regex with the **destination side's** literal (`project` / `fork`). The rewrite preserves UTF-8-no-BOM encoding and the destination's native EOL (no CRLF churn). Generic by design — a further diverging line is just one more `rewrites` entry — but `toolkitRoot` is currently the only one. This replaces the earlier "`aldc.yaml` is maintained manually" stance: it is now fully auto-synced.

**Provenance of the mapping schema.** This Root↔`.github/` remap, the overlay semantics, and the special-cased files (`copilot-instructions.md`, `aldc.yaml`, the bundled `tools/bcquality` + `aldc.code-workspace` seed) were **distilled from the published ALDC VS Code extension 4.2.0** (`extension.js → installToolkit()/copyDirectory()`), which performs the same per-folder overlay from its bundled `templates/` into a project's `.github/`. We **re-implemented the logic in PowerShell as manifest data + a cmdlet-only script — no JavaScript was adopted or executed**, and unlike the extension our source is not a hardcoded bundle but a live fork clone, so the syncer is bidirectional (pull *and* push).

### D-19 — The consuming project keeps `.github/` at the **real git root** (multi-app repos), and the syncer anchors there
A consuming repo may hold **several AL apps as sibling folders** under one git root (e.g. `Base/`, `Test/`). GitHub-the-service reads `.github/` (Actions workflows, `CODEOWNERS`, issue templates) **only from the repository root**, and VS Code/Copilot discover `copilot-instructions.md` + `instructions/`/`prompts/`/`agents/` under a **workspace folder's** `.github/`. Therefore the toolkit's `.github/` (and the root-level `aldc.yaml`) **must live at the git root**, not inside an app folder. A layout where `.github/` sat under `Base/` was corrected by moving the whole `.github/` tree + `aldc.yaml` up to the git root via history-preserving `git mv`/rename.

**F-1 is NOT violated.** F-1 forbids moving ALDC *out of* `.github/` (into `vendor/aldc/`); here the toolkit **stays inside `.github/`** and `toolkitRoot` **stays `".github"`** — only the *anchor* of that `.github/` moves from an app subfolder to the repo root. All 29 absolute `.github/...` references remain valid because they resolve relative to the (now correctly placed) toolkit root.

**Syncer anchoring.** `Sync-AprodaLayer.ps1` and the project-init step resolve `ProjectRoot` by **walking up from the script dir until a `.git` entry is found**, falling back to the structural "scriptDir up 3" only outside a git work tree — replacing the fragile "count N parents" assumption, which silently pointed at an app folder in a multi-app repo. The `.git`-walk is used **instead of `git rev-parse --show-toplevel`** on purpose: parsing git's stdout mangles non-ASCII path segments (e.g. umlauts) under a non-UTF-8 console, whereas the pure path walk is encoding-safe.

**Workspace file.** The `*.code-workspace` must list the toolkit's **`.github`** as a folder (so it is visible/editable) alongside each app folder (`Base/`, `Test/` — kept as separate roots so the AL language server treats each `app.json` as its own project) and the external `../bcquality` knowledge root. The init step ensures the `.github` and BCQuality roots idempotently. This layout is the prerequisite for the planned **AL-Go** adoption (AL-Go also expects `.github/` + per-project folders at the repo root).

**Init split out of the run script.** The one-time project bootstrap (seed `plans/memory.md`; maintain the `.gitignore` Aproda block inside a `# Aproda ALDC Tool - BEGIN/END` marker; ensure the workspace roots) lives in its own **`tools/aproda-sync/Initialize-AprodaProject.ps1`** so the machine-local `Start-Pull.ps1` stays thin (pull, then content-load the init script — SRP-safe). The init script is part of the layer (`includeFiles`), so it flows to the fork and every project gets the same bootstrap.

### D-20 — Onboarding a fresh repo: a zero-seed bootstrap that borrows the engine from the fork
Bringing the layer into a repo that does **not** yet have it hits a chicken-and-egg floor: a pull needs the engine (`Sync-AprodaLayer.ps1` + `aproda-sync.json`), which cannot pull *itself* before it exists. The instinct “seed a small stub, then pull” was **rejected** — any seed-then-pull duplicates exactly what the pull already does (the four `tools/aproda-sync/*` files are in `includeFiles`, so the pull writes them anyway), and you **cannot** seed anything smaller than the engine+manifest, so a “smaller seed” is impossible by construction.

**The escape is zero-seed: don't place the engine first — borrow the fork's copy.** The fork already contains the engine (it is the source). `tools/aproda-sync/Bootstrap-AprodaProject.ps1` (net-new, ships in `includeFiles`):
1. **PULL** — content-loads the engine **from the fork** and runs it `-Direction pull -ForkPath <fork> -ProjectRoot <target>`. The pull materializes the **whole** layer into the target's `.github/`, *including* `tools/aproda-sync/*`. So the seed is **zero files**; the only artifact is the bootstrap script itself, which already sits on disk for anyone holding a fork clone.
2. **INIT** — the target now carries `Initialize-AprodaProject.ps1`; content-load it **from the target** (not the fork) so its `.git`-walk anchors on the **target's** root. (Init has no `-ProjectRoot`; running the fork's copy would init the fork — wrong. The post-pull target copy is the correct anchor.)

**Signature — one required input.** Only `-ProjectRoot` (the target) is mandatory; `-ForkPath` auto-derives by walking up from the script's own location to `.git` (the script ships inside the fork), overridable. Slimmer than a two-path call.

**No `git init` — warn and abort.** The bootstrap requires the target to **already be a git work tree** (a `.git` at its root) and aborts otherwise, rather than silently `git init`-ing. Reason: the init step's `.git`-walk must land **exactly** on the target root; auto-initing could mask a target nested under an ancestor repo whose `.git` the walk would otherwise (wrongly) find. Making the user run `git init` first keeps the anchor unambiguous and the destructive surface zero.

**Framework settle pull (fresh-repo only).** The engine resolves the ALDC framework file set from the **destination's** `aldc.yaml`, but `aldc.yaml` is written (dual-variant) at the **end** of the same pull — so a fresh repo's **first** pull cannot include the framework (no `aldc.yaml` existed at resolve time); only the self-identifying `.aproda.` layer + tools arrive. The bootstrap therefore issues **one extra "settle" pull** once `aldc.yaml` is present, which brings the framework (skills/prompts/agents/`docs/templates` incl. the `memory-template` the init seeds `plans/memory.md` from). Overlay is idempotent → safe and strictly one-time (onboarding only); the recurring `Start-Pull` never needs it because an established repo already has `aldc.yaml`.

**`-WhatIf`** dry-runs the pull and **skips** init (nothing is materialized to initialize). Distinct from `Start-Pull` (the recurring, machine-local starter, which arrives via the pull as `Start-Pull.ps1.template`): bootstrap is the **one-time** onboarding; Start-Pull is the **repeat** pull. Fork = source of truth; the bootstrap is a fork-side tool that ships everywhere (D-16) but is run where a fresh repo needs onboarding.

**Seamless one-click onboarding + generated Start-Pull.** Two additions make onboarding a single gesture:
- The bootstrap, after pull+init, **materializes the target's `Start-Pull.ps1`** by injecting **only the fork path** into the pulled `Start-Pull.ps1.template` (the `APRODA_SYNC_SCRIPTDIR` line is left empty so the generated starter **self-locates** it at run time — see the self-location note below). The fork path is correct-by-construction (no typo in the longest path); the scriptdir is self-located → a **zero-config** generated starter. Idempotent (an existing, possibly customized `Start-Pull.ps1` is left untouched unless `-Force`). This answers "create the matching Start-Pull and leave the repo ready": the bootstrap's own pull+init **is** the initial run, and the generated starter serves every future pull — re-running it immediately would be a redundant double-pull, so it is not executed again.
- **`Start-Pull` / `Start-Push` self-locate `APRODA_SYNC_SCRIPTDIR`.** Both templates leave `APRODA_SYNC_SCRIPTDIR` empty by default and resolve it from the script's own location (`$PSScriptRoot` when run as a file, else `$psEditor`'s current file under "Run Selection") — the file sits directly in `<project>/.github/tools/aproda-sync`, so the self-path **is** the scriptdir (no level-walk). This drops a manual copy-and-fill from **two paths to one**: only `APRODA_FORK_PATH` (a separate repo, not self-locatable) must be filled. The longest, most typo-prone path (`…/.github/tools/aproda-sync`) is gone. A non-empty `APRODA_SYNC_SCRIPTDIR` is always respected as an **override** for special cases. They stay `.template` + git-ignored (the one remaining fork line is still machine-local) — only `Start-InitNewProject` (which needs *zero* machine-local lines) graduates to a committed `.ps1`.
- **`Start-InitNewProject.ps1`** is the **fork-only** one-click starter, and unlike `Start-Pull`/`Start-Push` it is a **real committed `.ps1`, not a template, and is NOT synced** (deliberately absent from `aproda-sync.json` → invisible to the allowlist in both directions). Rationale: it is **fork infrastructure**, not layer content — a consuming project never runs its own copy (by the time a project exists it is already onboarded), and the bootstrap it drives expects a *fork-layout* source. It therefore lives next to the engine at `<fork>/tools/aproda-sync/` and is maintained there directly (one-time manual placement; thin, rarely-changing launcher). Because it **self-locates the fork from its own script location** (`$PSScriptRoot`, or `$psEditor`'s current file under "Run Selection" → fork root is two levels up), there is **no machine-local path to fill in** — which is exactly why it can be a plain committed `.ps1` instead of a copy-and-fill `.template`. `$targetRepo` defaults to empty → a **Windows folder picker** (`Shell.Application.BrowseForFolder`, STA-independent so it works under the PS extension's MTA "Run Selection", unlike WinForms `FolderBrowserDialog`) prompts for the target. It then content-loads `Bootstrap-AprodaProject.ps1` from the fork and runs it. Net flow: **pick a folder → run → repo is ready** (pulled, initialized, Start-Pull in place).

### D-21 — Fleet management tools: fork-only admin scripts that are NOT synced to projects
The fork needed a way to manage the *fleet* of project repos that carry the Aproda layer: inspect their version, push updates out, and pull in-place edits back. Three scripts under `tools/aproda-sync/fleet/` implement this:

- **`Get-AprodaFleetStatus.ps1`** — scans sibling project repos; compares `aproda.layerVersion` against the fork; reports `[OK]` / `[UPDATE]` / `[DRIFT]` / `[NO-VER]` / `[NONE]`. With `-FullDiff` runs a full SHA-256 layer compare (reusing the same manifest/glob logic as the sync engine). Writes a JSON report to `fleet/_status-output/` (git-ignored). Supersedes the ad-hoc `_compare-output/run-layer-compare.ps1`.
- **`Start-FleetUpdate.ps1`** — classifies repos as `[UPDATE]` / `[OK]` / `[SKIP]`; loads `Sync-AprodaLayer.ps1` content-based (SRP-safe, D-15); calls `-Direction pull` per outdated repo. Supports `-WhatIf`.
- **`Start-FleetGather.ps1`** — brings in-place edits from selected project repos back into the fork. Interactive repo selection (Out-GridView → console index fallback). **Conflict guard**: checks `git status --porcelain` for uncommitted tracked changes in the fork before any write; if found, prints the affected files and aborts — gather must not silently overwrite unresolved fork edits. Supports `-WhatIf`.

**All three are fork-only** — they are deliberately absent from `aproda-sync.json` (not in `includeFiles`, not matching any sync glob) so they are invisible to the allowlist syncer in both directions. Rationale: they operate on the fork **as a whole** (comparing/updating/gathering across multiple project repos), require access to the sync engine and a local fork clone, and are never useful inside a project repo. Keeping them fork-side avoids confusing consumers with fork-admin tools they cannot run. Self-location follows the same 3-tier pattern used throughout the toolkit (`$PSScriptRoot` → `$env:APRODA_SYNC_SCRIPTDIR` → `$psEditor` current-file path). The `fleet/_status-output/` output directory is git-ignored.

The VS Code extension under `tools/aproda-vscode-extension/` follows the same fork-only classification. It is explicitly denied by `aproda-sync.json` `neverTouch`, so its source, dependencies and internal VSIX build output can never be overlaid into a consuming project. The extension orchestrates the existing sync engine; it does not replace it.

### D-22 — Per-agent model pinning: cost-tiered defaults + a HITL model-escalation gate
All 10 agents were pinned to `Claude Sonnet 4.6 (copilot)`, which **retires 2026-09-01**. Migration was therefore forced, not optional — the only decision left was *which* model per agent.

**Selection metric: cost per completed task, not price per token.** Price per token is misleading because verbosity differs by a factor of ~3 between models at the same price tier. Measured against the Artificial Analysis Intelligence Index v4.1.1 (2026-08):

| Model | AA Index | Price in/out | Cost per AA task | Output tokens (full Index) | Speed |
|-------|---------:|--------------|-----------------:|---------------------------:|------:|
| Claude Opus 5 | 63 | $5 / $25 | $2.34 | 100M | 59 t/s |
| GPT-5.6 Terra | 57 | $2 / $12 | **$0.51** | 96M | 116 t/s |
| Claude Sonnet 5 | 55 | $2 / $10 | $1.72 | 300M | 81 t/s |
| GPT-5.6 Luna | 52 | $0.20 / $1.20 | $0.05 | 130M | 154 t/s |

Three findings drove the allocation: (a) **Terra dominates Sonnet 5** on both axes — higher index *and* 3.4× lower cost per task, because Sonnet 5's cheaper output price is over-compensated by its token volume; (b) **Opus 5 dominates GPT-5.6 Sol** (63 vs 61 index at a lower output price), so Sol is never the right pick; (c) **Claude Fable 5 is excluded on compliance** — Anthropic retains prompts/outputs for safety classifiers, outside GitHub's standard data-retention agreement, which is disqualifying for customer code.

**Allocation rule: is the prose the product?** Where the deliverable is human-read documents, verbose reasoning is *wertschöpfend* and Sonnet 5's lower output price applies — Anthropic also leads the agentic knowledge-work benchmark (AA-Briefcase). Where the deliverable is code, tool loops, or structured JSON, verbosity is pure waste and Terra wins on index, cost and speed.

| Agent | Model | Why |
|-------|-------|-----|
| `al-architect` | Claude Sonnet 5 | Deliverable is `architecture.md` + diagrams; low frequency; prose quality is the product |
| `al-presales` | Claude Sonnet 5 | Estimation/SWOT/proposal documents, multilingual, no code risk |
| `al-agent-builder` | Claude Sonnet 5 | Natural-language agent instructions are half the deliverable |
| `al-conductor` | GPT-5.6 Terra | Orchestration = many turns, large input context, mechanical output |
| `al-developer` | GPT-5.6 Terra | Daily edit→diagnostics→fix loop; speed and cost per task dominate |
| `al-implement-subagent` | GPT-5.6 Terra | Highest token volume in the framework |
| `al-planning-subagent` | GPT-5.6 Terra | Read-only research; needs search discipline + long context, not max reasoning |
| `al-review-subagent` | GPT-5.6 Terra | Output is a strict JSON verdict; runs **every phase** → the cost driver among the gates |
| `dredd` | GPT-5.6 Terra | Same findings/JSON profile as the review subagent; consistency between in-loop and independent auditor is deliberate |
| `al-triage` | GPT-5.6 Terra | Core work is reproduce → debug → trace, i.e. a tool loop |

**Opus 5 is deliberately NOT a pinned default anywhere.** At $2.34/task (~4.6× Terra) it is not defensible for daily work. Instead it is reachable through a **HITL model-escalation gate** in the two agents where invocation is rare *and* the decision is hard to reverse:

- **`al-architect`** — raised only at **HIGH** complexity, evaluated *before* any design work. Placing it at the existing "architecture complete → approve" gate would be useless: by then the reasoning has already happened and an upgrade would only polish wording. The gate rides on the complexity assessment that ALDC performs anyway, so it adds **no new interruption**.
- **`al-triage`** — raised only for **high-stakes incidents** (production outage, data-integrity risk, customer-facing regression, posting/financial impact). Rationale: a wrong root cause here is caught by **no downstream reviewer**; the fix ships against it.

**Two hard constraints on the gate's wording**, both encoded as explicit prompt rules:

1. **The agent must never name the model it is running on.** There is no API for a model to read its own identity or the picker; the name is injected by the platform. A prompt that says "you are running X" invites a **fabricated model name that the user then acts on** as a cost decision. The gate therefore states only the *recommendation*.
2. **The skip condition fails safe.** Skip only on *positive* confirmation of Opus 5; when unsure, raise the gate. Asking unnecessarily costs one reply; skipping wrongly costs quality silently. A closing "never raise for LOW/MEDIUM (resp. routine bugs)" rule prevents the gate from degenerating into noise that gets reflexively dismissed.

**Rejected alternatives:** (a) *Opus 5 as pinned default for the reviewer/auditor/triage trio* — rejected on cost, since `al-review-subagent` runs per phase and is therefore effectively daily; (b) *self-switching the model from the prompt* — not possible, `model:` is a default applied at agent selection and only the user's picker overrides it; (c) *raising the reasoning level instead of the model class* — kept as the cheaper everyday lever, but 55→57 is not equivalent to 55→63, so it does not replace the gate at HIGH; (d) *GPT-5.6 Luna as any agent's default* — reserved as an explicit cost mode for bounded, mechanical work (workflow prompts, LOW-complexity research), not a pinned agent model.

**Workflow prompts follow the same rule.** They carried `Claude Sonnet 4.5`, which retires on the same date. The five deterministic procedures (`al-build`, `al-initialize`, `al-pr-prepare`, `al-memory.create`, `al-context.create`) produce tool loops and structured output → **GPT-5.6 Terra**. The Aproda-owned `al-doc-update.aproda` produces human-read module documentation → **Claude Sonnet 5**. Two prompt families are deliberately left alone: `al-spec.create` keeps **GPT-5.3-Codex**, which is GA and is itself the official successor for the retired Codex models (a coding-specialised model is the right fit for an implementable blueprint); the five `al-agent.*` prompts carry **no `model:` line at all** and inherit the picker — adding a pin would remove that flexibility for no gain.

**Not a model reference — do not "fix":** `skills/skill-copilot/SKILL.md` contains `exit('gpt-4o')` in an AL sample. That is an **Azure OpenAI deployment name inside Business Central Copilot capability code**, not a GitHub Copilot chat model. It is unaffected by any Copilot retirement.

**Mirror tree caveat.** Every agent exists twice — `agents/<name>.agent.md` (the discovered, authoritative copy) and `packages/foundation/agents/<name>.agent.md` (a distribution mirror, **not** covered by `aproda-sync.json`). Both were updated. Any future model or gate change must touch both or the mirror silently drifts.

### D-23 — Layer versions use existing `v<layerVersion>` tags
The VS Code extension needs a remote, machine-readable release source for its startup and manual update checks. The installed version is `aldc.yaml` → `aproda.layerVersion`; the available version is the highest remote tag matching `v<core>_aproda.<revision>`. This preserves the existing tag convention (`v1.2.0_aproda.2`, `.6`, `.7`) rather than creating a competing `aproda-layer/*` namespace.

A GitHub Actions workflow validates a new version bump on `aproda` against the checked-out `aldc.yaml`; only after Environment approval does it create the matching tag. Thus `v1.2.0_aproda.10` must contain exactly `layerVersion: "1.2.0_aproda.10"`. The extension treats an installed version newer than the latest tag as `ahead`, not current, preventing a false update result while a release tag is pending.

### D-24 — Agent configuration access uses an extension-owned read-only tool
Consumer workspaces deliberately expose curated subfolders such as `.github`, `Base`, and `Test`, not the repository root. Parent customization discovery makes ALDC instructions visible, but does not make root-level `aldc.yaml` readable to agents. Moving the file into `.github` would break the root-anchored sync, bootstrap, and fleet contract.

The Aproda VS Code extension therefore contributes `aprodaAldc_readConfiguration` (`#aldcConfiguration`). It resolves Git roots from existing workspace folders, accepts exactly one root containing `aldc.yaml`, and returns a structured subset of the authoritative configuration. It is read-only, never prompts agents to select a repository, and reports missing, ambiguous, or invalid configuration explicitly. ALDC personas use the tool before configuration-dependent decisions and use direct root-level access only when the extension tool is unavailable.

### D-25 — CI creates release tags after validation and approval
Layer and VS Code extension releases are separate version streams. A version bump merged to `aproda` starts the matching CI validation automatically; it does not itself create a release. The final CI job waits for approval in a dedicated GitHub Environment, then creates the immutable tag and GitHub Release. This preserves a single human release authorization without requiring a second manually started workflow.

Layer tags remain `v<core>_aproda.<revision>` and are the technical source for layer update checks. Extension tags remain `vscode-ext/v<semver>`; their matching GitHub Release contains `aproda-aldc-<semver>.vsix`, which is the self-update download source. A release tag therefore always denotes a validated, approved publication. Manual creation of either tag is prohibited.

`skill-aproda-aldc-release` documents this process for fork maintainers. It is deliberately excluded from the overlay sync manifest: consumer projects update from releases but must never be instructed to create them.

---

### D-26 — HITL gates must be self-verified, not just narrated

A live end-to-end test of the `skill-aproda-ado` CLI integration (2026-08-31) showed that
an agent following `al-pr-prepare.prompt.md`'s Completion Gate step-by-step still skipped
two of its own items (`/reports/pr-draft.md` deletion, the `memory.md` → Completed move)
without noticing — the gate was described in prose but never actively checked before the
agent declared the work done. A documented gate that isn't independently verified is not
a guarantee it ran.

Fix pattern (applied first to `al-pr-prepare.prompt.md`'s Completion Gate, mirroring
`al-conductor.agent.md`'s existing "🚨 HARD GATE" phrasing): every HITL/completion gate
must (a) require an explicit verification action (e.g. `git status --short`, a
file-existence check) rather than trusting that an earlier step "should have" run it, and
(b) require the gate's final report to render each item as ✅/❌ with the verification
evidence, not a restatement of the checklist text. Applies to any future gate added to
this layer, not just ADO.

---

### D-27 — A curated `CHANGELOG.aproda.md` alongside the technical Version/pin changelog

The Aproda layer's only version history was the *Version / pin changelog* table above —
terse, commit-diff-style notes meant for the upgrade reviewer. The VS Code extension, by
contrast, already carries a prose `CHANGELOG.md` for its own releases. Asked directly,
there was no equivalent human-readable summary for the layer itself, an inconsistency
between the two release streams governed by the same `skill-aproda-aldc-release`.

Added `.github/CHANGELOG.aproda.md`: a net-new, conflict-free file (`.aproda.` infix) that
restates each `layerVersion` bump as short prose bullets, newest first, mirroring the
extension's changelog style. It does not replace the Version/pin changelog (which stays
the technical source of truth with dates and upstream refs) — it is the curated summary a
human reads. `skill-aproda-aldc-release`'s "Before merge" step for the layer stream now
lists it alongside `aldc.yaml`, `readme.aproda.md`, and `decisions.aproda.md`.

The two changelogs' content now overlaps: the Version/pin changelog's `Notes` column and
`CHANGELOG.aproda.md`'s prose bullets said the same thing twice, risking drift between
them. **Going forward** (not retroactively — existing rows are left as written), the
Version/pin changelog's `Notes` column is kept to short technical keywords; the full
prose account of a release lives only in `CHANGELOG.aproda.md`. This preserves the
Version/pin changelog's unique, non-duplicated value (date + upstream SHA pin per
revision) without a second full prose copy.

---

### D-28 — memory.md lifecycle transitions have exclusive owners

An implementation subagent could edit `.github/plans/memory.md` because it had general
edit access and was prohibited only from writing phase-completion files. This allowed an
unreviewed implementation to advance a requirement to `review`, leaving the Conductor to
repair the state before independent review. A later correction is not a gate: the
incorrect state was already visible to subsequent agents.

The Active Requirements table is therefore a controlled lifecycle index. `draft` belongs
to the Architect/spec workflow, `in progress` and `review` belong to the Conductor (or the
direct LOW-path implementation specialist), and only `al-pr-prepare` moves a row to
Completed. Subagents never write `memory.md`; resolved HITL issues leave the requirement
in `review` until the Completion Gate succeeds.

Defense in depth is required for conductor-managed work: snapshot `memory.md` before
invoking the implementation subagent and compare it immediately on return. Any mutation
rejects the result and stops for an explicit human decision; it is never absorbed or
silently repaired as ordinary implementation progress. This is an in-place behavioral
change under D-2. No foundation or Claude-distribution synchronization is required,
because those channels are not used by Aproda.

---

## Stacking vs. changing — practical guide

| Intent | Mechanism | Touches Upstream? |
|--------|-----------|-------------------|
| "Additionally always do X" (e.g. run Deploy-Run-Verify Cycle before PR) | **Stacking**: a new `.aproda.instructions.md` whose `applyTo` matches | ❌ no |
| New capability (Deploy-Run-Verify Cycle, new agent, **site profile, meta-skill**) | **Net-new** `.aproda.` file / `skill-aproda-*` folder | ❌ no |
| Guard an edit to the Aproda layer itself (HITL stop + surface the D-entry) | **Stacking** guardrail instruction matching the layer's globs (D-16) | ❌ no |
| Sync the layer in/out of a project that also has AL-Go + project files | **Allowlist manifest** + overlay sync (D-18), not subtree | ❌ no |
| Reroute an agent to a custom skill/step | **Indirection** (edit the agent in place) | ✅ yes (D-2 conflict) |
| Change/relax an existing rule or flow | **In-place edit** of the original | ✅ yes (D-2 conflict) |

> Stacking can only **add/strengthen**, never **revoke** an Upstream rule (F-5). Anything that must *change or relax* existing behaviour requires an in-place edit (D-2).

---

## Upstream edits (the D-7 / D-2 register — keep current)

The few places where we touched Upstream files in-place. This is the list the upgrade reviewer diffs against.

| File | Change | Decision | Date |
|------|--------|----------|------|
| `copilot-instructions.md` | Added Skills-table row for `skill-aproda-deploy-run-verify` | D-7 | 2026-06-24 |
| `copilot-instructions.md` | Added Skills-table row for `skill-aproda-aldc` (meta-skill) | D-7 / D-16 | 2026-06-25 |
| `agents/al-developer.agent.md` | Added `skill-aproda-deploy-run-verify` to Domain-skills table + workflow step 4 (LOW trigger: once before PR) | D-2 / D-9 | 2026-06-24 |
| `agents/al-conductor.agent.md` | Added skill to Domain Skills + new step **2B-bis** runtime Deploy-Run-Verify Cycle gate + 2C hard-gate clause (MEDIUM/HIGH trigger: per phase) | D-2 / D-9 | 2026-06-24 |
| `agents/al-architect.agent.md` | CANNOT block rewritten: read-only terminal scripts and `runSubagent` for context-gathering explicitly allowed; AL builds/deploys/TDD cycles still forbidden. Duplicate `vscode/runCommand` removed. | D-2 | 2026-08-19 |
| `agents/al-developer.agent.md` | Tool-fit fix: `sshadowsdk` → `SShadowSdk` (correct Marketplace publisher casing); `upstash/context7` → `context7` (correct MCP server key per `mcp.json`). | D-2 | 2026-08-19 |
| `agents/al-implement-subagent.agent.md` | Tool-fit fix: `sshadowsdk` → `SShadowSdk`. | D-2 | 2026-08-19 |
| `agents/al-agent-builder.agent.md` | Tool-fit fix: `sshadowsdk` → `SShadowSdk`; `upstash/context7` → `context7`. | D-2 | 2026-08-19 |
| `agents/al-presales.agent.md` | Tool-fit fix: `upstash/context7` → `context7`. | D-2 | 2026-08-19 |
| `agents/al-developer.agent.md` | Workflow step 4 "Before PR" clause: run `al-doc-update` at delivery if a documented module changed | D-2 / D-14 | 2026-06-24 |
| `agents/al-conductor.agent.md` | Post-completion recommendation table: added `al-doc-update` row next to `al-pr-prepare` | D-2 / D-14 | 2026-06-24 |
| `prompts/al-pr-prepare.prompt.md` | Added «Aproda: Documentation Update (D-13 / D-14)» section before Next Steps: reminds agent to run `al-doc-update` at delivery boundary | D-2 / D-14 | 2026-06-28 |
| `copilot-instructions.md` | Drift-fix: "ALDC Core v1.1" → "v1.2" (lines 7 + footer), matches `core.version: 1.2.0` | D-17 | 2026-06-25 |
| `tools/aldc-validate/index.js` | Drift-fix: compliance banner "v1.1" → "v1.2" | D-17 | 2026-06-25 |
| `README.md` | Added Aproda notice banner with links to `onboarding.aproda.md` and `readme.aproda.md` | D-2 | 2026-07-01 |
| `agents/al-architect.agent.md` | Added ADO work item routing via `skill-aproda-ado` (Bug/Task/US/Feature + ID → `req_name` pattern) | D-2 | 2026-07-07 |
| `agents/al-implement-subagent.agent.md` | Mandatory `skill-testing` load rule + MS test library defaults (Library - Sales/Inventory/Manufacturing/ERM) in test-creation steps; proof token `🧠 skill-testing·MSLibraries` required when tests change | D-2 | 2026-06-29 |
| `agents/al-triage.agent.md` | Added ADO work item routing via `skill-aproda-ado`; subfolder path fix for diagnosis.md (`plans/<id>/<id>-diagnosis.md`) | D-2 | 2026-07-07 |
| `instructions/al-testing.instructions.md` | Test/TestCases + TestLibrary folder rule; MS library-first mandate; mandatory `skill-testing` load token | D-2 | 2026-06-29 |
| `skills/skill-testing/SKILL.md` | Added standard MS test library reference table (MSLibraries section) and symbol-discovery recipe | D-2 | 2026-06-29 |
| `agents/*.agent.md` (all 10) | `model:` re-pinned off the retiring `Claude Sonnet 4.6`: `Claude Sonnet 5` for al-architect / al-presales / al-agent-builder, `GPT-5.6 Terra` for the other seven | D-2 / D-22 | 2026-08-20 |
| `packages/foundation/agents/*.agent.md` (all 10) | Same model pins + both gates — **fork-only distribution mirror**, deliberately absent from `aproda-sync.json` and `aldc.yaml`. Must be changed in lockstep with `agents/` or it drifts silently | D-2 / D-22 | 2026-08-20 |
| `agents/al-architect.agent.md` | Added «Model Escalation Gate (HIGH complexity only)» section before Core Principles: HITL stop recommending Claude Opus 5, fires only at HIGH and only when Opus is not already confirmed | D-2 / D-22 | 2026-08-20 |
| `agents/al-triage.agent.md` | Added «Model Escalation Gate (high-stakes incidents only)» section before the reactive loop: same pattern, trigger = production/data-integrity/customer-facing severity | D-2 / D-22 | 2026-08-20 |
| `docs/agents/*.agent.md` + `docs/agents/index.md` | Doc-drift fix: `**Model**` rows and agent overview tables re-synced to the D-22 pins. **Fork-only** (mkdocs site pages; not in `aldc.yaml`, therefore deliberately *not* added to `inPlaceEdits` — projects do not consume them) | D-2 / D-22 | 2026-08-20 |
| `prompts/al-build`, `al-context.create`, `al-initialize`, `al-memory.create`, `al-pr-prepare` (both trees) | `model:` re-pinned off the retiring `Claude Sonnet 4.5` → `GPT-5.6 Terra` (deterministic procedures, tool loops, structured output) | D-2 / D-22 | 2026-08-20 |
| `copilot-instructions.md`, `agents/al-conductor.agent.md`, `agents/al-triage.agent.md`, `agents/al-review-subagent.agent.md`, `agents/dredd.agent.md` | Added `#aldcConfiguration` usage rule and extension tool allowlist for authoritative root-level configuration in curated consumer workspaces | D-2 / D-24 | 2026-08-27 |
| `skills/skill-aproda-ado/SKILL.md` + `scripts/` | Extended with controlled Azure CLI read/write operations (`Get-AdoWorkItem`, `Get-AdoPullRequest`, `Create-AdoPullRequest`, `Update-AdoWorkItem`) and Pattern 3 (existing-plan hard-stop check). Net-new Aproda skill (D-4) — not an Upstream in-place edit, so not added to `aproda-sync.json → inPlaceEdits` | D-4 | 2026-08-31 |
| `agents/al-architect.agent.md`, `agents/al-conductor.agent.md`, `agents/al-triage.agent.md` | Added CLI-fetch fallback (`Get-AdoWorkItem.ps1` when only an ADO ID/URL is given) and Pattern 3 existing-plan hard stop at the `skill-aproda-ado` load points | D-2 | 2026-08-31 |
| `agents/al-conductor.agent.md`, `agents/al-developer.agent.md` | One-line cross-reference to the HITL Validation phase at the `Status: in progress → review` transition, linking to `hitl-validation.aproda.instructions.md` instead of restating the definition | D-2 | 2026-08-31 |
| `agents/al-conductor.agent.md`, `agents/al-implement-subagent.agent.md` | Exclusive `memory.md` ownership: implementation subagent prohibition plus Conductor snapshot-and-reject gate before independent review | D-2 / D-28 | 2026-08-31 |
| `instructions/hitl-validation.aproda.instructions.md` | Cross-reference to `al-pr-prepare.prompt.md`'s new Completion Gate at the "ready for al-pr-prepare" signal, without duplicating its checklist | D-11 | 2026-08-31 |
| `instructions/hitl-validation.aproda.instructions.md` | Replaced ambiguous status vocabulary with exclusive writers; removed invalid `HITL Validation — All DONE` terminal status | D-11 / D-28 | 2026-08-31 |
| `prompts/al-pr-prepare.prompt.md` | Heading rename `## What` → `## Summary`; new "Aproda: ADO Pull Request Creation" + "Aproda: ADO Completion Comment" sections (ADO-hosted repos, via `skill-aproda-ado`); `/reports/pr-draft.md` deleted after PR creation; new Completion Gate gates the `memory.md` move; Documentation Update reordered before the move | D-2 / D-14 | 2026-08-31 |
| `readme.aproda.md`, `onboarding.aproda.md` | Corrected the "no API fetch" statement to reflect the new CLI capability; added Azure CLI setup (one-time, per workstation) documentation | D-4 | 2026-08-31 |
| `tools/aproda-vscode-extension/package.json` | New walkthrough step `azureCliSetup` between `installBcquality` and `readOnboarding` | D-21 | 2026-08-31 |
| `prompts/al-pr-prepare.prompt.md` | Completion Gate upgraded from a narrated checklist to a self-verified HARD GATE (`git status --short` + file-existence checks, ✅/❌ report required); `memory.md` completion step requires a commit, not just an edit; `pr-draft.md` deletion check made conditional on actual PR creation (not a gate failure if creation failed or repo is GitHub-hosted); added a real completeness check against `{req_name}-hitl-validation-issues.md`'s Status-Board before allowing the move | D-2 / D-26 | 2026-08-31 |
| `copilot-instructions.md` | Added a Core Principles line: AL/ADO HITL gates (`al-conductor`/`al-developer` delivery-boundary updates, `skill-aproda-ado` write approvals + AI disclaimer) apply even without an explicit `@`-agent | D-2 | 2026-08-31 |

---

## Version / pin changelog

| Date | Upstream ref adopted | Aproda layer version | Notes |
|------|----------------------|----------------------|-------|
| 2026-06-24 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.1` | Initial Aproda layer set up; ALDC base recorded retroactively (D-17) |
| 2026-06-25 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.1` | Versioning scheme adopted (D-17); upstream == fork at this SHA (in sync) |
| 2026-07-02 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.2` | BCQuality clone folder renamed `bcquality` → `bcquality-aproda`; scheme separator changed `+` → `_` (URL-safe); tagging rule added |
| 2026-07-06 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.3` | Terminology: "Test-Loop" → "Deploy-Run-Verify Cycle", "UAT loop" → "HITL Validation" across all docs, agents, skills, instructions (display names only; technical identifiers unchanged) |
| 2026-07-06 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.4` | Full technical rename: `uat-loop.aproda.instructions.md` → `hitl-validation.aproda.instructions.md`; `{req}-uat-issues.md` → `{req}-hitl-validation-issues.md`; `skill-aproda-test-loop/` → `skill-aproda-deploy-run-verify/`; `AprodaTestLoop.psm1` → `AprodaDeployRunVerify.psm1`; `Invoke-AprodaTestLoop.ps1` → `Invoke-AprodaDeployRunVerify.ps1`; `testloop.config.template.jsonc` → `deploy-run-verify.config.template.jsonc`; all PS function names (TestLoop → DeployRunVerify); all env vars (APRODA_TESTLOOP_* → APRODA_DEPLOY_RUN_VERIFY_*); all external path/doc references updated. Alias note added to SKILL.md description (Option 1). |
| 2026-07-07 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.5` | Naming compliance fix: `skill-ado/` → `skill-aproda-ado/` (D-4 convention: Aproda-specific skills must carry `skill-aproda-*` prefix so the allowlist glob auto-picks them up); all references updated in agents, readme.aproda.md, onboarding.aproda.md, SKILL.md frontmatter. |
| 2026-07-07 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.6` | Sync layer audit: `aproda-sync.json` `inPlaceEdits` completed (added `README.md`, `al-architect`, `al-implement-subagent`, `al-triage`, `al-testing.instructions.md`, `prompts/al-pr-prepare.prompt.md`, `skills/skill-testing/SKILL.md`); stale-cleanup tombstone added for `skills/skill-ado` (renamed to `skill-aproda-ado`); D-7 register brought in sync. |
| 2026-07-07 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.6` | Sync layer audit: `aproda-sync.json` `inPlaceEdits` completed (added `README.md`, `al-architect`, `al-implement-subagent`, `al-triage`, `al-testing.instructions.md`, `prompts/al-pr-prepare.prompt.md`, `skills/skill-testing/SKILL.md`); stale-cleanup tombstone added for `skills/skill-ado` (renamed to `skill-aproda-ado`); D-7 register brought in sync. |
| 2026-08-05 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.7` | `skill-aproda-ado/SKILL.md`: `req_name` pattern extended to `{type}-{id}-{short-name}` — short name derived from work item title (kebab-case, max 4–5 meaningful words, noise words stripped); table examples updated. `prompts/al-pr-prepare.prompt.md`: updated (model + tools). |
| 2026-08-19 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.8` | *(logged retroactively)* Tool-fit fixes across agents: `sshadowsdk` → `SShadowSdk` (publisher casing), `upstash/context7` → `context7` (MCP server key); `al-architect` CANNOT-block rewritten (read-only terminal + `runSubagent` allowed, builds/deploys still forbidden). |
| 2026-08-20 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.9` | Model re-pinning (D-22): all 10 agents off the retiring `Claude Sonnet 4.6` → 3× `Claude Sonnet 5` (doc-producing roles), 7× `GPT-5.6 Terra` (code/tool-loop/JSON roles); both `agents/` and the `packages/foundation/agents/` mirror. Model Escalation Gate added to `al-architect` (HIGH complexity) and `al-triage` (high-stakes incident) — HITL stop recommending Claude Opus 5, never naming the running model. `aproda-sync.json` `inPlaceEdits` extended with `al-planning-subagent`, `al-review-subagent`, `dredd`. Workflow prompts migrated off the retiring `Claude Sonnet 4.5`: 5× `GPT-5.6 Terra` + `al-doc-update.aproda` → `Claude Sonnet 5`; `al-spec.create` keeps GPT-5.3-Codex (GA, not retiring); `inPlaceEdits` extended with the four newly touched prompts. |
| 2026-08-27 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.10` | CI-gated release governance (D-25): the layer and VSIX release workflows validate candidates pushed to `aproda`, wait for dedicated GitHub Environment approval, then create their own tags and GitHub Releases. Added the fork-only `skill-aproda-aldc-release`, explicitly excluded from overlay sync. The internal extension supports credential sign-in retry and versioned VSIX assets (`aproda-aldc-<semver>.vsix`). |
| 2026-08-27 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.11` | Updated the guided extension onboarding: the first-run notification opens the native Aproda ALDC walkthrough directly, its second step applies the toolkit, and the extension uses Toolkit terminology in user-facing messages and documentation. Resetting extension-owned data restores the initial setup notification without resetting VS Code walkthrough progress. |
| 2026-08-27 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.12` | Published the current approved Aproda toolkit state as the next CI-gated layer release revision. |
| 2026-08-31 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.13` | ADO integration hardening (D-26) + `CHANGELOG.aproda.md` introduced (D-27); see CHANGELOG.aproda.md for the prose account. |
| 2026-08-31 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.14` | `tools/aproda-sync/templates/gitignore-block.txt`: added `.github/audits/` and `.github/reports/` to the managed `.gitignore` block. |
| 2026-08-31 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.15` | `memory.md` ownership gate and HITL status contract (D-28). |
