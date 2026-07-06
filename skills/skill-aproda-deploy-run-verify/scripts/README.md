# Aproda Test-Loop — Reusable Scripts

> Part of `skill-aproda-deploy-run-verify`. **Immutable templates** — copy/run, never edit the engine.
> The engine is parameter-driven; everything project/environment-specific is **auto-derived** from `launch.json` + each `app.json`, with a tiny per-project config for the few non-derivable bits.

## Files

| File | Role | Edit? |
|------|------|-------|
| `AprodaDeployRunVerify.psm1` | Engine: Resolve-Config, Build, Deploy, materialize Runner, Run, full Loop | ❌ never |
| `Invoke-AprodaDeployRunVerify.ps1` | Thin entry point (run via `Get-Content … -Raw \| iex`) | ❌ never |
| `runner-glue/` | The 3 version-agnostic glue scripts (central, shared by all projects/versions) | ❌ never |
| `deploy-run-verify.config.template.jsonc` | Per-project config — **copy** to the project, fill a few values | ✅ the copy only |

## Mini-effort usage (per project)

1. **Copy** `deploy-run-verify.config.template.jsonc` → `<project>/deploy-run-verify.config.jsonc`.
2. Fill the few non-derivable values (apps in dependency order, runner dir, `companyName`, server-side Mgmt DLL path, and the runner-DLL source — preferably `bcDvdRoot` + `bcCountry`). Most other fields can stay empty → auto-derived.
3. Run:

```powershell
# Set the three env hints, then dot-load the entry via iex (SRP-safe; no Import-Module).
$env:APRODA_DEPLOY_RUN_VERIFY_CONFIG = '<project>/Test/deploy-run-verify.config.jsonc'
$env:APRODA_DEPLOY_RUN_VERIFY_MODULE = '<skillpath>/scripts/AprodaDeployRunVerify.psm1'
$env:APRODA_DEPLOY_RUN_VERIFY_MODE   = 'full'   # 'full' (default) | 'buildonly' | 'skipbuild'
Get-Content '<skillpath>/scripts/Invoke-AprodaDeployRunVerify.ps1' -Raw | Invoke-Expression
```

> **Why `iex` + `APRODA_DEPLOY_RUN_VERIFY_MODULE`?** Some machines block `.psm1` import via Software
> Restriction Policy / Group Policy, so the entry point does **not** use `Import-Module`; it
> dot-sources the engine content (SRP-safe). When dot-loaded via `iex`, `$PSCommandPath` is
> empty, so the module path must come from `$env:APRODA_DEPLOY_RUN_VERIFY_MODULE`.

> The agent only ever touches the **config copy**, never the engine. New project = new 3-line config.

## New project / repo bootstrap (reproducible checklist)

A brand-new project needs **exactly one** project-local file — the config copy. Everything else is central (glue), generated (results), or materialized on demand (the 4 client DLLs). Steps:

1. **Prerequisite — `launch.json`**: the test project has `.vscode/launch.json` with a `server`-type configuration (server/instance/tenant). The engine derives the ServiceUrl from it. If several exist, set `launchConfig` to the one to use.
2. **Prerequisite — runner DLL source reachable**: either the K: BC DVD share (`bcDvdRoot` + `bcCountry`) **or** an explicit `runnerClientSource`. No DLLs are committed.
3. **Copy** `deploy-run-verify.config.template.jsonc` → `<project>/deploy-run-verify.config.jsonc`; fill `appsInOrder`, `runnerDir`, `companyName`, `mgmtDllPath`, and the runner-DLL source.
4. **`.gitignore`** (git root): ignore the generated runner + scratch dirs — nothing under them is committed:
   ```gitignore
   **/PowerShell/_runner/
   **/PowerShell/_temp/
   ```
   (Adjust the path if `runnerDir` is elsewhere; `_temp/` is for the `Get-Content -Raw | iex` scratch scripts.)
5. **Run** the entry point (next section). First run materializes `_runner/<ver>/` from the DVD; later runs reuse it.

That is the whole per-project surface. The 3 glue scripts, the engine, and the DLL-materialization logic are **not** copied — they live once in the skill.

## What is auto-derived (zero config)

| Value | Source |
|-------|--------|
| `server`, `serverInstance`, `tenant` | selected `launch.json` configuration |
| `serviceUrl` | `http://{server}/{serverInstance}/cs?tenant={tenant}&company={companyName}` (web client, port 80) |
| app `name`, `version`, `publisher`, `id` | each app's `app.json` |
| `testExtensionId` | the test app's `app.json → id` |
| `testCodeunitRange` | the test app's `idRanges` (or config override) |
| `alcPath` | latest `ms-dynamics-smb.al-*` VS Code extension |

## Non-derivable (must be in config)

- **`appsInOrder`** — project dirs in **dependency order** (last = the test app).
- **`runnerDir`** — project-local BASE folder for the AL test-runner DLLs. The engine uses a **version subfolder** `<runnerDir>/<major.minor>` matched to the BC server and validates the client DLL version (see [`../references/runner.md`](../references/runner.md)). The whole `_runner/` folder is git-ignored — the 4 DLLs are **materialized on demand**.
- **Runner DLL source** — where the 4 version-pinned client DLLs come from:
  - `bcDvdRoot` + `bcCountry` *(preferred)* — the K: BC product DVD; the engine globs the highest minor at `<bcDvdRoot>\<major>\<bcCountry>.<major>.<minor>\Applications\TestFramework\TestRunner\Internal`.
  - `runnerClientSource` *(alternative, wins)* — explicit folder, searched recursively.
  - `runnerClientFromServer=true` *(fallback)* — pull from a remote BC Service folder via remote PowerShell.
- **`companyName`** — pinned into the serviceUrl (`/cs?tenant=<t>&company=<c>`) so the headless runner doesn't prompt for a company. Empty → `/cs/`.
- **`bcVersion`** *(optional)* — pin the target BC platform `major.minor`; empty = derive from the live server.
- **`mgmtDllPath`** — server-side path to `Microsoft.Dynamics.Nav.Management.dll` (used inside the remote session).

> The 3 glue scripts are **not** project config — they ship centrally in `scripts/runner-glue/` and are loaded content-based (SRP-safe) at run time.

## Preflight / HITL

The engine calls a preflight before the first publish: it pings the service and (if reachable) checks for the Test Toolkit. On failure it **warns and offers build-only** — it does not hard-block. Per the skill's operational-safety rule, deploying to a **shared OnPrem server** requires the launch.json environment selection to be acknowledged once per spec.

> **Status:** Engine **fully live-verified** end-to-end against Straub Medical AG Base + Test (BC 28, server `apd-svw-nst05`): config resolution, preflight, server/runner-version validation, build of both apps, **deploy** (uninstall → unpublish → publish → sync → install), **runner materialization from the K: BC DVD**, and the **test run → 27/27 passed** — all via the entry point. Issues found and fixed during verification:
> 1. JSONC comment stripper destroyed `http://` URLs in `launch.json` → `(?<!:)` lookbehind.
> 2. Entry point used `Import-Module`, blocked by SRP on the target machine → SRP-safe dot-sourcing (needs `$env:APRODA_DEPLOY_RUN_VERIFY_MODULE`).
> 3. Same-version redeploy with a changed table set: `Install-NAVApp` refuses against the stale synced schema → **ForceSync → Install** fallback (drops data for changed tables — expected in a dev loop).
> 4. `Sync -Mode Add` emits a benign non-terminating error on redeploy that leaked to the `ErrorAction=Stop` caller and aborted before the run → silenced + `$Error.Clear()`.
> 5. Install failures were masked (loop ran tests against a half-deployed server) → **fail-loud**: deploy verifies `IsInstalled` and throws `DEPLOY INCOMPLETE` otherwise.
> 6. The run-bootstrap loaded the glue path-based (SRP-blocked) → **content-based** `[ScriptBlock]::Create` loading of all 3 glue files, Add-Type the client DLLs **before** the `ClientContext` scriptblock, and neutralize PsTestFunctions' internal `. $clientContextScriptPath`.
