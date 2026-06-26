# aproda-sync — the Aproda ALDC layer syncer

This folder is the **machinery that keeps the Aproda fork layer and a consuming
project in sync**. It is the `.aproda.` customization layer's transport: an
allowlist-driven OVERLAY syncer plus thin launchers. This README is the entry
point for a human or an AI agent that needs to understand or extend it.

> **Authority**: the *why* behind every design choice lives in
> [`../../decisions.aproda.md`](../../decisions.aproda.md) (decisions **D-18 / D-19 / D-20**).
> This README is the *map*; that file is the *law*. When they disagree, the
> decisions file wins — and you should update this README.
>
> **Guardrail (D-16)**: every file here is part of the `.aproda.` layer. Editing
> it is a deliberate fork-bound change — see
> [`../../instructions/aproda-aldc-steward.aproda.instructions.md`](../../instructions/aproda-aldc-steward.aproda.instructions.md).
> Changes must flow back to the fork, not silently diverge in one project.

## Quick start

**Fork**: <https://github.com/Aproda-AG/ALDC-AL-Development-Collection-Aproda>

### Onboard a new project (run from the aproda-aldc fork clone)

1. **Clone the fork** once (your machine-local source of the layer + the engine):
   ```powershell
   git clone https://github.com/Aproda-AG/ALDC-AL-Development-Collection-Aproda
   ```
2. **Commit everything in the target repo first** — safety net. The bootstrap
   overlays files into it; a clean working tree makes the change reviewable (and
   trivially revertible) via `git status` / `git diff`.
3. In the **fork clone**, open `tools/aproda-sync/Start-InitNewProject.ps1` →
   **PowerShell: Run Selection** → pick the target repo folder.
   → pull + framework settle-pull + init run automatically, and a filled
   `Start-Pull.ps1` is left in the target. **Ready.**

### Recurring: pull the latest layer into a project

Open `Start-Pull.ps1` in the project (`.github/tools/aproda-sync/`) →
**Run Selection**. Only `APRODA_FORK_PATH` is filled in; the scriptdir
self-locates. (See *Two ways `Start-Pull.ps1` comes to exist* below.)

## Mental model in one picture

```
   FORK (ALDC-AL-Development-Collection-Aproda)          PROJECT (this repo)
   primitives at REPO ROOT:                              everything under .github/:
     agents/ skills/ instructions/ tools/ ...    <───►     .github/agents/ skills/ ...
                                                  pull
                                                  push
```

- **Fork layout**: toolkit primitives sit at the **repo root**.
- **Project layout**: the same primitives live under **`.github/`**.
- The syncer **translates between the two layouts** (the `layouts` block in
  `aproda-sync.json`). A few files stay under `.github/` on **both** sides
  (`dotGithub` exceptions). `aldc.yaml` is a **dual-variant** file: copied
  verbatim except its `toolkitRoot` line, rewritten per side.

## The files

| File | Role |
|------|------|
| `Sync-AprodaLayer.ps1` | **The engine.** Resolves the allowlist, translates layouts, copies files OVERLAY-only (never deletes). `-Direction pull\|push`, `-ForkPath` (mandatory), `-ProjectRoot` (optional, `.git`-walk default), `-WhatIf`. |
| `aproda-sync.json` | **The allowlist (D-18).** Default = SAFE: a path not matched here is invisible in **both** directions. Holds `layouts`, `dualVariant`, `includeGlobs`, `includeFiles`, `inPlaceEdits`, `includeAldcFramework`, `neverTouch`. |
| `Initialize-AprodaProject.ps1` | **One-time project bootstrap.** Seeds `plans/memory.md`, maintains the `.gitignore` Aproda block, ensures the workspace roots + `chat.useCustomizationsInParentRepositories`. Idempotent. Anchors via `.git`-walk. |
| `Bootstrap-AprodaProject.ps1` | **Zero-seed onboarding** of a FRESH repo from a fork clone: pull → settle-pull (framework) → init → generate a filled `Start-Pull.ps1`. `-ProjectRoot` (mandatory), `-ForkPath` (optional), `-Force`, `-WhatIf`. |
| `Start-Pull.ps1.template` | Recurring **pull** launcher. Self-locates `APRODA_SYNC_SCRIPTDIR`; only `APRODA_FORK_PATH` is filled. Copy → `Start-Pull.ps1` (git-ignored). |
| `Start-Push.ps1.template` | Recurring **push** launcher (same self-location; one path to fill). Copy → `Start-Push.ps1` (git-ignored). |
| `Start-InitNewProject.ps1` | **Fork-only**, committed (not a template, not synced). Pick a target folder → bootstrap it. Self-locates the fork from its own path. |

## How to run it (SRP-safe)

The estate's Software Restriction Policy blocks **path-based** PS execution, so
everything is loaded **content-based**:

```powershell
$src = Get-Content "$env:APRODA_SYNC_SCRIPTDIR\Sync-AprodaLayer.ps1" -Raw
& ([ScriptBlock]::Create($src)) -Direction pull -ForkPath $env:APRODA_FORK_PATH
```

In practice you don't write that — you use a launcher:

| You want to… | Run |
|--------------|-----|
| Pull the layer into this project | open `Start-Pull.ps1` → **PowerShell: Run Selection** |
| Push local layer edits to the fork | open `Start-Push.ps1` → **Run Selection** |
| Onboard a brand-new repo | open `Start-InitNewProject.ps1` **in the fork** → **Run Selection** → pick the target |

> **Always dry-run first** when unsure: the engine supports `-WhatIf` (shows the
> resolved file set and writes nothing).

## Two ways `Start-Pull.ps1` comes to exist

1. **Generated** by the bootstrap during onboarding — the fork path is injected
   (correct-by-construction), the scriptdir is left empty (self-located).
   Zero-config.
2. **Hand-copied** from `Start-Pull.ps1.template` — fill the **one** fork path;
   the scriptdir self-locates.

## Extending it — the rules that bite

- **Add a new layer file?** If it carries the `.aproda.` infix or lives under
  `skills/skill-aproda-*/`, it is picked up **automatically** (D-4). Otherwise add
  it to `includeFiles` in `aproda-sync.json`.
- **Self-location** (`$PSScriptRoot` → `$psEditor` fallback) only works for files
  that physically sit in `.../tools/aproda-sync`. A separate repo (the fork) can
  **never** be self-located — that path stays manual.
- **`else { @() }` is a trap** in PowerShell: the `@()` branch is enumerated to
  *nothing* and the variable becomes `$null`. Wrap the whole conditional:
  `$x = @(if (cond) { ... })`.
- **Encoding-safe anchoring (D-19)**: resolve the repo root by walking up to
  `.git` with pure path ops — never `git rev-parse` (it mangles umlauts under a
  non-UTF-8 console).
- **OVERLAY-only**: the syncer never deletes. Removing a file from the layer
  means deleting it on both sides by hand.
- **Never touch**: `plans/**`, `documentation/**` (except its `README.md`),
  `workflows/**` (except `bcquality-evidence.yaml`), `*.code-workspace`,
  AL-Go system files. The allowlist already protects these; `neverTouch` is a
  redundant tripwire.

## Glossary

- **Layer** — the `.aproda.` fork customization on top of ALDC Core.
- **Overlay** — copy-on-top, additive, never destructive.
- **Dual-variant** — same physical path, content diverges on a few rewritten lines.
- **Settle-pull** — the bootstrap's second pull, once `aldc.yaml` exists, that
  brings the ALDC framework a fresh repo's first pull cannot.
