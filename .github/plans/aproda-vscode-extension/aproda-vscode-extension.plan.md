# Aproda ALDC — VS Code Extension · Implementation Plan

| | |
|---|---|
| **Requirement** | `aproda-vscode-extension` |
| **Type** | Aproda layer tooling (net-new, fork-only — never synced into projects) |
| **Status** | Implementation complete; interactive and release acceptance pending |
| **Target** | `tools/aproda-vscode-extension/` |
| **Extension ID** | `aprodaag.aproda-aldc` — publisher `aprodaag`, name `aproda-aldc`, display name *Aproda ALDC* |
| **Language** | TypeScript. UI strings English only. |
| **Distribution** | Internal VSIX attached to GitHub releases of the fork. No marketplace. |
| **Layer version at planning time** | `1.2.0_aproda.9` |

## Phase 0 evidence

| Spike | Result | Decision / follow-up |
|---|---|---|
| S1 — validator | `node tools/aldc-validate/index.js --config aldc.yaml` passed with 0 warnings after its declared `npm install --omit=dev` prerequisite. It correctly handles `toolkitRoot: "."`, the Aproda artefacts and the intentional Copilot entrypoint trim. | Keep the validator as an explicit extension command. The extension must bootstrap `tools/aldc-validate/node_modules` with `npm install --omit=dev --no-package-lock` when missing. No vendoring required. |
| S2 — private remote | `GIT_TERMINAL_PROMPT=0 git ls-remote --heads --tags` succeeded headlessly. The remote exposes branch `aproda` and legacy layer tags `v1.2.0_aproda.2`, `v1.2.0_aproda.6`, and `v1.2.0_aproda.7`; no `aproda-layer/*` tags exist. | Resolve release versions from `v<layerVersion>` tags. Introduce and enforce this convention for all future layer releases rather than introducing a second tag namespace. The current `aproda` head (`1.2.0_aproda.9`) is not tagged and must receive `v1.2.0_aproda.9` before release-channel checks ship. |
| S3 — PowerShell bridge | A Node `spawnSync` invocation of `pwsh -NoProfile -NonInteractive -Command` completed the SRP-safe content-loaded `Bootstrap-AprodaProject.ps1 -WhatIf` flow with `EXIT=0`. The log resolved 115 layer files and confirmed `INIT skipped`. | Use the specified content-loading bridge. Preserve the tested outer-shell-safe quoting strategy when building the TypeScript implementation. |

The probes created no tracked dependency changes; only this plan directory is untracked at the time of the probe.

---

## 1. Goal

Replace the manual PowerShell onboarding entry point with a guided VS Code UI, without duplicating the sync engine.

The extension is an **orchestrator**. It owns UX, environment discovery, layer-source lifecycle and version checks. The existing PowerShell engine in `tools/aproda-sync/` remains the single implementation of the allowlist overlay (D-18) and is invoked as-is.

### In scope

1. Initialize / update **the currently open repository** with the Aproda ALDC layer.
2. Startup version check, restricted to AL projects.
3. Central BCQuality-Aproda knowledge-base install / update.
4. Getting Started pointer to the fork's onboarding document.
5. Installation validation via `aldc-validate`.
6. One-time machine setup wizard plus an environment doctor.

### Out of scope (explicit non-goals)

- Initializing repositories that are not currently open. External seeding stays with `Start-InitNewProject.ps1`.
- Batch operations across multiple repositories.
- Reimplementing `Sync-AprodaLayer.ps1` logic in TypeScript.
- Editing base ALDC upstream behaviour.
- Remote / WSL / Codespaces hosts.

---

## 2. Locked decisions

| # | Decision | Rationale |
|---|---|---|
| L1 | Location `tools/aproda-vscode-extension/` | Mirrors `tools/aproda-sync/`; keeps repo root clean |
| L2 | TypeScript, not JavaScript | Type safety across the PS bridge and JSON manipulation |
| L3 | Layer source = **managed cache clone** owned by the extension; local fork only as opt-in for layer maintainers | Removes per-machine path config and silent drift |
| L4 | Installed version read from `<repoRoot>/aldc.yaml` → `aproda.layerVersion`; available version from git tag `v<version>` | Two different questions, two appropriate sources; no third source of truth |
| L5 | Target repository = current workspace git root only | Confirmed scope reduction; removes the riskiest command |
| L6 | BCQuality strategy `central` is the default, path `<devRoot>/BCQuality-Aproda` | Single clone per developer |
| L7 | `I:` is a mapped network drive and must be used regardless | Infrastructure constraint — mitigations in §9, not avoidance |
| L8 | Workspace BCQuality root path is **silently corrected on every open** to match local reality (option c) | Avoids a process rule; accepted cost is a local diff in a versioned file |
| L9 | Extension sets `BCQUALITY_HOME` in the workspace settings | Only pull-proof override; `aldc.yaml` is a `dualVariant` sync file and cannot hold project-specific values |
| L10 | Fork repository is private | First clone must run in a visible terminal so the credential manager can prompt |
| L11 | Phase 0 spikes precede all implementation | Three unknowns drive design in phases 2, 4 and 8 |

---

## 3. Architecture

```
VS Code Extension Host  (TypeScript)
  ├── environment discovery   git root · app.json · devRoot
  ├── layer source            managed cache clone in globalStorage
  ├── version service         aldc.yaml  vs  git ls-remote --tags
  ├── workspace maintenance   *.code-workspace roots + settings
  └── PowerShell bridge  ──────────────┐
                                       │  SRP-safe, content-loaded
                                       ▼
          tools/aproda-sync/Bootstrap-AprodaProject.ps1
              ├── Sync-AprodaLayer.ps1     (pull, settle pull)
              ├── Initialize-AprodaProject.ps1
              └── Start-Pull.ps1 materialization
```

The extension never calls `Start-InitNewProject.ps1`. That script is interactive (`Out-GridView`, `Read-Host`) and would block in a spawned process. The extension assumes its *responsibility* (locate target, validate, provide fork) in native UI and invokes `Bootstrap-AprodaProject.ps1` directly with explicit parameters. `Start-InitNewProject.ps1` stays unchanged as the non-extension path.

---

## 4. Repository layout

```
tools/aproda-vscode-extension/
├── package.json                 # extension manifest, independent of repo-root package.json
├── tsconfig.json
├── .vscodeignore
├── .eslintrc.json
├── README.md
├── CHANGELOG.md
├── media/                       # icon, walkthrough assets
├── src/
│   ├── extension.ts             # activate / deactivate, command registration
│   ├── config.ts                # settings access, defaults, constants
│   ├── log.ts                   # OutputChannel "Aproda ALDC"
│   ├── env/
│   │   ├── gitRoot.ts           # upward .git search (pure path ops)
│   │   ├── detectAl.ts          # app.json probe
│   │   └── devRoot.ts           # devRoot derivation and validation
│   ├── source/
│   │   ├── layerSource.ts       # managed cache vs local fork, resolve(ref) -> path
│   │   └── gitClient.ts         # git spawn, terminal fallback for auth
│   ├── version/
│   │   ├── installed.ts         # aldc.yaml -> aproda.layerVersion
│   │   ├── available.ts         # git ls-remote --tags, cached
│   │   └── compare.ts           # <core>_aproda.<n> comparator
│   ├── ps/
│   │   └── bridge.ts            # SRP-safe pwsh invocation
│   ├── workspace/
│   │   ├── workspaceFile.ts     # jsonc-parser based surgical edits
│   │   └── bcqualityRoot.ts     # root path fixer + BCQUALITY_HOME + watcherExclude
│   ├── bcquality/
│   │   └── install.ts           # clone / pull of the central knowledge base
│   ├── setup/
│   │   ├── wizard.ts
│   │   └── doctor.ts
│   ├── startup/
│   │   └── check.ts             # throttled version check + notifications
│   ├── agent/
│   │   └── readAldcConfigurationTool.ts # registers #aldcConfiguration
│   └── commands/                # one file per command
└── dist/                        # build output, gitignored
```

### Runtime dependencies

| Package | Purpose |
|---|---|
| `yaml` | Read `aproda.layerVersion` from `aldc.yaml` |

Dev dependencies: `typescript`, `@types/vscode`, `@types/node`, `@vscode/vsce`.

### Protection rules — must not leak into consumer projects

1. **No `.aproda.` infix in any file name inside this folder.** `includeGlobs: ["**/*.aproda.*"]` in `aproda-sync.json` would otherwise pick the file up as a layer artefact.
2. Add tripwire to `aproda-sync.json` → `neverTouch`: `"tools/aproda-vscode-extension/**"`.
3. `.gitignore` additions: `tools/aproda-vscode-extension/node_modules/`, `tools/aproda-vscode-extension/dist/`, `tools/aproda-vscode-extension/*.vsix`.
4. Verify `scripts/check-conformance.js` and the root `package.json` `files` array do not trip over the nested manifest.

---

## 5. Commands

| Command ID | Title (English) | Enablement |
|---|---|---|
| `aprodaAldc.initProject` | Aproda ALDC: Apply Layer to Project | AL project open |
| `aprodaAldc.previewChanges` | Aproda ALDC: Preview Update Changes | AL project open |
| `aprodaAldc.installBcQuality` | Aproda ALDC: Install / Update BCQuality Knowledge Base | always |
| `aprodaAldc.setup` | Aproda ALDC: Configure Settings | always |
| `aprodaAldc.gettingStarted` | Aproda ALDC: Open Getting Started | always |
| `aprodaAldc.validate` | Aproda ALDC: Validate Installation | layer installed |
| `aprodaAldc.doctor` | Aproda ALDC: Environment Diagnostics | always |
| `aprodaAldc.repairCache` | Aproda ALDC: (Re)build Layer Cache | always |
| `aprodaAldc.showLog` | Aproda ALDC: Show Log | always |
| `aprodaAldc.checkForUpdates` | Aproda ALDC: Check for Updates | AL project open |
| `aprodaAldc.resetData` | Aproda ALDC: Reset Layer Cache and Settings | always |

Enablement is driven by two context keys set during activation: `aprodaAldc.isAlProject`, `aprodaAldc.isLayerInstalled`.

### Activation events

```jsonc
"activationEvents": [
  "workspaceContains:**/app.json",
  "workspaceContains:**/aldc.yaml",
  "onCommand:aprodaAldc.setup",
  "onCommand:aprodaAldc.doctor",
  "onCommand:aprodaAldc.gettingStarted",
  "onCommand:aprodaAldc.installBcQuality"
]
```

Deliberately not `["*"]`. `workspaceContains` is the cheapest correct implementation of the "AL projects only" requirement — the extension is never loaded elsewhere.

---

## 6. Settings

```jsonc
// Developer environment
"aprodaAldc.devRoot": "",                          // e.g. "I:/Florian Köll"; wizard proposes

// Layer source
"aprodaAldc.source.mode": "managed",               // "managed" | "localFork"
"aprodaAldc.source.forkPath": "",
"aprodaAldc.source.repositoryUrl":
  "https://github.com/Aproda-AG/ALDC-AL-Development-Collection-Aproda.git",
"aprodaAldc.channel": "release",                   // "release" | "edge" | "pinned"
"aprodaAldc.pinnedVersion": "",

// BCQuality
"aprodaAldc.bcquality.strategy": "central",        // "central" | "per-parent"
"aprodaAldc.bcquality.path": "",                   // default <devRoot>/BCQuality-Aproda
"aprodaAldc.bcquality.setEnvInWorkspace": true,
"aprodaAldc.bcquality.autoFixWorkspacePath": true,

// Behaviour
"aprodaAldc.startupCheck.enabled": true,
"aprodaAldc.startupCheck.intervalHours": 24,
"aprodaAldc.pwshPath": "pwsh",
"aprodaAldc.validate.autoRunAfterUpdate": false,
"aprodaAldc.gettingStartedUrl":
  "https://github.com/Aproda-AG/ALDC-AL-Development-Collection-Aproda/blob/aproda/.github/onboarding.aproda.md"
```

All settings are written at **Global (User)** scope by the wizard. `bcquality.autoFixWorkspacePath` may also be set per workspace.

---

## 7. Component contracts

### 7.1 `env/gitRoot.ts`

```ts
function findGitRoot(start: string): Promise<string | undefined>
function resolveTargetRepo(): Promise<string | undefined>
function resolveAldcRepository(): Promise<AldcRepositoryResolution>
```

- `findGitRoot` walks upward testing for a `.git` entry, using pure path operations only. No `git rev-parse` — parsing its stdout mangles non-ASCII path segments under non-UTF-8 consoles. This mirrors the deliberate choice in `Sync-AprodaLayer.ps1` and `Initialize-AprodaProject.ps1` (D-19).
- `resolveTargetRepo` maps every workspace folder through `findGitRoot`, de-duplicates case-insensitively, then:
  - 0 roots → error "No git repository found in this workspace."
  - 1 root → return it, no prompt.
  - n roots → QuickPick, label = folder name, detail = full path.
- `resolveAldcRepository` filters the discovered Git roots for a root-level `aldc.yaml` and never prompts an agent: one match returns its absolute configuration path; none or multiple matches return an explicit state.

### 7.1.1 `agent/readAldcConfigurationTool.ts`

- Registers the read-only `aprodaAldc_readConfiguration` Language Model Tool, referenceable as `#aldcConfiguration`.
- Reads only the root-level `aldc.yaml` selected by `resolveAldcRepository` and returns structured values needed by agents: toolkit root, Copilot entrypoint, plans root, layer version, and BCQuality configuration.
- Invalid YAML and unresolved repositories return explicit structured states. The tool never guesses values or exposes arbitrary file reads.

### 7.2 `env/devRoot.ts`

Derivation proposal when unset: take the target repo path, keep the drive plus the **first** path segment (`I:\Florian Köll\Kunde\Repo` → `I:\Florian Köll`). If the resulting folder does not exist or equals the repo itself, fall back to the repo's parent. Always a proposal, never applied silently.

### 7.3 `source/layerSource.ts`

```ts
interface LayerSource {
  ensure(ref: ChannelRef): Promise<string>;   // returns absolute path usable as -ForkPath
  describe(): Promise<SourceStatus>;
}
```

**Managed mode.** Cache at `<globalStorageUri>/layer-cache/fork` — always on local disk, never on `I:`.

| Situation | Action |
|---|---|
| Cache absent | First try `git clone --no-checkout --filter=blob:none <url> fork` headlessly with stored credentials; on authentication failure open a **visible VS Code terminal** so the credential manager can prompt, then checkout of the resolved ref |
| Cache present | `git fetch --tags --prune` → resolve ref → `git checkout --detach <ref>` → `git reset --hard` → `git clean -xfd` |
| Fetch fails, network | Offer to continue with the cached state; show cache age; never proceed silently |
| Fetch fails, auth | Automatic fallback to the terminal path with an explanatory message |
| Cache corrupt | `repairCache` deletes and re-acquires |

Blob filtering rather than `--depth=1` — shallow clones complicate tag resolution and channel switching.

Headless git runs with `GIT_TERMINAL_PROMPT=0` so a missing credential fails fast instead of hanging.

**Local fork mode.** Uses `source.forkPath` directly. Before every operation it warns on: dirty working tree, branch other than `aproda`, behind `origin`. These are exactly the drift conditions that go unnoticed today.

### 7.4 `version/`

```ts
// installed.ts
function readInstalledVersion(repoRoot: string): string | undefined
// <repoRoot>/aldc.yaml -> aproda.layerVersion ; undefined = not installed

// available.ts
function resolveAvailable(channel: Channel): Promise<Resolved>
// release : highest tag matching ^v(.+)$   via `git ls-remote --tags <url>`
// edge    : refs/heads/aproda
// pinned  : aprodaAldc.pinnedVersion

// compare.ts
const RE = /^(\d+)\.(\d+)\.(\d+)_aproda\.(\d+)$/;
function compare(a: string, b: string): -1 | 0 | 1 | undefined
```

The version is **not** semver. Comparison is a numeric 4-tuple. String comparison is forbidden — it would rank `_aproda.10` below `_aproda.9`. Unparseable input yields `undefined`, comparison is skipped and the user is informed.

**Version contract to be enforced in CI:** a tag `v1.2.0_aproda.10` must point at a commit whose `aldc.yaml` contains exactly `layerVersion: "1.2.0_aproda.10"`. This matches the tags already present on the remote. A new fork workflow validates this on tag push, alongside the existing `bcquality-evidence` workflow. The extension additionally surfaces a visible warning on mismatch instead of silently doing the wrong thing.

`resolveAvailable` results are cached in `globalState` with a timestamp and honour `startupCheck.intervalHours`.

### 7.5 `ps/bridge.ts`

```ts
function runPowerShell(scriptPath: string, args: Record<string, string | boolean>, opts): Promise<PsResult>
```

Invocation shape:

```
pwsh -NoProfile -NonInteractive -Command "<inline>"
```

with `<inline>` composed as:

```powershell
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$env:APRODA_SYNC_SCRIPTDIR='<cache>\tools\aproda-sync'
& ([ScriptBlock]::Create((Get-Content -LiteralPath '<script>' -Raw))) -ProjectRoot '<target>' -ForkPath '<cache>'
```

Four non-negotiable details:

1. **No `-File`, no temporary `.ps1`.** Both are path-based execution and are blocked by the software restriction policy. Only `-Command` with content loading works.
2. **Quoting:** every path is emitted as a PowerShell single-quoted literal with embedded `'` doubled. No interpolation.
3. **Encoding:** the working paths contain umlauts. Set `[Console]::OutputEncoding` and decode stdout as UTF-8 in Node.
4. **`APRODA_SYNC_SCRIPTDIR` is mandatory** — under content loading `$PSScriptRoot` is empty and all three scripts fall back to this variable by design.

Executable resolution: `pwshPath` setting → `pwsh` on PATH → `powershell` → hard error pointing at Setup.

Output is streamed line by line into the `Aproda ALDC` output channel. Exit code determines success. On failure the notification carries a **Show log** button rather than a truncated message.

### 7.6 `workspace/bcqualityRoot.ts`

Implements L8 and L9. Runs after every init/update and once on activation.

```ts
function reconcile(repoRoot: string): Promise<ReconcileResult>
```

1. Locate `*.code-workspace` files in `repoRoot`. None → nothing to do (init creates one).
2. Compute `desired = path.relative(repoRoot, bcqualityPath)` with forward slashes.
   `I:/User/Kunde/Repo` + `I:/User/BCQuality-Aproda` → `../../BCQuality-Aproda`.
3. Find the folder entry whose `path` matches `/bcquality-aproda/i`. This is the same case-insensitive test the PowerShell init uses (`$_ -match 'bcquality-aproda'`), so a corrected path continues to satisfy the script's idempotency check and it will never re-add `../bcquality-aproda`.
4. If the entry is missing → append it. If present but different → rewrite it. Identical → no write.
5. Ensure `settings["terminal.integrated.env.windows"]["BCQUALITY_HOME"]` equals the absolute BCQuality path when `setEnvInWorkspace` is true.
6. Ensure `settings["files.watcherExclude"]` covers the BCQuality root (§9).
7. Skip entirely if the file has unsaved changes in an open editor.

Edits use `jsonc-parser` `modify` + `applyEdits` so comments and formatting survive. Note that once the PowerShell init has written the file it is plain JSON — the seed template's comments only exist before first init.

Behaviour is **silent** by design (option c): the result is logged to the output channel, no notification. `autoFixWorkspacePath: false` disables it.

### 7.7 `bcquality/install.ts`

| Situation | Action |
|---|---|
| Target absent | `git clone https://github.com/Aproda-AG/BCQuality-Aproda.git <path>`, first run in a visible terminal (private repo, same reasoning as L10) |
| Target present and is a git repo | Offer `git pull --ff-only` |
| Target present, not a git repo | Refuse, explain, offer another path |
| Target lies **inside** any git repo under `devRoot` | Hard refusal — nested example `.al` files would enter compilation |
| Folder name is not `BCQuality-Aproda` / `bcquality-aproda` | Warn: the workspace idempotency regex depends on the name |

Default path `<devRoot>/BCQuality-Aproda`. On the network drive this is a one-off cost paid per developer, not per project.

### 7.8 `startup/check.ts`

Runs asynchronously after activation, deferred, never blocking.

1. Confirm AL project: `app.json` in the git root or in a first-level folder (`App`, `Test`, or any).
2. Read installed version.
3. Throttle: if the last remote check is newer than `intervalHours`, reuse the cached result — no network call.
4. Resolve available version.
5. Dispatch:

| State | Notification | Buttons |
|---|---|---|
| No layer | *Aproda ALDC is not installed in this project.* | Install · Later · Never for this project |
| Outdated | *Aproda ALDC update available: 1.2.0_aproda.9 → 1.2.0_aproda.11* | Update · Preview changes · Later · Skip this version |
| Current | none | — |
| Metadata mismatch | *Version metadata mismatch — tag and aldc.yaml disagree.* | Show log |
| Unparseable version | *Cannot compare layer versions.* | Show log |

*Never for this project* persists in `workspaceState`; *Skip this version* in `globalState` keyed by version.

No state ever writes without explicit confirmation (HITL).

### 7.9 `commands/initProject.ts` — the core flow

```
1  resolveTargetRepo()
2  preflight
     a  target is a git work tree?        no  -> explain, offer `git init`, abort otherwise
     b  uncommitted changes under .github/?  yes -> list files, warn, require confirmation,
                                                    suggest Preview Changes
     c  pwsh available?                    no  -> error -> Setup
3  layerSource.ensure(channelRef)          -> forkPath   (progress: "Preparing layer source")
4  bridge.runPowerShell(
       <forkPath>/tools/aproda-sync/Bootstrap-AprodaProject.ps1,
       { ProjectRoot: repoRoot, ForkPath: forkPath, WhatIf?: true })
                                            (progress: "Applying Aproda ALDC layer")
5  bcqualityRoot.reconcile(repoRoot)
6  success notification -> [Open Getting Started] [Validate Installation] [Show log]
```

Preflight step 2a exists because `Bootstrap-AprodaProject.ps1` throws when the target is not a git work tree; catching it beforehand turns a stack trace into an actionable prompt.

`previewChanges` is the identical flow with `-WhatIf`, skipping steps 5 and 6.

The sync engine owns the Preview result. In `-WhatIf`, it skips byte-identical regular files by SHA-256 and compares dual-variants against their computed destination content. It emits `DRY-RUN complete — <n> change(s) would be applied.`; the extension parses that contract and shows either an up-to-date result or an aggregated change count with **Show Log** and **Update** actions.

### 7.9.1 `commands/resetData.ts`

`aprodaAldc.resetData` is a confirmed local-data reset, not an extension uninstaller. Its modal warning states its exact scope. After explicit confirmation it waits for an in-flight startup update check, removes only the managed cache in extension global storage, clears all global `aprodaAldc.*` user settings, and clears the extension's update-check state. It never modifies project files, workspace settings, or a configured local fork.

### 7.10 `commands/validate.ts`

```
node "<repoRoot>/.github/tools/aldc-validate/index.js" --config aldc.yaml     (cwd = repoRoot)
```

Explicit command only; `validate.autoRunAfterUpdate` defaults to `false`. Findings are reported but never block. Final integration shape depends on Spike S1.

### 7.11 `setup/wizard.ts`

Runs once on first activation (`globalState` marker) and on demand. Multi-step QuickPick, every step skippable, all values written to Global settings.

| Step | Content | Default |
|---|---|---|
| 1 | Environment check: `git`, `pwsh`, `node`, repository reachability | informational, with concrete fixes |
| 2 | Developer root | proposal from `devRoot.ts` |
| 3 | Layer source: managed / local fork | `managed` |
| 4 | Release channel | `release` |
| 5 | BCQuality strategy and path | `central`, `<devRoot>/BCQuality-Aproda` |
| 6 | Startup check on/off, interval | on, 24 h |
| 7 | Summary, open walkthrough | — |

`doctor.ts` repeats step 1 at any time and writes a full report to the output channel — the basis for self-service instead of support requests.

### 7.12 Getting Started

`vscode.env.openExternal(config.gettingStartedUrl)`. Default URL points at the `aproda` branch of the fork, overridable by setting so a document move needs no release.

Additionally a native walkthrough (`contributes.walkthroughs`) with four steps: Configure Settings · Preview or apply layer changes · Install BCQuality · Read the onboarding guide. First activation offers this walkthrough without interrupting the current workflow.

---

## 8. Version streams

Two independent streams — do not conflate them.

| Stream | Marker | Consumer |
|---|---|---|
| Layer | `aldc.yaml` → `aproda.layerVersion`, tag `v<version>` | Startup check, init/update |
| Extension | `package.json` → `version`, tag `vscode-ext/v<semver>` | VSIX self-update |

The extension checks the newest `vscode-ext/v*` tag on the standard startup throttle. On explicit user selection it authenticates with GitHub, downloads the release VSIX asset, installs it through VS Code, and offers a window reload.

---

## 9. Network drive considerations (`I:`)

`I:` is a mapped network drive and is mandated by infrastructure (L7). Consequences that must be handled rather than avoided:

| Concern | Mitigation |
|---|---|
| VS Code file watching over SMB is expensive and unreliable | `reconcile` writes `files.watcherExclude` entries for the BCQuality root into the workspace settings |
| Search indexing of the knowledge base | Add `search.exclude` for the BCQuality root unless the user opts out |
| Git operations are slower and occasionally flaky | Generous timeouts, no parallel git operations against the same path, single retry on transient failures, all output logged |
| Long paths | Recommend `core.longpaths=true`; doctor reports the current value |
| Layer cache must stay fast | Managed cache lives in `globalStorageUri` on local disk — never on `I:` |
| Locked files by other processes | Clone/pull failures are reported with the offending path instead of a generic error |

---

## 10. Phases

### Phase 0 · Spikes — precede everything

| ID | Question | Method | Drives |
|---|---|---|---|
| **S1** | Does `aldc-validate` behave correctly against the Aproda fork layout and can `js-yaml` be installed? | Passed: 0 warnings after `npm install --omit=dev`; no vendoring required | Phase 8 |
| **S2** | Does `git ls-remote --tags` against the private fork work headlessly? | Passed. Existing tags use `v<layerVersion>`, not `aproda-layer/v<version>` | Phase 2, 4 |
| **S3** | Does the `-Command` content-load invocation work from Node with an umlaut path and full parameter passing? | Passed: full `-WhatIf` flow ended `EXIT=0` | Phase 3 |

**Exit criterion:** met on 2026-08-26. Evidence is recorded in the Phase 0 evidence section. No design decision in phases 2, 3, 4 or 8 rests on an unresolved probe.

### Phase 1 · Scaffold

- Folder, `package.json`, `tsconfig.json`, direct Node TypeScript compiler, `.vscodeignore`, MIT license.
- `log.ts`, `config.ts`, context keys, `doctor`, `showLog`.
- `neverTouch` entry in `aproda-sync.json`; `.gitignore` additions.
- Verify `scripts/check-conformance.js` and root `package.json` tolerate the nested manifest.

**Done when:** the VSIX builds, installs, activates only in AL workspaces, and `Doctor` produces a meaningful report.

**Implemented 2026-08-26:** VSIX compilation and packaging pass. The direct TypeScript compiler is used because the local policy blocks native `esbuild.exe` and the `tsc` command shim. Installation and interactive Doctor validation remain part of the Phase 2 HITL checkpoint.

### Phase 2 · Layer source

- `gitClient.ts` with headless and terminal execution paths.
- `layerSource.ts` managed mode: clone, fetch, resolve, checkout, reset, clean.
- Local fork mode with drift warnings.
- `repairCache`.

**Done when:** the cache builds from nothing on a machine without cached credentials, and recovers from deliberate corruption via one command.

**Implemented 2026-08-26:** managed-cache and local-fork code paths compile, including headless clone/fetch with a visible-terminal authentication fallback, deterministic checkout/reset/clean, drift warnings and the repair command. Interactive cache acquisition remains part of the Phase 2 HITL checkpoint.

### Phase 3 · Core command

- `gitRoot.ts`, `detectAl.ts`.
- Preflight checks including `git init` offer and dirty-`.github` warning.
- `ps/bridge.ts`.
- `initProject`, `previewChanges`, progress and error surfaces.

**Done when:** a fresh repository initialized through the extension is byte-for-byte equivalent to one initialized through the existing PowerShell task, including a path containing an umlaut.

**Implemented 2026-08-27:** current-workspace Git-root resolution, multi-root selection, Git initialization confirmation, dirty-`.github` confirmation, SRP-safe Bootstrap bridge, Preview Changes and Initialize / Update commands are included in the VSIX. Interactive acceptance remains pending: run Preview Changes against an open AL repository, then confirm Initialize / Update on a disposable repository and compare its result with the existing PowerShell launcher.

**Phase 3.1 implemented 2026-08-27:** `-WhatIf` now compares regular files by SHA-256 and dual-variants against their computed destination content, reporting one machine-readable total: `DRY-RUN complete — <n> change(s) would be applied.` Preview shows `Aproda ALDC is up to date.` for zero, otherwise `Aproda ALDC found <n> changes.` with **Show Log** and **Update** actions.

**Phase 3.2 implemented 2026-08-27:** the extension contributes the read-only `#aldcConfiguration` Language Model Tool. It discovers the Git root from curated workspace folders and reads the authoritative root-level `aldc.yaml`; this supports consumer multi-root workspaces without exposing the repository root as a workspace folder.

**Phase 3.3 implemented 2026-08-27:** `Reset Layer Cache and Settings` is a confirmed extension-data reset. It clears the managed cache, all global `aprodaAldc.*` user settings, and update-check state while preserving project files, workspace settings, and local forks. It waits for an in-flight startup check before removing its state; focused tests cover settings, state, and cache isolation.

### Phase 4 · Version service and startup check

- `installed.ts`, `available.ts`, `compare.ts` with unit tests covering `_aproda.9` vs `_aproda.10`.
- Throttling, the five states, skip/never persistence.
- CI workflow enforcing the tag ↔ `aldc.yaml` contract.

**Done when:** an artificially lowered `layerVersion` produces exactly one correct notification, and a second window opening within the interval performs no network call.

**Implemented 2026-08-27:** shared version service reads `aldc.yaml` and remote `v*_aproda.*` tags, compares numeric version tuples, and handles current, outdated, ahead, missing, invalid and unavailable states. The manual **Check for Layer Updates** command always runs; the AL-only startup check is throttled by `startupCheck.intervalHours` (24 hours by default). `v1.2.0_aproda.9` versus `.10` comparison tests pass, and the fork-only version-contract workflow validates a matching tag against `aldc.yaml`. Interactive acceptance remains pending for startup notifications, command actions and persisted skip choices.

### Phase 5 · Setup wizard

- `devRoot.ts` derivation, wizard steps, global settings writes, first-run trigger.

**Done when:** a developer on `I:\<User>\<Kunde>\<Repo>` and one on `<other>\<User>\<Repo>` both complete setup without documentation.

**Implemented 2026-08-27:** the first activation offers a non-blocking settings wizard and the `Configure Settings` command reruns it on demand. It writes global settings for developer root, layer source, channel and startup-check interval, proposes the first segment beneath the drive as the developer root, and requires confirmation for a non-existent root. The managed-cache and local-fork choices retain their existing behavior; pinned channels require a valid layer version. Environment diagnostics run before the configuration prompts. Reset Local Data now also clears the first-run marker. Unit coverage verifies developer-root derivation; interactive acceptance remains pending for the two supported repository layouts.

### Phase 6 · BCQuality

- `install.ts` including the nested-repo refusal and the folder-name warning.
- `workspaceFile.ts`, `bcqualityRoot.ts` including `BCQUALITY_HOME`, watcher and search excludes.

**Done when:** after init plus reconcile a multi-root workspace opens with a working BCQuality root at both nesting depths, and a second run writes nothing.

**Implemented 2026-08-27:** `Install / Update BCQuality` manages one central `BCQuality-Aproda` clone at the configured path or `<developer root>/BCQuality-Aproda`. It refuses a target nested in another Git repository and uses a fast-forward-only update for an existing standalone clone. After a successful install and after each layer apply, the extension reconciles root-level `*.code-workspace` files using `jsonc-parser`: it corrects or adds the BCQuality root, sets `BCQUALITY_HOME`, and adds watcher and search exclusions. Dirty workspace editors are skipped, and the operation is logged without a notification. Focused tests verify JSONC comment preservation and the expected workspace settings; interactive acceptance remains pending for central clone authentication and both supported repository nesting depths.

### Phase 7 · Getting Started and walkthrough

- Link command, `contributes.walkthroughs`, icon, README, CHANGELOG.

**Done when:** the walkthrough appears after installation and leads through the full first-time flow.

**Implemented 2026-08-27:** `Open Getting Started` opens the configurable onboarding URL, and the native **Get Started with Aproda ALDC** walkthrough guides configuration, layer preview/apply, BCQuality installation, and the onboarding guide. The extension README and CHANGELOG document the supported command surface; `.github/onboarding.aproda.md` identifies the VS Code extension as the recommended in-workspace entry point. Interactive acceptance remains pending for the walkthrough rendering in an installed VSIX.

### Phase 8 · Validator

- Integration according to the S1 result; readable result presentation.

**Done when:** the command produces an understandable outcome rather than raw console output.

**Implemented 2026-08-27:** `Validate Installation` resolves the current repository and runs its synchronized `.github/tools/aldc-validate/index.js` with `--config aldc.yaml`. When `js-yaml` is absent, the command installs the validator's declared production dependencies in its own directory before validation. The full report is written to the Aproda ALDC output channel; the UI reports valid, valid-with-warnings, or validation-errors with **Show Log**. The validator was verified against the fork with exit code 0 and `COMPLIANT (0 warning(s))`.

### Phase 9 · Release

- `vsce package`, release tag `vscode-ext/v1.0.0`, VSIX asset, internal install instructions.

**Done when:** two colleagues install the VSIX and complete an initialization without asking questions.

**Implemented 2026-08-27:** the `Release Aproda ALDC VSIX` workflow runs on `vscode-ext/v*` tags, verifies the tag exactly matches `tools/aproda-vscode-extension/package.json`, runs `npm ci`, tests and packages the extension, then attaches `aproda-aldc.vsix` to a GitHub release. The extension checks tagged internal releases on the configured startup interval. After explicit user confirmation and GitHub authentication, it downloads the release asset, installs the VSIX through VS Code, and offers a window reload.

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| Policy tightening blocks `-Command` script blocks too | Verified early in S3. Fallback would be porting the sync core to TypeScript — deliberately out of scope, but the thin-bridge architecture keeps that door open |
| Private-repo authentication fails headless | Visible terminal for first clone, `GIT_TERMINAL_PROMPT=0` plus explicit fallback afterwards |
| Umlaut paths corrupt output or parameters | UTF-8 enforcement, pure path operations, mandatory umlaut test case from Phase 3 |
| Layer version and tag drift apart | CI contract check plus visible extension warning |
| Extension files leak into consumer projects | No `.aproda.` infix, `neverTouch` tripwire, one-time verification via dry-run pull |
| Silent workspace-file rewrites surprise users | Logged to output channel, disableable, skipped when the file is dirty, never touches unrelated entries |
| Network drive latency degrades the experience | §9 mitigations; cache stays local |
| Nested `package.json` breaks repo CI | Verified in Phase 1 |

---

## 12. Layer artefacts to update

The extension extends the Aproda layer and is subject to the steward guardrail. To be delivered alongside the code:

- `decisions.aproda.md` — **D-21** VS Code extension as a distribution channel · **D-22** managed layer cache instead of a local fork · **D-23** version contract `aldc.yaml` ↔ git tag · **D-24** central BCQuality with workspace path reconciliation and `BCQUALITY_HOME`
- `readme.aproda.md` — extension section, delineation from the PowerShell path
- `.github/onboarding.aproda.md` — extension as the recommended entry point, PowerShell task as the alternative
- `tools/aproda-sync/aproda-sync.json` — `neverTouch` entry
- New CI workflow for the version contract

The fork is the source of truth. Changes flow back via subtree push / PR.

---

## 13. Open items

Implementation has no remaining blocking items. The following acceptance and release actions are outside the automated implementation:

- Install the VSIX in a clean VS Code profile and verify the Phase 1, 2, 3, 4, 5, 6, and 7 interactive acceptance criteria.
- Have two colleagues install the first released VSIX and complete initialization (Phase 9 acceptance criterion).
- Set the first extension release version in `package.json` and `CHANGELOG.md`, commit it, push a matching `vscode-ext/v<semver>` tag, and verify the GitHub release asset.
