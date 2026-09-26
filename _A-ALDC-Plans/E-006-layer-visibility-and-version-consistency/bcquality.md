# BCQuality — evidence, audits and the per-user clone path

> **Own chapter, split out of E-006 on 2026-09-24.** BCQuality surfaced as a side finding while closing
> Block 1 (F-16), but it is not a layer-visibility problem — it is its own subject with its own
> requirement, its own defects and its own decision. Keeping it inside
> [`findings-01`](findings-01-layer-visibility.md) would bury it.
>
> **Status until Block 4: leave everything as-is.** No code, config or shipped doc has been changed.
> It is a notebook, not a change log — with one growing exception: **T-22 has been designed, tested and
> decided** (2026-09-24). §1.3–§1.6 carry a researched design, five measured test rounds, and four
> decisions (`.external/bcquality` layout, dual path, no `.gitkeep`, S1 opt-in). Designing and measuring
> is not changing — no shipped artifact has been touched. Findings **B-9** and **B-10** and items
> **T-28–T-33** came out of that work.
>
> **✅ Superseded 2026-09-25 — Block 4 is implemented.** The paragraph above describes the state *before*
> implementation and is kept for the design trail. All eight Block-4 items (**T-33, T-22, T-28, T-29,
> T-17, T-24, T-25, T-35**) are now implemented, each reviewed by an independent subagent and re-fixed
> where the review found defects. **Nothing is committed** — the work sits in the working tree for the
> maintainer. Six new findings (**B-12–B-17**) and three new open items (**T-36–T-38**) came out of the
> implementation; see §4 and §5. The deferred Block-5 items (**T-21, T-23, T-26, T-27, T-34**) were
> verified untouched.

---

## 1. The requirement (user, 2026-09-24)

> *"Es soll zuverlässig pro user funktionieren. Jeder user kann sein BCQ clone an einem anderen Ort im
> Verhältnis zum Projekt-Repo haben. Workspace + aldc sind repo settings, also nicht optimal. Idee wäre,
> diesen Pfad zentral in den VS Code user settings zu führen. Muss stabil funktionieren."*

Restated: **the clone location is a property of the workstation, not of the repository.** Today it is
configured in two repo-scoped places (`aldc.yaml → external.bcquality.home`, `*.code-workspace`), which
forces every developer onto the same relative layout and makes the value wrong for anyone who deviates —
including the fork itself (see B-5). The target is a single, user-scoped, reliably resolved path.

### 1.1 Resolution mechanisms that already exist

`validate_evidence.py` resolves the clone in this order (lines 81–115):

1. `--bcquality-root` (CLI argument)
2. `$BCQUALITY_HOME` (environment variable) — **already user-scoped**
3. `aldc.yaml → external.bcquality.home` (repo-scoped)

Then it confirms the clone by probing `skills/entry.md`.

So a user-scoped channel **exists at the script level** — but none of it reaches the two consumers that
actually matter. See §1.2.

### 1.2 Five consumers, four channels, no precedence (measured 2026-09-24)

| Consumer | Reads | Scope |
|---|---|---|
| Agents (`al-conductor`, `al-review-subagent`, `dredd`, `al-triage`) | `#aldcConfiguration` → `home` (repo-relative), then `read_file <home>/skills/entry.md` | **repo** |
| VS Code multi-root | `*.code-workspace → folders[].path` (repo-relative) | **repo, tracked** |
| `validate_evidence.py` | `--bcquality-root` → `$BCQUALITY_HOME` → `aldc.yaml home` | mixed |
| `install.sh` / `install.ps1` | `$BCQUALITY_HOME` → `../bcquality` | env / default |
| Aproda VS Code extension (`bcquality/install.ts`) | `aprodaAldc.bcquality.path` → `<devRoot>/BCQuality-Aproda` | **user (Global)** ✅ |

**The decisive finding:** a user-scoped channel already exists (`aprodaAldc.bcquality.path`), but it
reaches neither consumer that matters.

- `readAldcConfigurationTool.ts` returns `home` **verbatim from `aldc.yaml`** and never consults the user
  setting. Agents therefore always receive the repo value — even when it is wrong (= B-5 / T-17).
- `workspace/bcqualityRoot.ts` writes the per-user path **into the tracked `*.code-workspace`**, plus
  `BCQUALITY_HOME` into `terminal.integrated.env.windows`. A workstation property is persisted into a
  versioned repo file → per-developer git churn. The syncer's `neverTouch` does not prevent this; it
  only prevents overwriting, not dirtying.

**Second finding, easy to miss:** agents cannot read files outside the workspace roots. A correct user
setting alone does **not** make BCQuality readable to an agent. Any solution must deliver both —
*resolve* **and** *reach*.

### 1.3 Design (2026-09-24) — recommendation: resolver + `#bcquality` LM tool

> **Recorded as [D-49](../../.github/decisions.aproda.md) on 2026-09-25** — the governing decision under
> the D-16 steward guardrail, written before any implementation. This section remains the working
> design trail; D-49 is the durable record.

**Canonical channel = `aprodaAldc.bcquality.path`** (VS Code Global/Machine, absolute). That is the only
layer that models "per workstation, across all repos" correctly.

**One resolver in the extension** (new `src/bcquality/resolve.ts`), documented precedence, every candidate
confirmed by probing `<root>/skills/entry.md` — never an unverified path. Returns
`{ root, resolvedFrom, verified }`:

```
1. aprodaAldc.bcquality.path              (user / machine setting)
2. mounted workspace folder containing <entryPoint>   (discovery)
3. $BCQUALITY_HOME                        (script bridge)
4. <devRoot>/BCQuality-Aproda             (convention)
5. aldc.yaml → external.bcquality.home    (repo default, last)
```

**Reaching the agent — the key move.** Instead of mounting the clone, the extension contributes a
**`#bcquality` language-model tool** (`read` + `list`) that serves files relative to the resolved clone.
Precedent is already in the repo: `#aldcConfiguration` exists precisely because it *"works when the
repository root is not itself a workspace folder"* ([D-24](../../.github/decisions.aproda.md)). With the
tool, the clone may sit anywhere on disk and **needs no workspace root at all** — no repo file carries a
per-user value any more.

**Planned change set:**

| # | Change | Owner | Merge point (D-2) |
|---|---|---|---|
| 1 | `resolve.ts` — the resolver above | Aproda extension | none |
| 2 | `bcquality/install.ts` → use the resolver (today: setting → `<devRoot>/…`, unverified) | Aproda extension | none |
| 3 | `readAldcConfigurationTool.ts` → add `resolvedHome`, `resolvedFrom`, `mounted`; keep `home` | Aproda extension | none |
| 4 | **New `#bcquality` tool** (`read` + `list`) + agent prose switched from `read_file ../bcquality/…`, **keeping the path read as a documented fallback** (dual path, see §1.6) | extension + 4 agent files | **existing** (D-24 already edited all four for `#aldcConfiguration`) |
| 5 | `aldc.yaml → home` — **value fix only** (= T-17), comment and schema untouched | dualVariant | T-17's, no extra |
| 6 | `BCQUALITY_HOME` → `ConfigurationTarget.Global`, for `windows`/`linux`/`osx`; stop writing it into the workspace file | Aproda extension | none |
| 7 | Fail loudly (→ T-23): `enabled: true` + unverified = visible error; `auto` = explicit `not-applicable` **with the resolver's reason**, surfaced in the checkpoint card | extension + agent prose | existing |

Precedence changes in `validate_evidence.py` and the install scripts stay **upstream-PR candidates**
(§2), not fork edits.

**Comfort features (Aproda extension, additive):**

| Feature | Why | Verdict |
|---|---|---|
| Status-bar item `🟢/⚪ BCQuality` | The only permanently visible proof that the knowledge layer is live; today you notice at review time | yes |
| Command `Show BCQuality Status` — quick-pick of the full resolver chain, per candidate path + verdict (`verified` / `no entry.md` / `not set`) | Makes the silent failure class B-5 visible in one click; the UI half of "fail loudly" | yes |
| Startup self-heal — setting points at a missing directory → notification with *Install / Update BCQuality* (`startup/check.ts` already has the pattern) | Covers the common real case: clone deleted or moved | yes |
| `Mount BCQuality in this Workspace` via `updateWorkspaceFolders` | Does **not** help: in a saved multi-root workspace VS Code writes the change back into the `.code-workspace` — the very churn being removed | no |
| Show BCQuality HEAD SHA in the status | Belongs to the pin question (T-24 / B-7), not to T-22 | defer |
| Extend `commands/validate.ts` with the BCQuality resolution | One command instead of two | optional |

**Order:** resolver → tool output → `#bcquality` tool → status-bar / show-status. Agent prose last, so the
resolver is proven before agents depend on it.

### 1.4 Alternatives considered and rejected

| Option | Why not |
|---|---|
| **`$BCQUALITY_HOME` as the canonical channel** | Agents do not read env vars; requires out-of-band per-machine setup and a VS Code restart; today only `terminal.integrated.env.windows` (terminal-only, Windows-only) → reaches neither the extension host nor the agents. Fails the stated reliability bar. Kept as the *script/CI bridge* only |
| **Repo-local untracked override** (`aldc.local.yaml`) | Per-repo **and** per-user → does not scale across a project fleet; contradicts "property of the workstation" |
| **`site-profile.aproda.md`** | Repo-scoped as well — wrong layer |
| **Discovery only** | Good as a fallback rung, but does not solve reachability and must fail loudly or it just trades one silent failure for another. Folded in as rung 2 of the resolver |
| **Agents reference the workspace-root *name* instead of a path** | Only moves the problem into the still-tracked `.code-workspace` |
| **Gitignore the generated `*.code-workspace`** (proposed, then withdrawn) | Converts an upstream-shipped, conflict-free file into a permanent D-2 merge point and contradicts the upstream doc ("commit the file") — exactly what E-006's *Explicitly not doing* rejects |
| **Extension writes `home` into `aldc.yaml`** at Apply Toolkit (proposed 2026-09-25, then withdrawn) | **Provably redundant**: `aldc.yaml` is gitignored in a consumer, so a written value never leaves the machine that wrote it — and on that machine the extension is present, so resolver rungs 1–4 already answer before rung 5 (`home`) is reached. *The write can only benefit a machine that already knows better.* **And it is not free**: `Bootstrap-AprodaProject.ps1` rewrites `aldc.yaml` as a `dualVariant` file, and the **fleet scripts call the same bootstrap** — one `Start-FleetUpdate` would silently reset `home` across every repo. That would need a "preserve" rule in the sync manifest, producing a value that is *sometimes right and silently stale otherwise* — E-006's own failure class. **Instead:** `Show BCQuality Status` displays declared vs resolved side by side, so the divergence is visible rather than papered over |
| **Syncer scripts read the VS Code user settings** to resolve the clone | Technically possible, but **no consumer needs it**: `Bootstrap-AprodaProject.ps1` never touches BCQuality, and the fleet scripts *skip* BCQuality repos by design (`$SkipRepos = @('BCQuality*','bcquality*')`). The only script that needs the path is `validate_evidence.py`, which already honours `$BCQUALITY_HOME`. Building the reader would couple PowerShell to an editor's private storage (JSONC parsing, plus Code / Insiders / VSCodium / portable and three OS path variants) for no gain |

**Placeholders in the workspace file are impossible — verified against the VS Code docs (2026-09-24).**
The workspace schema allows *"either absolute or relative paths"*; variable substitution exists only in
`launch.json`, `tasks.json` and *"some select settings"* (`terminal.integrated.cwd/env/shell/shellArgs`,
`window.title`). `${env:BCQUALITY_HOME}` or `${config:aprodaAldc.bcquality.path}` in `folders[].path`
resolves to a **literal folder name**. A path "pulled from user settings" inside the workspace file is
therefore ruled out.

### 1.5 Plan B — junction sidecar (S1), if a real mount is wanted

> **Final layout, decided 2026-09-24** (after the round-4 fix below). The tests were run with
> `.bcquality` and later `BCQuality/.bcquality`; **every result is name-independent** — nothing measured
> depends on the strings, only on the wrapper/subfolder relationship.
>
> ```
> .external/                ← wrapper; mounted as the workspace root
>   ├─ README.md             ← tracked; explains the junction — see below
>   └─ bcquality/            ← the junction onto the resolved clone
> ```
>
> `aldc.yaml → home: ".external/bcquality"` — **a constant, correct by construction for the shipped
> layout** (see the correction history below), exclude glob `bcquality/**`, gitignore
> `/.external/bcquality/`.
>
> **`.external/README.md` — a tracked explainer, shipped with the seed (decided 2026-09-25).** It
> replaces the rejected `.gitkeep` and does the same job better: because it is tracked, the wrapper
> **exists in every fresh clone**, so T-32's yellow "missing root" entry never appears — and unlike an
> empty marker file, someone who opens it learns something. Contents:
>
> - **What this is**: `bcquality/` is not a directory but a **directory junction / symlink** onto the
>   BCQuality clone, which lives outside the repository.
> - **Why**: the clone location is a property of the workstation, not of the repo — the junction keeps
>   the repo-side path constant while the target varies per developer.
> - **Who creates it**: the Aproda VS Code extension, on *Apply Toolkit* / *Install-Update BCQuality*.
> - **How to create it by hand**, if the extension is unavailable:
>   `New-Item -ItemType Junction -Path .external\bcquality -Target <clone>` (Windows, no elevation) /
>   `ln -s <clone> .external/bcquality` (macOS, Linux).
> - **Removal**: delete the **link only** — `(Get-Item .external\bcquality -Force).Delete()` or
>   `cmd /c rmdir`. **Never `Remove-Item -Recurse`**, which can delete through the link into the real
>   clone.
> - **Exclude rule**: `search.exclude` + `files.watcherExclude` on `bcquality/**` — **never**
>   `files.exclude`, which would hide the folder outright and endanger the read path the agents use.
> - Pointer to `docs/bcquality.md` for the full picture.
>
> Why not `BCQuality/.bcquality` (the tested layout): it sorts into the repo root between `Base` and
> `Test` and reads like a third AL app — exactly the confusion `install.sh` warns about; the repetition
> looks like a typo in logs and config; and the dot sat on the inner level, where it hides the
> implementation detail instead of the thing that clutters the repo root. `.external` states the
> semantics (consumed from outside, not compiled) and groups with `.github` / `.vscode`.

The tracked `aldc.code-workspace` carries a **constant** path identical for every user:

```jsonc
{ "name": "BCQuality (Aproda ALDC)", "path": ".external" }
```

`.external/bcquality` is not a directory but an extension-managed **directory junction** (Windows
`mklink /J`, no elevation) / symlink (macOS, Linux) onto the resolved clone. The indirection moves from
the path string into the filesystem.

> **Correction history — the claim was overstated, then re-validated.** On 2026-09-24 the "`home` becomes
> a constant" argument was withdrawn, on the explicit ground that *"it only holds if the junction is
> **mandatory**"* while §1.6 then made S1 **opt-in, default off**. **T-29 (2026-09-25) removed that
> premise**: the seed now mounts `.external/` for everyone, so the junction sits at the same repo-relative
> path in every project that has one. The constant is therefore correct again — not because the argument
> changed, but because the condition it depended on did.
>
> **Decided (option B, 2026-09-25): `home: ".external/bcquality"`.** Correct by construction wherever a
> junction exists; wrong only where none has been created yet — and exactly there the resolver's rungs
> 1–4 answer first, so the miss is inert. It stays a *static default* in framing (T-17): the authority
> remains `resolvedHome`, re-resolved and probe-verified per call. **Consequence: T-17 is fixed as a
> class, not as one value** — B-5 cannot recur through a layout difference, only through a missing
> junction, which fails loudly.

| Risk | Handling |
|---|---|
| The link sits **inside** the repo — precisely what `install.sh` warns about (example `.al` files polluting the build) | Repo root, not an app folder (the AL compiler only walks `app.json` folders); plus `.gitignore`, `files.watcherExclude`, `search.exclude` |
| Repo-walking tools follow the link (aproda-sync, aldc-validate, Dredd's "changed files", `git status`) | Each must be checked for an exclude — **this is the real cost**, not creating the link |
| `aldc.code-workspace` + `workspace.seed.jsonc` change | Upstream in-place edit → new D-2 merge point |
| Junction creation may be restricted by GPO/AppLocker | Verify on an Aproda workstation before committing to it |

S1 and the `#bcquality` tool are **not mutually exclusive**: tool as the agent channel, S1 as an optional
human-convenience mount. S1 is strictly better than the withdrawn gitignore variant — it makes every
repo-scoped value constant instead of hiding it in an untracked file.

> **Tested with an agent-executable protocol** in a real consuming project (general Copilot agent mode,
> not the Conductor). Protocol and raw result files were **deleted after the run (2026-09-24)** — they
> were single-use scaffolding. The criterion IDs below (A1…H3, D1…D6, G1…G4, J1…J4) refer to that
> protocol; the findings they produced are carried here and in §4 / §5, which are now the only record.

#### Test result — executed 2026-09-24 in `straub-medical-ag-base`

Five rounds, two of them after a full VS Code reload. The raw result files were deleted with the
protocol; everything load-bearing is summarised below and in the T-29–T-32 entries of §5.

**Verdict: S1 is technically viable.** Every rejection-tier criterion passed:

| Cleared | Evidence |
|---|---|
| Junction without elevation, no GPO/AppLocker block | A1, A2, A4 |
| Git does not descend; `git clean -ndx` lists nothing inside | B2, B3, B4 |
| **Bonus safety net**: the clone carries its own `.git`, so git treats `.bcquality` as a **nested-repo boundary** and refuses to descend even without the `.gitignore` rule | B4 (surprise finding) |
| AL build isolated — 246 `.al` files in the clone, 0 diagnostics under `.bcquality` | C1, C2, C3 |
| PowerShell `Get-ChildItem -Recurse` does not follow the junction (PS 7.6) | G1 |
| Dredd's scope source (`git diff --name-only main...`) unaffected | G4 |
| **The clone survived byte-for-byte** — 489 files before and after | **H2**, H1, H3 |

**The one failure — root-caused in round 3, fixed in round 4.** **D4: a workspace root cannot exclude
itself.** `search.exclude` globs are evaluated *relative to each mounted folder root*, so as long as the
clone **is** the root, `.bcquality/**` looks for a nested `.bcquality` inside it and never fires — for
`grep_search`, the Search view and Quick Open alike. Mounted clone content then appears in workspace
searches: a search for an AL symbol returns BCQuality's **example `.al` files** as if they were project
code. That is an analysis-quality risk, not a cosmetic one.

> **Correction to the round-2 reading.** Round 2 concluded *"`grep_search` does not honour
> `search.exclude` at all"*. That was wrong: the setting was never violated — the **glob simply could
> not match**. Same observable outcome, different mechanism — and only the corrected mechanism pointed
> at the fix.

**The fix (round 4, user's proposal): never mount the junction itself — mount a wrapper.**

```
BCQuality/                 ← mounted as the workspace root      (as tested)
  └─ .bcquality/          ← the junction; a genuine SUBFOLDER, so ".bcquality/**" resolves
```

→ shipped as `.external/` + `bcquality/` per the decision at the top of §1.5 — same relationship,
better names.

With `search.exclude` / `files.watcherExclude` on the junction's glob relative to that root, the content
disappears from search and Quick Open — verified twice, independently: by the user via Ctrl+P (`do.md`
no longer findable) and by the agent via `grep_search` (0 hits under the mount, remaining hits all
legitimate elsewhere). Shipped, that is `bcquality/**` and gitignore `/.external/bcquality/`.

**Two consequences worth holding on to:**

1. **This is a design constraint, not a defect of S1** — but it *is* an unfixed defect of the layout
   shipping today: `../BCQuality-Aproda` is likewise its own root and therefore cannot be excluded
   without the same restructuring. The junction variant is in fact *easier* to fix, because the wrapper
   lives inside the repo and can be created by the extension; for the sibling layout the wrapper would
   have to be created outside the repo. Recorded as **B-9** / **T-29**.
2. **Settled: the exclude strips false positives, not capability (round 5).** Measured after the fix
   and a reload, the **entire consumption chain** resolves through the junction — `skills/entry.md`
   (routing contract) → `skills/read.md` → `skills/do.md` → a real knowledge file
   (`microsoft/knowledge/performance/use-setloadfields-for-partial-records.md`, frontmatter + body).
   At the same time `grep_search` finds **zero** hits under the mount, and the workspace's
   `files.exclude` block was verified to contain only unrelated AL patterns (`**/*.dep.app`,
   `**/rad.json`). This is exactly what the agent contracts predict — `dredd` and
   `al-review-subagent` consume BCQuality **by explicit path only** and never search it; dredd's own
   prose states the root *"never surfaces unless you read its path explicitly"*. **The mount is
   therefore strictly better with the exclude than without it.**

> **Standing constraint for the implementation:** use `search.exclude` + `files.watcherExclude` —
> **never `files.exclude`**. The first two hide the clone from search and the watcher; the last would
> hide it outright and endanger the read path the agents depend on. Making the exclusion "more
> thorough" is exactly how this breaks.

Either way the §1.3 recommendation is unaffected: the `#bcquality` tool design mounts nothing, so clone
content never enters the search scope and the wrapper question does not arise.

**Still open** (environment gaps, not junction behaviour): **C4** had no pre-junction diagnostics
baseline (protocol gap, since fixed). **G2/G3 were closed on 2026-09-24** — `aldc-validate` and
`aproda-sync -WhatIf` produce **identical output with and without the junction** (T-31), which removes
what was the largest remaining technical risk for S1.

**Method note.** Both runs executed the whole protocol in **one agent session**, which was correct: every
unverified item failed on environment or VS Code window state (reload, active-editor binding, missing
npm dependency, missing parameter) — none on context. A subagent shares the same window and would have
changed nothing, while splitting T1 from T9 would have risked leaving the junction orphaned.

---

### 1.6 Behaviour when BCQuality is *not* used

"Not used" is not one state but four, and each needs its own rule. Getting this wrong is how an optional
layer becomes a mandatory one by accident.

| Case | Rule |
|---|---|
| **1. `enabled: false`** — deliberately off | **No resolve, no junction, no wrapper.** The extension must not build infrastructure for a feature the project switched off. The reconcile is **bidirectional**: flipping to `false` **removes** an existing junction, it does not merely stop creating one |
| **2. `auto`, no clone installed** — the default for a new project | Resolver returns `verified: false` → no junction → no workspace root → agents probe, get *absent*, fall back to native A–G, `fallback.neverBlock: true`. Unchanged from today's contract. **The trap: never materialise a root that points at nothing.** "Verify first, then act" applies here too |
| **3. Aproda extension not installed** | The weak point — and it exists **today**, independent of T-22: per **B-10** the documented *"direct root-level access"* fallback cannot succeed in a consuming project. Addressed by the dual path below **plus T-33**, which makes the third rung actually reachable |
| **4. Upstream / non-Aproda consumers** | Untouched — the whole construction is fork-local; upstream keeps the sibling mount |

#### Dual path — decided 2026-09-24

Switching the agent prose to `#bcquality` alone would **increase the extension dependency at a point
where something still works today**: without the extension there would be no route to BCQuality at all,
whereas the multi-root mount currently functions without it.

**Decision: dual path.** The agent prose keeps a direct path read as an explicit, documented fallback
for when `#bcquality` is unavailable. It costs some prose complexity in the same four agent files, and
it avoids reproducing exactly the failure class E-006 criticises everywhere else — a documented
capability that is not in effect.

Three rungs, each reachable once **T-33** lands:
`#bcquality` → `#aldcConfiguration` → `read_file <toolkitRoot>/aldc.yaml`.

> Rejected alternative: *tool-only*. Simpler, but then `copilot-instructions.md` would have to declare
> the extension a **prerequisite** for BCQuality instead of promising a fallback that does not exist.

#### Two further rules for the implementation

- **S1 is the shipped layout (decided 2026-09-25, supersedes "opt-in, default off").** The seed mounts
  `.external/`, and the wrapper plus its `README.md` are tracked, so they exist in every clone. **The
  wrapper is not the junction:** §1.6 case 1 still holds — with `enabled: false` no junction is created
  and an existing one is removed. A `.external/` containing only its README is **inert documentation**,
  not an active mount. That is the price of the swap, and it is small: one folder, one file worth
  reading.
- **The extension is the automation, not the precondition.** Because the README documents the manual
  `New-Item -ItemType Junction` / `ln -s` route, the direct-read fallback (dual path, rung 3) stays
  reachable without the extension — it just stops being automatic. §1.6's dual path therefore survives
  the swap intact.
- **The `.gitignore` entry belongs inside the `Aproda ALDC Tool BEGIN/END` block**, not loose below it —
  otherwise it will not survive the next sync.

---

## 2. Ownership — BCQuality is Upstream, not Aproda

Verified via `git log --diff-filter=A`:

```
fa37cf7  2026-06-05  Javier Armesto Gonzalez
feat: upstream FORGE innovations into ALDC (port + docs + distribution + plugin) (#51)
```

Present in the pinned ALDC base (`4f3371f`): `tools/bcquality/**`, `.github/workflows/bcquality-evidence.yaml`,
`docs/bcquality.md`. **Aproda's contribution is the fork URL**, not the mechanism.

Consequence: fixes here are candidates for an **upstream PR** (Block 5), not fork-local edits — with the
exception of the per-user path, which is an Aproda requirement and may well be one too.

---

## 3. How it is supposed to work

| Piece | Role | Runs where |
|---|---|---|
| `tools/bcquality/install.{sh,ps1}` | Clone BCQuality next to the repo | Human, once per workstation |
| BCQuality clone (`skills/entry.md`) | Citable knowledge; agents route through the entry point | Agent, at review time |
| `al-review-subagent`, `dredd` | Produce findings with `references[].path` | Agent |
| `al-conductor` | Persists the reports, reports the CI verdict | Agent |
| `validate_evidence.py` | Resolves **every** citation against the clone | CI |
| `.github/workflows/bcquality-evidence.yaml` | Runs the validator on PR | GitHub-hosted runner |

The division of labour is the whole point: **agents assert, CI falsifies.** That is exactly what
`copilot-instructions.md` calls the difference between *declarative* and *falsifiable* evidence.

Two artifact families feed the validator — both count as "audit checking" in this chapter:

- **Review evidence** — `.github/plans/**/*-review-phase-*.json` (superset) and `*-bcquality-*.json` (derived view)
- **Audit evidence** — `.github/audits/**/*-audit-*.json`, written by `@dredd`

---

## 4. Findings

*B-1 … B-11 were observed 2026-09-24 by inspection, before any change. The three sections after them
carry what the implementation and the two end-to-end runs added. Status is per row.*

| # | Finding | Evidence |
|---|---|---|
| **B-1** | `neverTouchExceptions → workflows/bcquality-evidence.yaml` is **inert**. `.github/workflows/…` reverse-maps to `$null` before the exception is consulted, so the CI has never shipped to any project | = E-006 **F-16**; verified absent in `straub-medical-ag-base` |
| **B-2** | The manifest comment calls it *"our BCQuality evidence workflow"* — **false ownership**, it is Upstream's | `aproda-sync.json` lines 134–135 vs. §2 above |
| **B-3** | `aldc.yaml` lines 64–66 declare `validator:` and `ciWorkflow:` as machine-readable config. **Both files are absent in a consuming project**, and `aldc.yaml` ships as `dualVariant` — so the shipped config points at nothing | Reference project: `tools/bcquality/validate_evidence.py` and `.github/workflows/bcquality-evidence.yaml` both FEHLT |
| **B-4** | `copilot-instructions.md` line 127 promises CI validation *"A hallucinated citation or a drifted pin fails the check"*. In a project the whole apparatus is missing ⇒ the evidence chain is **purely declarative there**, i.e. precisely what that section rules out | Same measurement as B-3 |
| **B-5** | `external.bcquality.home: "../../BCQuality-Aproda"` resolves from the fork root to `C:\_EphemeralWorkspace\BCQuality-Aproda` — **does not exist**. The clone is one level up, at `…\Florian Köll\BCQuality-Aproda`. The validator therefore skips citation resolution **although a clone is present**. **Corroborated in a live project (T-22 test, P3):** `straub-medical-ag-base` carried **three different paths for the same clone** before the experiment began — `.code-workspace` → `../../../BCQuality-Aproda`, `aldc.yaml` → `../../BCQuality-Aproda`, `$BCQUALITY_HOME` → `c:\_EphemeralWorkspace\BCQuality-Aproda`, while the real clone sat at `…\Florian Köll\BCQuality-Aproda`. **None of the three was correct.** This is the strongest evidence for the T-22 requirement | = **T-17**; reproduced live: run without `--bcquality-root` reported *"clone not available"*, run with the real path found it |
| **B-6** | **The validator reports PASSED when it has verified nothing.** Three independent paths to false green: no clone, wrong clone path (B-5), no evidence files. All three exited `0` | 3 local runs, each `BCQuality evidence validation PASSED (0 citation(s) across 0 file(s))`, exit 0 |
| **B-7** | **Check 1 (pin coherence) no longer exists.** The docstring claims a three-way cross-check (`aldc.yaml` + both install scripts, *"a drift in any of them fails the build"*); the code states `# there is no hardcoded pin to cross-check` and only prints a note. `copilot-instructions.md` still advertises the three-way check | `validate_evidence.py` docstring lines 6–10 vs. code line 101; `copilot-instructions.md` line 127 |
| **B-8** | `.github/audits/` does **not exist** in the fork (0 files), although it is a declared trigger path and Dredd's output location. Audit evidence has therefore never been exercised end-to-end | Directory listing during the Block-1 session |
| **B-9** | **A workspace root cannot exclude itself — and the BCQuality mount is exactly that.** `search.exclude` / `files.watcherExclude` globs are evaluated **relative to each mounted folder root**. When the clone *is* the root, `.bcquality/**` looks for a *nested* `.bcquality` inside it and can structurally never match — confirmed for `grep_search`, the Search view **and** Quick Open, after a real reload. Consequence: the clone's 246 example `.al` files surface in symbol searches as if they were project code. **Fixed in round 4:** nest the junction one level down (`BCQuality/.bcquality`) and mount the **wrapping folder** as the root — then the glob resolves and the content disappears from search and Quick Open (verified independently by the user via Ctrl+P and by the agent via `grep_search`). **The defect applies to the `../BCQuality-Aproda` sibling root shipping today**, which is likewise its own root and therefore unexcludable in its current layout | T-22 test, D4 (rounds 2–4); root-caused round 3, fixed round 4 |
| **B-10** | **The documented "direct root-level access" fallback cannot be executed in a consuming project.** `aldc.yaml` sits at the repo root and is **deliberately gitignored** (`/aldc.yaml`, inside the `Aproda ALDC Tool BEGIN/END` block — as is the whole synced layer). Three access paths, three different outcomes: **(a)** `read_file aldc.yaml` fails on **workspace scope** — the repo root is not a workspace folder (roots are `.github`, the apps, BCQuality); **(b)** `file_search **/aldc.yaml` fails on the **ignore rule** — exactly the false negative run 2 produced; **(c)** a **terminal** read would work (neither scope nor ignore applies), **but neither BCQuality consumer has a terminal**: `dredd` = `[changes, read/readFile, read/problems, search, edit, todo, …]`, `al-review-subagent` = `[read/problems, read/readFile, search, …]` — no `runCommands` in either, and both are deliberately cut read-only-near. So the agents' precondition promises a backstop that **has no way to succeed**, and `#aldcConfiguration` is load-bearing rather than convenient. **Fix: T-33** — move `aldc.yaml` to `toolkitRoot` | Confirmed by the user 2026-09-24 (`aldc.yaml` + `.gitignore` of `straub-medical-ag-base`); tool allowlists read from the agent frontmatter; same failure class as B-3/B-4/B-7 |
| **B-11** | **The Aproda extension's BCQuality install diverges from the declared config contract — three ways.** `installOrUpdateBcquality` is the *only* Aproda-sanctioned install path (`install.{sh,ps1}` are upstream and unused here), yet: **(a)** the repo URL is **hardcoded** (`https://github.com/Aproda-AG/BCQuality-Aproda.git`) while `aldc.yaml` claims *"the install scripts read `url` / `ref` / `pinnedCommit` from here — this file is the single source of truth"*; **(b)** **`pinnedCommit` is ignored** — it does `clone` + `pull --ff-only` on the default branch, never `checkout <pin>`, so a pin set for reproducible evidence is **silently not honoured** (the most serious of the three: the pin is the reproducibility of the whole evidence chain); **(c)** it never reconciles `aldc.yaml → home` — the direct cause of B-5 surviving an otherwise correct setup. Same failure class as B-3/B-4/B-7: a declared capability that is not in effect | `src/bcquality/install.ts` vs `aldc.yaml → external.bcquality` comment; read 2026-09-25 |

### Findings from the end-to-end run 1 (2026-09-25) — the wrong order, measured

*Run 1 deliberately delivered the layer to a real project while the **old** extension was still
installed. It found one release blocker that has nothing to do with the extension at all — and it
corrected two predictions, one of them mine.*

| # | Finding | Status |
|---|---|---|
| **B-18** | **The first Block-4 pull crashes — via `Start-Pull.ps1`, deterministically.** `Start-Pull.ps1` loads **the project's own** `Sync-AprodaLayer.ps1`, so pull *n* runs the **pre-Block-4** engine (old manifest, old regex, no `sidePaths`) — which then overwrites `Initialize-AprodaProject.ps1` with the **new** one. The new Init immediately reads `templates/external-readme.seed.md`, which the old engine never copied → unhandled `ReadAllText` exception in Init 4; Init 5 never runs. The project is left half-migrated: `.external/` empty, both BCQuality roots in the workspace file, `BCQUALITY_HOME` orphaned, root `aldc.yaml` rewritten in place, no `.bak`. **Proof it is not random** (the test agent called it "non-deterministic"): pull 1 logged `Dual-variant: aldc.yaml  (toolkitRoot -> project value)` — the *old* code's format — while pulls 2/3 logged `aldc.yaml -> .github/aldc.yaml`; 130 vs. 135 files matches the old regex exactly. **Apply Toolkit is immune**: `Bootstrap-AprodaProject.ps1` runs the **fork's** engine, so no version skew. My own "this hits every project" was therefore also too broad — it hits the `Start-Pull` path | ✅ **fixed**: both new Init reads are guarded and skip with a message instead of throwing |
| **B-19** | **An existing project never receives a refreshed `Start-Pull.ps1`.** `Bootstrap-AprodaProject.ps1` leaves an existing starter untouched *by design* ("it may carry user edits") and the extension never passes `-Force`. So **any** future fix to the pull entry point is structurally undeliverable to existing projects — same "stale forever" class as T-39, at a spot that looks like a template and therefore feels safe to change | ⏳ **deferred to Block 5 (T-40)** — low impact: ~98% of updates run through Apply Toolkit |
| **B-20** | **A degraded audit is indistinguishable from a full one.** With BCQuality absent, Dredd's reply carried the verdict and findings as usual; the `not-applicable` outcome was only discoverable inside `audit.bcquality` / `notes` of the persisted JSON. Dredd **flagged this against itself, unprompted, during the run.** Consequence: with Block 4 shipped you could not tell from a report whether it had worked | ✅ **fixed**: the report contract now requires the BCQuality outcome next to the verdict in **every** report, with an explicit line for the not-consulted case |
| — | Confirmed again, live: the workspace file's `BCQUALITY_HOME` pointed at `c:\_EphemeralWorkspace\BCQuality-Aproda` — **wrong path**, while the clone sits one level up. Fresh evidence for **B-5**, now removed by the migration | — |
| — | The migration left the retired sibling root's `search.exclude` / `files.watcherExclude` globs behind | ✅ fixed in the same pass |
| **B-21** | **The `.bak` never held the original — and one writer never made one at all.** Run 1's repeat (after the B-18 guards) measured the backup as byte-*different* from the pre-Block-4 baseline. Root cause is older and wider than the migration: **`Initialize-AprodaProject.ps1`'s Init 3 rewrites the workspace file through `ConvertTo-Json` — stripping comments and formatting — with no backup whatsoever**, and has done so since long before Block 4. The migration's `.bak` covered only the *second* rewrite, so it captured already-modified content. The promise "your original is saved" was therefore never actually kept | ✅ **fixed**: the backup is taken before the **first** rewrite, by whichever writer gets there first, still write-once. Verified in a fixture: `.bak` byte-identical to the pristine file, comment intact, migration output unchanged |
| **B-22** | **`Start-Pull.ps1` executed the project's own sync engine** — the direct cause of B-18's version skew, and the reason the first Block-4 adoption needs two pulls even after the guards. `Start-Pull.ps1.template` now takes the engine **and** the manifest from the **fork**, mirroring `Bootstrap-AprodaProject.ps1`; `Initialize-AprodaProject.ps1` deliberately stays project-side, because it anchors its `.git`-walk at its own location. **This does not help the current transition** — an existing project never receives a refreshed starter (**T-40**), so no code change can reach the projects adopting Block 4 now. **Accepted by the maintainer, 2026-09-25, with no mitigation:** ~98% of updates — today every developer except the maintainer — run through *Apply Toolkit*, which was never affected because it executes the fork's engine. The one exposed person knows | ✅ fixed for future projects; residual risk **accepted** |

### Findings from the end-to-end run 2 (2026-09-25/26) — the production order, measured

*Run 2 delivered the layer in the intended order (Apply Toolkit, `localFork`) into a real project.
**26 of 30 acceptance points passed cleanly**: the migration was flawless, the `.bak` was byte-identical
to the baseline (**B-21** holds), the `#bcquality` containment boundary held against an adversarial
probe, a real Dredd citation resolved to a genuine knowledge file, and the disable/re-enable cycle
behaved. The four defects below are what the run bought.*

| # | Finding | Status |
|---|---|---|
| **B-23** | **`Install / Update BCQuality` created a duplicate clone and leaked it machine-wide.** The command did not reuse the already-verified clone; it fell through to `<devRoot>/BCQuality-Aproda`, **silently `git clone`d a second copy**, junctioned `.external/bcquality` to *that*, and wrote Global `aprodaAldc.bcquality.path` at it — which then outranks every rung in **every** Aproda project on the machine (confirmed to propagate into `@Dredd`: `resolvedFrom: "setting"`). **The reported diagnosis — "read and write path disagree on precedence" — was wrong**; both use the same `resolveBcqualityPath()`. The real cause is **timing**: `initializeProject()` resolved BCQuality only *after* `runBootstrap`, and the migration removes the mounted BCQuality root and the workspace-level `BCQUALITY_HOME` **before** the replacement junction exists. In that window no rung verifies, so an existing clone is indistinguishable from a first-time install. A stale `devRoot` (missing one path segment) supplied the plausible-but-wrong target | ✅ **fixed**: the resolution is captured **before** the bootstrap; a clone into a not-yet-existing target now requires a confirmation naming the path. Deliberately **not** changed: the Global `bcquality.path` write after a successful install (maintainer decision) |
| **B-24** | **Apply Toolkit appeared to hang on the `localFork` path.** Two causes, one of them not the suspected one: (a) `Sync-AprodaLayer.ps1`'s noise skip was anchored at the top level, so a nested `.git`/`node_modules` was walked — **24 018 files enumerated instead of 606**; (b) the actual hang: three advisory `showWarningMessage` calls in `ensureLocalFork()` were `await`ed, blocking the entire command until dismissed. Measured git time was 0.2 s, which is what ruled (a) out as *the* cause | ✅ **fixed**: depth-aware skip (dry-run 4.9 s) and the three advisories changed to fire-and-forget. **Not swept blanket-wise** — the other 17 `await`ed message sites include ones that legitimately gate control flow (`ensureGitRepository`, `confirmGitHubChanges`) |
| **B-25** | **`BCQUALITY_HOME` was written for all three platforms and read from the wrong scope.** `reconcileBcquality` set `terminal.integrated.env.{windows,linux,osx}` regardless of the host, leaving two entries that can never be correct, and it read the existing value via `get()` — which collapses Workspace over Global — instead of `inspect()?.globalValue` | ✅ **fixed**: only the current platform's key is written, stale entries on the other two are pruned, and the scope is read explicitly |
| **B-26** | **The repository quick-pick could silently select the BCQuality clone.** A reviewer **reproduced** it: a forged `entryPoint` in the clone's own `aldc.yaml` made it look like the project repo. Identity must never be taken from a candidate's own config | ✅ **fixed**: `isBcqualityClone()` probes only the fixed default marker path; a single-root or all-clones situation errors out instead of guessing, and the prompt appears only when genuinely ambiguous |
| **B-27** | **Run 2's first attempt was confounded and had to be discarded.** `source.mode` was still `"managed"`, so the *released* layer was applied rather than the fork under test. My omission — the briefing never listed `source.mode` as a precondition | ✅ **fixed**: a hard Phase-0 check in the briefing |

> **Why a 30-point acceptance list missed B-23.** The junction criteria asserted that a junction
> **exists**, not what it **points at** — so a junction to the wrong clone passed. This is the same
> weakness as the "declared capability not in effect" class the whole subsystem keeps producing, moved
> into the test plan itself. Every criterion touching a resolved path must assert **identity**, not
> existence. The regression tests written for the fix follow that rule.

> **A defect the fix itself introduced, caught by re-review.** The first repair threaded a **single**
> pre-bootstrap repository snapshot into both the pre- *and* post-bootstrap call sites. But the bootstrap
> is what *writes* `aldc.yaml` — so on a first init the fallback would never have seen the declared
> `home` and reconciliation would have been skipped silently. Found by an independent second review
> round, reproduced as a failing test, then fixed by re-probing in the fallback branch.

### Findings from the end-to-end runs 3 and 4 (2026-09-26)

*Run 3 re-tested the run-2 blockers on Straub, deliberately keeping the wrong `devRoot` so the fix had to
hold under the original conditions. Run 4 was the **first-init** path on `HEKS Base` — a repository that
had never seen ALDC, whose repo root is not a workspace folder and whose `*.code-workspace` is not even
strict JSON. B-23 … B-26 held in both. What the runs bought instead is the row below it.*

| # | Finding | Status |
|---|---|---|
| **B-28** | **The resolver discovers the junction it manages itself, and links it to itself.** Rung 2 probes, for every mounted workspace folder, both the folder and `<folder>/bcquality` — and after the migration `.external` **is** a mounted folder. So `.external/bcquality` verifies and is returned as the canonical root. Three consequences, all observed live: **(a)** `Install / Update BCQuality` reported *"BCQuality is ready at `<project>\.external\bcquality`"* and wrote that **project-scoped** path into the **Global** `aprodaAldc.bcquality.path` and `BCQUALITY_HOME` — so every other Aproda project on the machine now resolves BCQuality through *this* project's junction (the same class as B-23, one step worse); **(b)** on the next reconcile the setting rung returns that same path, and `createBcqualityLink(linkPath, target)` is called with `target === linkPath` — there is no self-reference guard — producing a **junction pointing at itself** and `ELOOP: too many symbolic links encountered`; **(c)** the resolver still reports `verified: true` for it, because a probe only asks whether *something* answers at the path. **Structural, not incidental:** the resolver treats its own managed artifact as a discovery source | ✅ **fixed**: a verified candidate is canonicalised (`realpath`) before it becomes `root`, so the canonical root is always the real clone; `createBcqualityLink` refuses a target that resolves to the link itself. **Review follow-up:** `reconcileBcquality` wrote `BCQUALITY_HOME` from the *caller's* earlier resolution while linking from its own fresh one — two independently timed answers to the same question, which is what produced the two mutually inconsistent Global settings observed. Both now come from the fresh, canonical resolution. **Verified empirically, not assumed:** `fs.lstat().isSymbolicLink()` returns `true` for a Windows **junction** (checked with a real `mklink /J`) — the whole fix rests on that || **B-29** | **Every migrated project reports "ALDC is not installed" forever.** `VersionService.readInstalled()` reads `path.join(repoRoot, "aldc.yaml")` with **no two-rung lookup** — T-33 moved the file to `.github/aldc.yaml` and this reader was missed. The startup check therefore offers to *initialize* a project that is fully initialized, on every window. Same failure class as **B-10** and **B-12**: a reader still assuming the repo root, silently wrong rather than loudly broken. Observed in run 4 | ✅ **fixed**: both readers now use the exported two-rung `resolveConfigurationPath()`. **A second instance was found by the fix, not by the run:** `repositoryInitialization.ts` carried the same hardcoded check, so the startup prompt and the version service could disagree about what counts as installed |
| **B-30** | **`Validate Installation` cannot run on Windows** — `spawn npm ENOENT`, while `npm` works fine in a terminal. `run("npm", …)` spawns without `shell`, and on Windows `npm` is a `.cmd` shim that `child_process.spawn` will not resolve without `shell: true` (or an explicit `npm.cmd`). A first init is the cleanest input this check will ever get, and it is exactly where it fails | ❌ **first fix was wrong**, ✅ fixed on the second attempt. `npm.cmd` alone turned `ENOENT` into **`EINVAL`** — measured again in runs 3.2 and 4.2. Real cause, reproduced on this machine (`node -e`, Node 24.21): since Node 18.20.2 (CVE-2024-27980) `spawn` **refuses a `.cmd`/`.bat` without a shell at all**, so the extension was fixed and still broken. Now one constant command string under `shell: true`, with an **empty** argument array — the shell is opt-in per call, and nothing user-influenced is ever concatenated into it. **I diagnosed this from the error name without reproducing it; the run caught me** |
| **B-31** | **The post-bootstrap BCQuality step logs nothing.** Run 4 (D18) found the *outcome* correct — junction created, pointing at the real clone — but the log goes silent after `Bootstrap: done.`. The run instructions had flagged silence explicitly as a failure shape, because **that is what the broken first repair of B-23 looked like**: correct-looking absence, indistinguishable from a step that never ran | ✅ **fixed** — and the first attempt was wrong in the same way: it logged *"reconciling"* from the caller, while `reconcileBcquality` could still return silently (opt-out, unverified, no-op link). Caught by review; the function now reports its own outcome and the caller claims nothing |

| **B-32** | **`Install / Update BCQuality` silently discarded a user-set path.** Run 3.2, Phase 4: `aprodaAldc.bcquality.path` was set to a non-existent path; the command resolved through another rung (the `.external/bcquality` junction), succeeded, and then **overwrote the setting back** to the resolved value — no confirmation, no warning, no log line. Because the setting is **Global**, a deliberate override (a second clone, another project) is discarded without a trace, and the misconfiguration is hidden behind a success message | ✅ **fixed**: a configured path that differs from what was actually used is **left alone**; the mismatch is logged and surfaced as a warning instead |
| **B-33** | **The negative test could not fire its own dialog — a test-design defect, not a product one.** Phase 4 of run 3 can only reach the confirmation branch when **nothing** resolves. After Phases 1–2 the junction always resolves, whatever garbage `bcquality.path` holds, so the command never falls into "offer to clone". Run 3.2 correctly reported **NOT-REACHED**, not FAIL — the lesson from the previous round held | ✅ **fixed in the run instructions**: Phase 4 removes the junction first (link only, per briefing rule 5), or the criterion is acknowledged as reachable only on a project that never had a working mount |

| **B-34** | **The B-28 self-reference guard was inverted, and it shipped.** Measured on a live Apply Toolkit: `ERROR: Refusing to link BCQuality to itself: …\BCQuality-Aproda resolves to …\HEKS Base\.external\bcquality.` The guard resolved **both** sides through `realpath` — but a **correct** junction resolves to exactly its target, so `realpath(target) === realpath(linkPath)` is true for every healthy link. The guard therefore condemned the normal case and refused to maintain the junction. A link's identity is its **canonical parent plus its own name**, never `realpath(linkPath)`. **A second defect kept it hidden until production:** the early return compared `path.resolve(currentTarget)` with `path.resolve(target)` **case-sensitively**, while `readlink` reports the drive letter as stored (`C:\`) and a resolved candidate can carry it lower-cased (`c:\`) — so the healthy path never short-circuited and execution reached the broken guard. **Why the test passed anyway:** it only counted `"Linked BCQuality"` messages, so a refusal looked identical to a no-op. Existence, not identity — the same weakness as B-23's acceptance list, this time in a test I had reviewed and accepted | ✅ **fixed**: guard compares against the canonical *parent* + basename; all path comparisons are case-insensitive on Windows; the test now asserts **no error was logged**, that the already-correct branch was taken, and that the link still reaches its target, plus a case-only-difference case |
| **B-35** | **Every subprocess ran with TLS certificate verification disabled.** Surfaced by the first successful `Validate Installation` (B-30 finally closed, HEKS, first init): `Warning: Setting the NODE_TLS_REJECT_UNAUTHORIZED environment variable to '0' makes TLS connections and HTTPS requests insecure`. **Not ours, but ours to contain:** VS Code's extension host sets that variable and verifies certificates itself — protection that covers only the host. Every Node child inherits the variable and stops checking altogether, so `npm install` fetched the validator's dependencies over an **unverified** connection, silently overriding npm's own `strict-ssl=true`. Verified it comes from neither the toolkit (no occurrence in the repository), nor User/Machine environment, nor npm config. `git` is unaffected — it uses its own TLS stack | ✅ **fixed**: the variable is stripped from the environment handed to child processes; everything else is inherited unchanged and the host's own environment is untouched. **Residual risk, stated plainly:** behind a TLS-intercepting proxy `npm install` may now fail where it previously "succeeded". That is the correct trade — a loud failure beats a silent unverified download |
| **B-36** | **The validator's baseline in a consuming project is six warnings that can never be fixed there** — so warning number seven would go unnoticed. Measured on the first init of `HEKS Base`: `skills/index.md` links `skill-aproda-aldc-release` (declared `neverTouch`, deliberately never shipped), and `readme.aproda.md`'s inventory names five more fork-only paths (`CHANGELOG.aproda.md`, `onboarding.aproda.md`, `tools/aproda-sync/fleet/`, `tools/aproda-vscode-extension/`, `skills/skill-aproda-aldc-release/`). **Deliberately rated *minor*, and an earlier framing of mine was too harsh:** the index row already says *"fork maintainer only"* in its own column, so this is a dangling link, not an unkept promise — unlike B-3/B-4. **The damage is the lost signal, not the warnings**: a check with permanent noise cannot serve as a gate, which is the same mechanism that kept **B-35** invisible for as long as `Validate Installation` never ran | ✅ **fixed on the second attempt** — the first one was worse than the problem. The validator now derives fork-only status from the sync manifest (`includeGlobs`/`includeFiles`/`inPlaceEdits` vs. `neverTouch`), applied **only** in the project layout, so the fork keeps full coverage. **The subagent's first version shipped a broken glob translation** (`**/` demanded a slash) that classified **every root-level `*.aproda.*` file as fork-only** — `readme.aproda.md`, `decisions.aproda.md`, `site-profile.aproda.md` included. Had one of those genuinely vanished from a project, the validator would have stayed silent: it traded six false warnings for blindness on the layer's most important files. **Its own coverage test passed because the fake path it used contained a slash.** It also reported "0 warnings" after **hand-copying two files into the test project** — a result no user could reproduce |
| **B-37** | **The syncer's glob translation has the identical defect — and it is why two layer files never shipped.** `Convert-GlobToRegex` renders `**/*.aproda.*` as `^.*/[^/]*\.aproda\.[^/]*$`, which **requires a slash**, so no root-level path can ever match. Consequence: `aproda-sync.json`'s central promise (*"as new .aproda.* artifacts are added — no manifest edit"*) is **false for root-level files** — they ship only if listed explicitly. `readme.aproda.md`, `decisions.aproda.md` and `site-profile.aproda.md` are listed and ship; `CHANGELOG.aproda.md` and `onboarding.aproda.md` are not, and silently never arrived. The manifest's own comment on line 39 claims that omission was fixed on 2026-09-24 (F-14) — **it was not**. Found only because the validator's baseline was being driven to zero; the two warnings were real all along and had been dismissed as "a stale pull". Third time in this subsystem that a regex quietly discards files (**B-12**, **B-36**, now this) | ✅ **fixed**: `**/` spans zero or more directories in both the syncer and the validator. Dry-run against the reference project: **135 → 137** resolved files, the delta being exactly those two |

> **The logging contradiction (D18 / D35) is resolved — logging was never broken.** A clean repeat
> (project closed and reopened, then Apply Toolkit, channel read with nothing in between) produced the
> full log: the git preflight, the applied fork path, both sync passes, every `Init:` and `Init 5:`
> line, `Bootstrap: done.` — and then the BCQuality step's own line. Run 4.2's silence was an artifact
> of reading the channel after a window reload / extension-host restart, which recreates it. **Worth
> keeping as a method note:** a report stating "confirmed not a log-level artifact" had still not ruled
> out the channel being recreated, and absence of evidence was read as evidence of absence. That same
> clean repeat is what surfaced **B-34** — which no amount of blind fixing would have found.

> **A reported blocker that was not one — and why it looked like one.** Run 3's report marked **C14
> FAIL** ("no modal confirmation appeared") and derived a blocker from it: a clone into a deliberately
> bogus path, plus the junction repointed at it. The confirmation **did** appear, named the path
> correctly, and was **confirmed by the operator** — the run's instruction was to cancel with Esc. The
> B-23 gate works. The agent's command-execution harness cannot observe modal dialogs, and it inferred a
> product defect from its own blindness. **Third wrong diagnosis in this subsystem to survive into a
> written report**, after "non-deterministic resolution" (B-18) and "only the last rung reads `enabled`"
> — in all three the *symptom* was real and the *mechanism* invented. Treat an agent-run verdict on a UI
> criterion as `NOT-REACHED` unless a human saw the dialog. **Residual, genuine:** after a confirmed
> clone an already-verified junction is repointed with no second confirmation.


> **A verdict the run got wrong:** it marked **A14** FAIL ("the three catalog files are in no part of the
> sync manifest"). They are not in `aproda-sync.json` — they are in `aldc.yaml → required.catalog`. Its own
> diagnostic log shows all three present after the pull, and pulls 2/3 list them. **T-36 works.**

### Findings discovered *during* Block 4 (2026-09-25)

*None of these were predicted by the plan. They were found by implementing it — several by a review
adjudicating why something the plan assumed to work did not.*

| # | Finding | Status |
|---|---|---|
| **B-12** | **The syncer silently dropped every annotated catalog entry.** `Sync-AprodaLayer.ps1`'s framework-file scrape anchored its regex on the closing quote (`"\s*$`), so any `required`/`optional`/`catalog` line carrying a trailing `# comment` never matched. That is exactly the three most recently registered catalog files — `agents/index.md` (T-11), `docs/copilot-reference.md` (T-14/F-11) and `docs/bcquality.md` (T-29) — so **T-11's and T-14's "now it ships" claims were never in effect**, the same failure class those items were opened to fix. Measured against this repo's `aldc.yaml`: **73 → 76** matched entries after the fix, the delta being exactly those three lines | ✅ **fixed in Block 4** |
| **B-13** | **A catalog change needs two pulls, and the routine path only does one.** The framework scrape read the **destination's** `aldc.yaml`, which is itself rewritten (`dualVariant`) at the *end* of the same run — so a newly registered entry could only resolve on the next pull. `Bootstrap-AprodaProject.ps1` compensated with an explicit settle pull; **`Start-Pull.ps1.template`, the routine per-project update path, did not.** Reproduced: a dry-run pull into the reference project resolved the layer with none of the three newly registered catalog files present. Second, unnoticed half of the same defect: a **removed** entry was kept alive indefinitely by the stale destination list | ✅ **fixed in Block 4 (T-36)** — the scrape now reads the source |
| **B-14** | **A second distribution channel still writes `aldc.yaml` to the repo root.** `scripts/install.js` (the upstream `npx aldc install` path) writes `path.join(projectDir, 'aldc.yaml')` unconditionally, contradicting T-33's rule — even though it rewrites `toolkitRoot` to a non-`"."` value a few lines earlier. T-33's cost list named the *other* install scripts (`tools/bcquality/install.{sh,ps1}`) as deliberately out of scope; this one it simply did not enumerate. Aproda does not use this channel, and fixing it opens a new D-2 merge point on an Upstream file | ❌ **formally excluded (T-37, 2026-09-25)** |
| **B-15** | `tools/aproda-sync/templates/workspace.seed.jsonc` is **not registered in the manifest and never ships**; `Initialize-AprodaProject.ps1`'s fallback writer builds the same JSON inline, and its `Write-Host` hint pointed a developer at a path that does not exist in a consuming project. The hint now says "fork-side only, not shipped" | ✅ claim corrected; the seed staying fork-only is deliberate |
| **B-16** | **`Initialize-AprodaProject.ps1` anchors its `.git`-walk at the *script's own location*** (`$env:APRODA_SYNC_SCRIPTDIR` / `$PSScriptRoot`), not the working directory. Correct in production — the synced copy always sits inside its own project — but a real trap when testing: during Block 4 a subagent ran it against a scratch directory while the env var still pointed at the fork and **initialized the fork itself** (caught and reverted the same minute). Any test must copy the script **and** `templates/` into the scratch tree | ⏳ documented; a guard is worth considering |
| **B-17** | The agent mirrors under `docs/agents/**` and `packages/foundation/agents/**` still carry the pre-T-28 unexecutable *"fall back to direct root-level access"* prose. `packages/foundation/**` is **out of E-006's scope per the maintainer** (it is the *upstream* extension's packaging source, which Aproda does not ship); `docs/agents/**` is a fork-maintained mkdocs mirror. Confirmed: neither tree ships to a consuming project | ❌ **formally excluded (T-38, 2026-09-25)** |

### Cross-cutting

B-3, B-4, B-7 and **B-11** are the same failure mode as E-006's T-9/T-19: **a documented or declared
capability that is not in effect.** Four instances inside one subsystem, three of them in shipped
artifacts, and B-11 on the *only* install path Aproda actually uses. Whatever Block 4 decides, the
honesty of the shipped documentation has to be restored — that part is independent of whether the CI
ever ships.

---

## 5. Open items

> **Block 4 implemented 2026-09-25.** **T-17, T-22, T-24, T-25, T-28, T-29, T-33, T-35** are all
> **✅ implemented** (uncommitted, in the working tree), each with an independent review pass and a
> D-7 register row. The rows below are kept as the design record; read them for *why*, not for status.
> Still genuinely open: **T-36, T-37, T-38** (new, below) and the Block-5 set **T-21, T-23, T-26,
> T-27, T-34**.

| # | Item | Depends on |
|---|---|---|
| **T-36** | ✅ **Decided and implemented 2026-09-25.** **B-13** — the framework scrape now reads the **source's** `aldc.yaml` instead of the destination's. Two defects in one: a newly registered entry needed a second pull, *and* a **removed** entry was kept alive forever by the stale destination list. The destination copy is a verbatim copy of the source (only `toolkitRoot` diverges), so it never held independent information — reading it merely simulated an autonomy the consuming project does not have. Measured: resolved set **132 → 135**, delta exactly `agents/index.md` + `docs/copilot-reference.md` + `docs/bcquality.md`, nothing dropped. **Rejected:** adding a settle pull to `Start-Pull.ps1.template` — doubles every routine pull to mask an ordering bug, and the generated `Start-Pull.ps1` is git-ignored and machine-local, so it would never reach existing workstations. **Follow-on:** `Bootstrap-AprodaProject.ps1`'s settle pull is now redundant; left in place (idempotent) pending a deliberate removal | — |
| **T-39** | ⏸️ **Deferred to Block 5, 2026-09-25 (maintainer).** **Overlay → sync: carry removals through.** Today `Sync-AprodaLayer.ps1` is explicitly *"OVERLAY: copy only; never delete anything at the destination"*, so a file dropped from the layer lingers in every project — and a stale agent or catalog file is still **loaded by Copilot**, i.e. invisible drift, exactly E-006's subject. **Nothing breaks today**, which is why it waits. **Do not implement it as a list-diff:** (a) it would abandon a deliberate design invariant (D-18 territory, not a bug fix); (b) the whole synced layer is **git-ignored**, so a wrong deletion has no `git restore` safety net *and* will not come back on the next pull; (c) "absent from the list" ≠ "ours" — the ignore block enumerates skills individually precisely so projects may add their own alongside; (d) the config list is the wrong source anyway — it does not know the files delivered via `includeGlobs` or skill-folder expansion. **The right shape is a manifest of what was actually delivered**, written at pull time and diffed on the next run | T-36 |
| **T-37** | **B-14 — `scripts/install.js` writes `aldc.yaml` to the repo root**, contradicting T-33. Upstream-owned; Aproda does not use that channel. ❌ **Decided 2026-09-25: formally excluded.** Fixing it in the fork would open a new D-2 merge point on an Upstream file for a distribution channel Aproda never runs — the same merge-economics argument E-006 already used to route the v1.1 drift to an upstream PR instead of a fork sweep. Recorded here so the exclusion is a decision, not an oversight; it may be folded into the Block-6 upstream PR (**T-15**) if that is opened | T-33 |
| **T-38** | **B-17 — agent mirrors carry pre-T-28 prose.** ❌ **Decided 2026-09-25: formally excluded.** `packages/foundation/**` is already out of E-006's scope per the maintainer (it is the *upstream* extension's packaging source, which Aproda does not ship), and `docs/agents/**` is a documentation mirror of it. Neither reaches a consuming project — verified against the resolved file list of a dry-run pull — so no customer sees the superseded prose. The mirrors lag **by design**; that is the recorded position, not a backlog item | T-28 |
| **T-40** | ⏸️ **New from the end-to-end run 1, deferred to Block 5 as *minor*, 2026-09-25 (maintainer).** **B-19 — an existing project never receives a refreshed `Start-Pull.ps1`.** `Bootstrap-AprodaProject.ps1` deliberately leaves an existing starter untouched (*"it may carry user edits"*) and the extension never passes `-Force`, so every future change to the pull entry point is structurally undeliverable to existing projects. **Low impact, and that is why it waits:** ~98% of updates run through *Apply Toolkit*, which never uses `Start-Pull.ps1` and executes the **fork's** engine instead. The only project-specific value the generated starter carries is the injected fork path, which the bootstrap rewrites on every run anyway — so a controlled refresh is probably safe, but that is a decision about the idempotency guarantee, not a fix. Same "stale forever" class as **T-39**; look at both together | — |

*Design record for the Block-4 items, kept for the reasoning. Numbering continues E-006's. The
"nothing is implemented" framing these rows were written under held until 2026-09-25 — see the note
above; T-30/T-31/T-32 remain closed as measurements rather than changes.*

| # | Item | Depends on |
|---|---|---|
| **T-17** | ✅ **Decided 2026-09-25, revised the same day after T-29.** `external.bcquality.home` becomes the **constant `.external/bcquality`** — correct by construction for the shipped layout (§1.5), since T-29 makes the wrapper mount the default rather than an opt-in. It keeps its **static default** framing: the authority is the resolver's `resolvedHome` (T-22), re-resolved and probe-verified on every call. **Deliverables:** (a) set the value; (b) rewrite the comment — static fallback **and how to check the real value**: user setting `aprodaAldc.bcquality.path`, or the `Show BCQuality Status` command; (c) the extension sets `BCQUALITY_HOME` (Global) so the script side is covered without writing to the repo. **Fork value deliberately not fixed** — no productive work happens there. **Rejected**: extension writes `home` (redundant — the file is gitignored, so the value never leaves the machine that already knows better; and the fleet bootstrap would silently reset it) | T-22, T-29 |
| **T-34** | ⏸️ **Deferred to Block 5 (BCQuality part 2), 2026-09-25.** **B-11** — make the extension's BCQuality install honour `aldc.yaml`: read `url` / `ref` / `pinnedCommit` instead of the hardcoded URL, and **check out the pin** after clone/pull. **(b) is the priority** when it is picked up — without it a configured pin is inert and the evidence chain is not reproducible on the Aproda path. **(c)** is already answered by T-17's decision (no `home` write-back), so only (a) and (b) remain. **Deferred because the defect is latent, not active:** `pinnedCommit` is empty today, so nothing mis-resolves; pinning + update semantics are their own piece of work | T-17 |
| **T-21** | ⏸️ **Deferred to Block 5, 2026-09-25** — the CI runs nowhere today (B-1), so the decision changes nothing until something consumes it; T-24 records the current truth either way. Decide B-1: make the declared exception work (`workflows/**` in `dotGithub` + `tools/bcquality/**`), or declare the CI fork-only and drop it from `neverTouchExceptions`. **Precondition resolved 2026-09-24:** `Aproda-AG/BCQuality-Aproda` is **public** — unauthenticated `git ls-remote` succeeded (`refs/heads/main` → `d97329b`, exit 0). A GitHub runner can therefore clone it, so option (a) is technically open; the decision is now purely about scope, not feasibility | — |
| **T-22** | **Per-user clone path** (§1) — the actual requirement. **Designed 2026-09-24 (§1.3): resolver + `#bcquality` LM tool + user-scoped setting, with the path read kept as a documented fallback (dual path, §1.6).** Plan-B junction sidecar (§1.5) **tested 2026-09-24: viable**, one confirmed limitation (B-9). Implementation open | — |
| **T-28** | **B-10** — the ignore is *deliberate* (D-18: fork is the source of truth, the consumer copy is a cache), so the fix is **not** to track the file. Fix the **prose**: the agents' *"fall back to direct root-level access"* clause is unexecutable in a consuming project. **Resolved in principle by the §1.6 dual-path decision** — state the extension requirement, and give a fallback that actually works. Touches the same four agent files as T-22's tool change — do both in one pass | — |
| **T-29** | ✅ **Decided 2026-09-25.** **B-9** — a workspace root cannot exclude itself. **The seed swaps the root, it does not drop it:** `workspace.seed.jsonc` mounts **`.external/`** instead of `../BCQuality-Aproda`, with `search.exclude` + `files.watcherExclude` on `bcquality/**`. The wrapper folder and its `README.md` are **tracked and ship with the toolkit**; the junction inside is created by the extension (*Apply Toolkit* / *Install-Update BCQuality*) or by hand per the README. Aproda-owned file — **no upstream edit, no new D-2 merge point**. **Two writers, not one:** `Initialize-AprodaProject.ps1` carries its own fallback workspace writer — updating only the seed would leave projects created through that path on the old layout, the same mechanism as F-14. Rationale: every Aproda workstation runs the extension, so the main path matters more than fallback noise; the sibling layout is unexcludable by construction and would otherwise pollute every workspace search with the clone's 246 example `.al` files | — |
| **T-30** | ✅ **Closed 2026-09-24 (round 5).** The excluded mount stays fully readable: the **complete four-link chain** resolves through the junction — `skills/entry.md` (routing) → `skills/read.md` → `skills/do.md` → a real knowledge file (`microsoft/knowledge/performance/use-setloadfields-for-partial-records.md`, frontmatter + body) — while `grep_search` returns zero hits under the mount and `files.exclude` was verified not to target BCQuality. Consistent with the agent contracts: consumption is **read-by-path only**, never search. **Carry forward as an implementation constraint:** `search.exclude` + `files.watcherExclude` only, **never `files.exclude`** | T-29 |
| **T-31** | ✅ **Closed 2026-09-24 — both PASS, by control comparison.** `aproda-sync -WhatIf`: 130 resolved files, **identical with and without the junction**, zero `BCQuality` mentions — the feared "489 clone files as foreign changes" did not materialise. `aldc-validate`: identical verdict (`COMPLIANT`, 4 warnings, 503/507 naming), `Compare-Object` byte-for-byte equal. Measured **with/without** rather than in a single run, which is what makes it evidence. `js-yaml` removed again, repo clean. **Residual: the result rests on Windows junction semantics** — PowerShell and Node do not follow reparse points here; a POSIX `ln -s` behaves differently for tree-walkers → re-measure before shipping S1 on macOS/Linux (T8) | T-29 |
| **T-32** | ✅ **Closed 2026-09-24 — cosmetic, not a risk.** Measured by hand (no extension code required, since the mitigation does not exist yet): **J1** a missing mount renders as a yellow, non-expandable Explorer entry and **does not rewrite the workspace file** (`git diff` clean); **J2** recreating the junction in a live window fills the root **immediately, no reload**; **J3** reads work instantly, even before any Explorer refresh; **J4** the full cycle leaves zero trace on tracked files. **Consequence — the implementation gets simpler:** no *Reload Window* prompt and no activation-timing logic are needed; creating the junction whenever the resolver verifies a clone is sufficient. **`BCQuality/.gitkeep` decided against 2026-09-24** — a tracked file bought only the absence of a yellow Explorer entry. **Superseded 2026-09-25**: `.external/README.md` (§1.5) does the same anchoring *and* explains the junction, so the wrapper is tracked after all — for a file worth finding, not an empty marker | T-29 |
| **T-33** | **Move `aldc.yaml` to `toolkitRoot`** — the structural fix for **B-10** (user's proposal, 2026-09-24). **Rule: `aldc.yaml` lives at `toolkitRoot`.** In the fork `toolkitRoot: "."`, so the file already sits there; in a consumer `toolkitRoot: ".github"`, so the file belongs at `.github/aldc.yaml` — today's consumer layout is the one violating the rule, not the proposal. `.github` **is** a workspace root, so `read_file .github/aldc.yaml` works: no extension, no terminal, unaffected by the ignore rule. Everything else of the toolkit already lives there, and the file is gitignored anyway — it is treated as part of the synced layer but stored outside it. **Supersedes the generated-projection idea** (`.github/aldc.config.json`): no extra artifact, no drift, no freshness check. **Cost:** `resolveAldcRepository()` hardcodes `path.join(repositoryRoot, "aldc.yaml")` (Aproda, small); `aldc-validate` takes `--config` (trivial); the syncer must write the new location and migrate the `.gitignore` block; the upstream readers that assume repo root (`validate_evidence.py`, `install.{sh,ps1}`, the claude-plugin hook) are **not shipped to consumers** (B-3) — an upstream PR can add the same two-rung lookup. **Implement as a two-rung lookup** (`<toolkitRoot>/aldc.yaml` → `<repoRoot>/aldc.yaml`) so the migration is non-breaking. The prose changes land in the same four agent files as T-22/T-28 — **one pass** | T-22, T-28 |
| **T-24** | Restore honesty in the shipped docs (B-3, B-4, B-7): `aldc.yaml` pointers, `copilot-instructions.md` line 127, the script docstring — **plus B-11(a)**: the `external.bcquality` comment claims the install scripts read `url`/`ref`/`pinnedCommit` from there, which is false for the only install path Aproda uses. The *fix* is deferred to Block 5 (T-34); the *claim* must not stay false meanwhile | — |
| **T-23** | ⏸️ **Deferred to Block 5, 2026-09-25** — the validator is **not shipped to consumers** (B-3), so "fail loudly" has nothing to fail in yet; paired with T-26. Make the validator **fail loudly instead of passing vacuously** (B-6): distinguish "verified N citations" from "verified nothing". Prerequisite for any gate | — |
| **T-25** | Correct the false-ownership comment (B-2). One line, no dependencies | — |
| **T-35** | **Upgrade path from the old layout — the closing step of Block 4.** Projects already running the toolkit carry the pre-Block-4 state and must be migrated, not just re-seeded: sibling BCQuality root in `*.code-workspace` → `.external/`; `aldc.yaml` moved from the repo root to `toolkitRoot` **with the `/aldc.yaml` line in the `Aproda ALDC Tool BEGIN/END` ignore block rewritten**; `BCQUALITY_HOME` removed from the workspace file (it moves to a Global setting, T-17); `.external/` + `README.md` created and the junction established. **Design it only once T-33 / T-22 / T-28 / T-29 are implemented** — a migration can only be specified against a target shape that exists. Requirements: **idempotent**, a no-op on an already-migrated project, and safe on a dirty working tree (the workspace file is tracked) | T-22, T-28, T-29, T-33 |
| **T-26** | ⏸️ **Deferred to Block 5, 2026-09-25** — depends on T-23; a gate over a vacuously-passing validator would be gate theatre. **Agent-executed gate in `al-pr-prepare`** — run the validator at the Completion Gate so hallucinated citations are caught *before* the PR, independent of whether the CI ever ships. Feasibility confirmed: Python 3.14.7, stdlib only, clean exit codes, runs over our umlaut path; the gate already has the pattern (*"HARD GATE — a verification step, not a checklist to narrate"*, line 173). **Must evaluate the `notes`, not the exit code** (B-6), and must be labelled a self-check: the agent that produced the citations is not an independent verifier | T-17, T-23 |
| **T-27** | ⏸️ **Deferred to Block 5, 2026-09-25** — exploratory, nothing depends on it, and it needs a real Dredd run to produce input. Exercise audit evidence end-to-end (B-8) — does a Dredd run actually produce a validatable `*-audit-*.json`? | T-17 |

---

## 6. What held until Block 4 — and what holds now

*The three statements below described the state until 2026-09-25. Block 4 changed the first two.*

- ~~**Nothing is changed.**~~ → Block 4 implemented T-17/T-22/T-24/T-25/T-28/T-29/T-33/T-35. The paths
  work, the shipped docs are honest, the migration exists. **Uncommitted.**
- BCQuality-backed reviews keep working where a clone is reachable — now via the resolver and the
  `#bcquality` tool rather than a hand-maintained mount. **Only the verification layer is still broken,
  not the knowledge layer.**
- **Unchanged, and still true:** any BCQuality citation produced in a project is **unverified**. The
  validator still passes vacuously (**B-6**) and does not ship (**B-3**); the CI does not run in a
  consuming project (**B-1/B-4**). Treat "BCQuality Evidence" blocks in phase reports as claims, not as
  proof — until Block 5 (**T-21, T-23, T-26**) says otherwise.

**Measured end-to-end, 2026-09-25/26.** Two runs against a real project: run 1 in the deliberately
wrong order, run 2 in the production order. Run 2 scored **26/30** clean. Everything the runs found
(**B-18 … B-27**) is fixed except the two rows explicitly marked deferred (**T-40**) or accepted
(**B-22** residual risk). What is *not* measured: macOS/Linux — every junction result rests on Windows
reparse-point semantics (see T-31).
