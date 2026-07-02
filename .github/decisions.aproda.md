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
The test-loop scripts are packaged as a **parameter-driven engine** under `skills/skill-aproda-test-loop/scripts/` (`AprodaTestLoop.psm1` + thin entry + `testloop.config.template.jsonc`). The **engine is immutable** — the agent never edits it per project; it copies the config template and fills the few non-derivable values (apps in dependency order, runner dir, server-side Mgmt DLL). Everything else auto-derives from `launch.json` + each `app.json`. This is the reusable-across-projects goal: new project = a ~3-line config, not a rebuilt script.
**Origin:** generalized from the proven project-local `Test/PowerShell/_Cycle.ps1` + `_RunTests.ps1` (Audit Trail 26/26), which stay in place as the validated reference (single-source-of-truth; the engine is their parameterized form, not a duplicate). Environment-specific scripts are **not** put under `.github/` — only the generic engine is; concrete instances stay project-local.

### D-9 — Agents must be wired in-place to actually apply the skill ("Voll A")
A global row in `copilot-instructions.md` (D-7) is **not enough**: each agent follows its **own** skill table, so the skill must be added to the agents that use it. Chosen approach: **Voll A — both agents edited in-place** (not an additive instruction), because the conductor change is a **flow change** (a phase gate), which F-5 says stacking cannot achieve.
- **al-developer**: `skill-aproda-test-loop` added to the Domain-skills table + workflow step 4 — **LOW-complexity trigger: run once, after implementation, before PR.**
- **al-conductor**: skill added + new **step 2B-bis runtime test-loop gate** + 2C hard-gate clause — **MEDIUM/HIGH trigger: run per phase**, bound to the existing phase boundary (a phase is not complete until green or a service blocker is acknowledged).
- **Trigger policy** is deliberately bound to the existing LOW / MEDIUM-HIGH complexity tiers, not a new heuristic (matches the skill's `When to Load`).
- **Cost accepted:** the Upstream-touch register grows from 1 to 3 files (more D-2 merge-points). Justified because soft stacking could not enforce the conductor phase gate (F-5).

### D-10 — Delivery boundary defines pre- vs post-delivery handling
The **delivery boundary** is the moment a requirement is **accepted** (UAT sign-off / merge+deploy to the target environment). It splits the change lifecycle in two regimes with different document rules (D-11) and change-classification (D-12):
- **Pre-delivery** = still iterating toward first acceptance. Many UAT loops are normal and expected.
- **Post-delivery** = the requirement was accepted; any further change is a *new* effort.

ALDC itself has **no** post-delivery amendment workflow (verified: reactive tier routes unknown bugs via `@AL Triage`, but there is no patch/amendment spec type). D-10..D-13 fill that gap for Aproda **without** touching Upstream — they are documentation/convention only, enforced by a stacking instruction (D-4), not by editing ALDC agents.

### D-11 — Pre-delivery: spec edited in-place + a separate `uat-issues.md` work-item
While pre-delivery, the requirement's `{req}.spec.md` is a **draft** and stays the **single source of truth for the target state** — it is **edited in-place** each UAT loop (git history is the change log). The spec describes *how the system should be*; it carries **no status and no checklist**.

*What is still to do* lives in a **separate** `{req}-uat-issues.md` work-item, NOT in the spec:
- A **Status-Board** (index table) at the top: `ID | Title | Loop | Priority | Type | Status`.
- One **detail block** per issue below, each with a `Status:` field (`TODO` / `IN-PROGRESS` / `DONE`).
- **UAT loops are headers within the one file** (`## Loop 1 — <date>`), **not** separate `loop1.md`, `loop2.md` files — one file = one work-source for the agent.
- **Issue numbers are global and monotonic** (I-1, I-2, … I-n) across all loops, never reset per loop, so every git/commit reference stays unique.
- **Agent contract**: *read the Status-Board → take the next `TODO` (respect implementation order) → load only that issue's detail block (token-efficient) → fix → run the test-loop → set `DONE`.* The agent only fixes/extends/adjusts; the spec is the target reference, never a checklist.

**Rejected**: (a) a second sibling spec per loop (two specs = no source of truth); (b) one file per loop (splits the work-source, breaks global numbering, clutters the folder); (c) a spec `git diff` as the to-do signal (mixes typo-fixes with behaviour changes, and "already implemented" is not in the diff). An explicit `Status:` field beats an implicit diff.

> **Splitting is pain-driven, not prophylactic**: keep it one file until the Status-Board itself is drowned out; only then archive old `DONE` loops into `{req}-uat-issues-archive.md`. The real token lever is the agent contract ("board, then one TODO block"), not file count.

### D-12 — Post-delivery: new plan folder; Bug vs Enhancement classified against the frozen spec
At the delivery boundary (D-10) the spec is **frozen**. Any later change starts a **new plan folder** and is classified by comparing against that frozen spec:
- **Bug** = behaviour deviates from what the (frozen) spec demanded → SemVer **Revision** bump.
- **Enhancement / new scope** = behaviour the spec never promised → SemVer **Minor** bump (or its own requirement).

This classification also applies **within** pre-delivery loops to label each issue (Type column), but only post-delivery does it force a *new plan*. Example from `audit-trail-extension-1` loop 1: I-4/I-7 are **Bugs** (the spec demanded the gate / the translations); I-1/I-3 are **Enhancements / under-spec** (D-04 explicitly stated "Allowed + untracked", so the new "start Blocked" behaviour is a scope change, not a bug).

### D-13 — Naming & placement: transient plans vs durable module docs
Two distinct lifecycles get two distinct homes:
- **Transient, per-requirement** (spec, uat-issues, architecture, test-plan, phase/plan-complete) → `.github/plans/{req}/`. Post-delivery follow-ups: `{req}-2/` (new scope) or `{req}-fix-{n}/` (post-delivery bug).
- **Durable, per-module** (lives across all requirements/loops) → `.github/documentation/<Module>/`:
  - `<Module>.reference.md` — technical module reference (**English**). Lean: links to the `.al` files + the module SKILL as source-of-truth, never mirrors IDs/paths.
  - `<Module>.Handbuch.de-CH.md` — user handbook (**de-CH**, Aproda standard for end-user docs).

`.github/documentation/` is **distinct from** `.github/docs/` (the latter is ALDC framework templates + schema — not module content). Module docs reflect the **target state**; while related UAT issues are still `TODO`, the reference may describe the soll-state ahead of the code — acceptable for a reference, by design.

> **Agent awareness of D-11**: agents do not know this convention natively. It is surfaced additively via a stacking instruction (`instructions/*.aproda.instructions.md`, D-4) — **not** by in-place agent edits (D-9), because the UAT-loop rule is purely additive ("additionally, when a `uat-issues.md` exists, consume it this way"), which Stacking can express (F-5). The `uat-issues.md` file is also self-describing (carries the agent contract in its header) as a second, redundant safeguard.

### D-14 — Module documentation maintenance: a workflow, not a doc-agent
The durable per-module docs (D-13: `<Module>.reference.md` EN + `<Module>.Handbuch.de-CH.md`) are kept current by a **net-new `.aproda.` workflow** `al-doc-update` (`prompts/al-doc-update.aproda.prompt.md`, D-4 — no Upstream conflict), **not** by a dedicated documentation agent.

**Why a workflow, not an agent**: generating docs is a **deterministic procedure** (read code/spec → render → write the two files), not a role with judgment. ALDC models such procedures as *workflows* (`al-context.create`, `al-memory.create`), not agents. A doc-agent would be a persona with nothing to decide — overkill. Rejected.

**Trigger — the delivery boundary (D-10)**, alongside `al-pr-prepare`: docs should mirror the **final** target state, so regenerating them per individual UAT fix is waste; the spec only stabilizes at acceptance. Wiring (extends the **existing** D-9 touch-points, so the register does not grow new *files*):
- **al-developer**: the workflow-step-4 "Before handing off for PR" sentence gains a delivery-boundary clause — *if a documented module changed, run `al-doc-update`.* (LOW trigger.)
- **al-conductor**: the post-completion recommendation table gains an `al-doc-update` row next to `al-pr-prepare`. (MEDIUM/HIGH trigger.)

The workflow is **documentation-only**: it must not edit `.al`, the spec, or the `uat-issues.md`, and must not duplicate IDs/paths/signatures (D-13 — link, don't mirror). It does not commit (that is `al-pr-prepare`).

### D-15 — Test-loop standardized on the own engine: central glue + DVD-materialized runner DLLs + SRP-safe loading
The test-loop is standardized on the **own engine** (D-8); `jamespearson/al-test-runner` is **fallback only** (its Newtonsoft.Json fix lives outside the workspace, unversioned — the instability that motivated this). Validated end-to-end: **27/27 green** via the engine against BC 28 OnPrem. Three refinements to D-8, all **skill-internal** (no new Upstream touch-points, register unchanged):

- **Central glue.** The 3 version-agnostic glue scripts (`ClientContext.ps1`, `PsTestFunctions.ps1` — MS canonical, MIT; `AprodaRunner.ps1` — Aproda wrapper) ship **once** in `scripts/runner-glue/`, not per project, not per runner version. The engine resolves `glueDir` from its own module location. `New-TestLoopRunner` is **DLL-only**.
- **Runner DLLs materialized from the K: BC DVD.** `Initialize-TestLoopRunner` + `Resolve-TestLoopClientSource` derive the 4 version-pinned client DLLs from the deterministic DVD layout `<bcDvdRoot>\<major>\<bcCountry>.<major>.<minor>\Applications\TestFramework\TestRunner\Internal` (config `bcDvdRoot` + `bcCountry`; highest minor wins). Alternatives: explicit `runnerClientSource` (wins) or `runnerClientFromServer` (remote-PS pull, fallback). The **whole `_runner/` folder is git-ignored** — nothing under it is committed.
- **SRP-safe script loading.** This estate's Group Policy / Software Restriction Policy **blocks path-based PowerShell execution** (`. <path>.ps1`, `Import-Module`) workspace-wide → `PSSecurityException`. Everything is loaded **content-based** via `[ScriptBlock]::Create((Get-Content -Raw))`: the entry point loads the engine; the run-bootstrap loads all 3 glue files, `Add-Type`s the client DLLs **before** the `ClientContext` scriptblock (its class references `Microsoft.Dynamics.Framework.UI.Client.*` at parse time), and regex-neutralizes PsTestFunctions' internal `. $clientContextScriptPath`. `Get-Content` (reading) is not SRP-blocked; only path-based *execution* is.

### D-16 — Self-knowledge: a site profile, a meta-skill, and a steward guardrail
The layer must carry **its own infrastructure facts** and **its own how-to-extend knowledge**, so a fresh chat / new repo isn't blind to the estate (K:, NST servers, SRP, remote-PS) or to the `.aproda.` conventions. Three net-new artifacts (all `.aproda.` / `skill-aproda-*` → **no Upstream touch-points**, register unchanged), plus one personal fallback:

- **`site-profile.aproda.md`** (net-new doc) — concrete, org-wide **infrastructure facts**: topology (VS Code local, BC on `apd-svw-nst0x`, `D:\` server-only, `K:\` local), remote-PS, the **SRP path-execution block + content-based workaround**, the **K: BC DVD** layout, the web-client port-80 rule, paste mangling. It is **referenced on demand** by the Aproda skills, **never auto-loaded** (the user's constraint: most users only apply, few change). Site facts only — project-specific values stay in `testloop.config.jsonc` / `launch.json` (link, don't duplicate, D-13).
- **`skill-aproda-aldc`** (net-new meta-skill) — **Explain** (what is the layer / why decision D-N) for the many onboarding questions, and **Extend** (the stacking-vs-in-place decision tree + record + flow-back procedure) for the few who change it. It **links** `readme.aproda.md` / `decisions.aproda.md` / `site-profile.aproda.md`; it never copies them. **Not a new agent** — explaining is Q&A from a knowledge body, extending is a procedure with judgment, which ALDC models as a *skill/workflow*, not a persona (same reasoning that rejected a doc-agent in D-14).
- **`aproda-aldc-steward.aproda.instructions.md`** (net-new stacking instruction, `applyTo: **/*.aproda.*, **/skill-aproda-*/**`) — the **HITL guardrail**. Because an Upstream-behaviour change could be made by a user who doesn't know it's deliberate, the trigger must be **invocation-independent**: only an auto-applied `applyTo` glob fires when *any* layer file is edited, even in a normal chat that never `@`-calls a steward. It **stops and requires confirmation** before changing/relaxing anything, surfaces the relevant D-entry, and reminds that the change must **flow back to the fork**. Stacking only strengthens (F-5) — it adds a gate, revokes nothing.
- **User-memory fallback** (`/memories/aproda-infra.md`, personal, cross-workspace) — a redundant condensed copy of the infra facts that travels with the developer's account into repos that don't carry the full `.github/` subtree. Redundancy is deliberate (same principle as the self-describing `uat-issues.md`, D-11).

**Distribution (the user's decision):** everything ships to **every project** via the subtree; **reading/applying** happens everywhere, **changing** happens where the need arises (with live validation), and the change is only adopted once it is **pushed back to the aproda-aldc fork** — the inverse direction of the D-6 upgrade pull. Fork = source of truth; project copies = working copies.

### D-17 — Sub-versioning the fork: `<ALDC core.version>_aproda.<n>` + a recorded base pin
The Aproda layer had **no version of its own** and the ALDC base it sits on was an unfilled placeholder — so "how far is the fork from Upstream?" was unanswerable. Adopted a composite version: `<ALDC core.version>_aproda.<revision>` (current: `1.2.0_aproda.2`), URL-safe and unambiguous; where the left side is the adopted ALDC `core.version` and the right side is the Aproda revision counter, bumped each time the layer is pushed to the fork. The **ALDC base commit** is pinned in `aldc.yaml → aproda.basePin` and echoed in the Version/pin changelog (current: `a900263f51e416762cc7f85575deb9b30cd5b1e3`; at this SHA upstream == fork, i.e. all our `.aproda.` work is the working-tree delta on top of a synced base). Single source of truth for the numbers = `aldc.yaml → aproda` (mirrors the `external.bcquality` pin pattern). The drift where `copilot-instructions.md` (and the `aldc-validate` banner) still said "ALDC Core v1.1" against `core.version: 1.2.0` was corrected at the same time — a candidate for an upstream PR, registered below.

**Index, not a new file:** the question "does the fork need an index?" resolves to **no new artifact** — the existing `readme.aproda.md` inventory table ("What lives here") **is** the Aproda index. It is refreshed to list every net-new primitive with live status. Upstream per-type `index.md` files are deliberately **not** touched (would multiply merge-points, against D-7).

### D-18 — Layer sync by ALLOWLIST manifest, not subtree (coexists with AL-Go + project files)
A project's `.github/` has **three owners**: AL-Go (`workflows/*`, `AL-Go-Settings.json`, `.AL-Go/`), the Aproda toolkit (this layer), and the project itself (`plans/`, `documentation/`, app). `git subtree --prefix=.github` treats the whole tree as one unit — it would overwrite AL-Go/project files on pull and upload them on push. **Rejected.** Instead the layer is synced by a small script (`tools/aproda-sync/Sync-AprodaLayer.ps1`) driven by an **allowlist manifest** (`tools/aproda-sync/aproda-sync.json`).

**Why allowlist (include), not blocklist (exclude) — the user's argument:** the decisive question is the *default* for an **unknown future file**. A blocklist defaults to *touch it* (must remember to exclude every new AL-Go/project file — default-unsafe, constant upkeep, one miss = an accident). An allowlist defaults to *leave it alone* (a miss merely means a new Aproda file isn't synced yet — visible, harmless, destroys nothing). The Aproda layer is **self-identifying** (D-4): the convention globs `**/*.aproda.*` + `skills/skill-aproda-*/**` grow automatically, so the allowlist needs almost no upkeep. AL-Go and project files need **no manifest entry at all** — not being on the list = invisible to the sync in both directions.

**Allowlist sources** (resolved by the script): (1) convention globs (self-growing); (2) named net-new files without the infix (`readme.aproda.md`, `decisions.aproda.md`, `site-profile.aproda.md`, the syncer itself); (3) **`inPlaceEdits`** — the Upstream files we edited, kept **redundant** in the JSON (user's choice: explicit beats parsing the markdown register; it mirrors the D-7 table, which is updated for governance anyway); (4) ALDC framework files scraped from `aldc.yaml required`/`optional` (toggle `includeAldcFramework`). A `neverTouch` tripwire (`plans/**`, `documentation/**`, `workflows/**`, `AL-Go-Settings.json`, `.AL-Go/**`) is a redundant belt-and-suspenders, with `workflows/bcquality-evidence.yaml` as the one Aproda-owned exception.

**Two safety properties:** (a) **overlay-only** — sync copies, never deletes a destination file it doesn't own, so AL-Go/project files survive even a manifest gap; (b) **push filters through the same allowlist** — `plans/`/`documentation/` physically cannot reach the fork because they aren't listed. The script is SRP-safe (cmdlet-only, no path-based dot-sourcing) and supports `-WhatIf` dry-run. Flow mirrors D-16: pull (fork→project) overlays the layer; push (project→fork) stages only layer files for a PR — the change is real once merged into the fork.

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

---

## Stacking vs. changing — practical guide

| Intent | Mechanism | Touches Upstream? |
|--------|-----------|-------------------|
| "Additionally always do X" (e.g. run test-loop before PR) | **Stacking**: a new `.aproda.instructions.md` whose `applyTo` matches | ❌ no |
| New capability (test-loop, new agent, **site profile, meta-skill**) | **Net-new** `.aproda.` file / `skill-aproda-*` folder | ❌ no |
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
| `copilot-instructions.md` | Added Skills-table row for `skill-aproda-test-loop` | D-7 | 2026-06-24 |
| `copilot-instructions.md` | Added Skills-table row for `skill-aproda-aldc` (meta-skill) | D-7 / D-16 | 2026-06-25 |
| `agents/al-developer.agent.md` | Added `skill-aproda-test-loop` to Domain-skills table + workflow step 4 (LOW trigger: once before PR) | D-2 / D-9 | 2026-06-24 |
| `agents/al-conductor.agent.md` | Added skill to Domain Skills + new step **2B-bis** runtime test-loop gate + 2C hard-gate clause (MEDIUM/HIGH trigger: per phase) | D-2 / D-9 | 2026-06-24 |
| `agents/al-developer.agent.md` | Workflow step 4 "Before PR" clause: run `al-doc-update` at delivery if a documented module changed | D-2 / D-14 | 2026-06-24 |
| `agents/al-conductor.agent.md` | Post-completion recommendation table: added `al-doc-update` row next to `al-pr-prepare` | D-2 / D-14 | 2026-06-24 |
| `prompts/al-pr-prepare.prompt.md` | Added «Aproda: Documentation Update (D-13 / D-14)» section before Next Steps: reminds agent to run `al-doc-update` at delivery boundary | D-2 / D-14 | 2026-06-28 |
| `copilot-instructions.md` | Drift-fix: "ALDC Core v1.1" → "v1.2" (lines 7 + footer), matches `core.version: 1.2.0` | D-17 | 2026-06-25 |
| `tools/aldc-validate/index.js` | Drift-fix: compliance banner "v1.1" → "v1.2" | D-17 | 2026-06-25 |

---

## Version / pin changelog

| Date | Upstream ref adopted | Aproda layer version | Notes |
|------|----------------------|----------------------|-------|
| 2026-06-24 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.1` | Initial Aproda layer set up; ALDC base recorded retroactively (D-17) |
| 2026-06-25 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.1` | Versioning scheme adopted (D-17); upstream == fork at this SHA (in sync) |
| 2026-07-02 | `a900263f51e416762cc7f85575deb9b30cd5b1e3` | `1.2.0_aproda.2` | BCQuality clone folder renamed `bcquality` → `bcquality-aproda`; scheme separator changed `+` → `_` (URL-safe); tagging rule added |
