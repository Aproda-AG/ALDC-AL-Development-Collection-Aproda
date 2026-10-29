# Aproda Test-Loop — Reusable Scripts

> Part of `skill-aproda-deploy-run-verify`. **Immutable templates** — copy/run, never edit the engine.
> The engine is parameter-driven; everything project/environment-specific is **auto-derived** from `launch.json` + each `app.json`, with a tiny per-project config for the few non-derivable bits.

## Files

| File | Role | Edit? |
|------|------|-------|
| `AprodaDeployRunVerify.psm1` | Engine: Resolve-Config, Build (altool → alc), Publish (altool → Dev Endpoint POST), Tests (altool → web-client runner), one-time ASINST cleanup, full Loop | ❌ never |
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
$env:APRODA_DEPLOY_RUN_VERIFY_MODE   = 'full'   # 'full' (default) | 'buildonly' | 'skipbuild' | 'runonly'
Get-Content '<skillpath>/scripts/Invoke-AprodaDeployRunVerify.ps1' -Raw | Invoke-Expression
```

| `APRODA_DEPLOY_RUN_VERIFY_MODE` | Steps |
|---|---|
| `full` (default) | build → dependency preflight → publish → test |
| `buildonly` | build |
| `skipbuild` | dependency preflight → publish → test |
| `runonly` | test only (service preflight; no dependency check, no publish) |

Optional per-run environment variables:

| Variable | Values | Purpose |
|---|---|---|
| `APRODA_DEPLOY_RUN_VERIFY_FORCE_UPGRADE` | empty / `1` | per-run `altool publishapp --forceupgrade` (Tier 3: only on an explicit request; not available on the direct POST) |
| `APRODA_DEPLOY_RUN_VERIFY_TEST_ROUTE` | `auto` (default) / `altool` / `webClient` | force a test route, e.g. for a route comparison |
| `APRODA_DEPLOY_RUN_VERIFY_DEPLOY_ROUTE` | `auto` (default) / `altool` / `devEndpoint` | force a publish route, e.g. to validate the fallback |

A forced route that is unavailable stops with `ROUTE_UNAVAILABLE: <step>=<route>` instead of falling back. Invalid values stop the run before the engine starts.

**Routes (E-010).** Every step tries `altool` first and a legacy route second, and falls back **only** on an invocation failure (`altool` missing / cannot start / no HTTP answer / no parseable test result / incomplete test result) — never on a red test, a compiler error, a sync/schema message, or HTTP 401/415/422:

| Step | First | Fallback |
|---|---|---|
| Build | `altool compile` | `alc.exe` |
| Publish (both adapters) | `altool publishapp` | direct multipart POST to the Dev Endpoint |
| Tests | `altool runtests --testgroups` | web-client runner (needs the runner DLLs below) |

The run ends with the existing `TIMING:` line, then `ROUTE: build=<r> · deploy=<r> · tests=<r>` and one `ROUTE-FALLBACK: <step> → <route> (<reason>)` line per fallback; the summary object carries the same data as `Routes` and `AlTool = { Path, Version, Source }`.

**Schema mode (D-39), both adapters.** `fkhSyncMode` (`Add` default | `ForceSync`) applies to **both** adapters and both publish routes: `Add` → `Synchronize` / `synchronize`, `ForceSync` → `ForceSync` / `forcesync` (the run prints `SCHEMA MODE: ForceSync (fkhSyncMode)`). Set `ForceSync` only for a destructive schema change and inform the user briefly. `Recreate` is never used. The DependencyPublishingOption is taken from the selected `launch.json` configuration (default `Default`).

Publishing goes through the Business Central Dev Endpoint for ASINST and Fkh alike; the Management DLL is used on ASINST only to read the app state and for the one-time cleanup (`Get-DeployRunVerifyCleanupCandidates` / `Remove-DeployRunVerifyAppVersion`, HITL per package — see `../SKILL.md`). Global-scope publishing is outside the engine and only on explicit user request.

Each completed run reports `TIMING: build=… · deploy=… · tests=… · total=…`. The `tests` duration includes runner initialization, connection, and test execution; skipped stages are shown as `skipped` or `n/a`. Use comparable runs against the same target to evaluate deployment changes such as the FKH Dev Endpoint default.

> **Why `iex` + `APRODA_DEPLOY_RUN_VERIFY_MODULE`?** Some machines block `.psm1` import via Software
> Restriction Policy / Group Policy, so the entry point does **not** use `Import-Module`; it
> dot-sources the engine content (SRP-safe). When dot-loaded via `iex`, `$PSCommandPath` is
> empty, so the module path must come from `$env:APRODA_DEPLOY_RUN_VERIFY_MODULE`.

> The agent only ever touches the **config copy**, never the engine. New project = new 3-line config.

## New project / repo bootstrap (reproducible checklist)

A brand-new project needs **exactly one** project-local file — the config copy. Everything else is central (glue), generated (results), or materialized on demand (the 4 client DLLs). Steps:

1. **Prerequisite — target selection**: the project has `.vscode/launch.json` with a `server`-type configuration (server/instance/tenant/authentication), and that configuration is selected in `.github/aldc.local.json` (*Select AL Target* in the Aproda extension, or `Set-AprodaAlLocalSelection`). The engine derives the ServiceUrl from it. Without a usable selection a full run stops with `TARGET_SELECTION_<STATE>` and lists the available configurations (build-only continues without a target).
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
| target (`server` host, `scheme`, `serverInstance`, `tenant`, `port`, `authentication`, `dependencyPublishingOption`) | the configuration selected in `.github/aldc.local.json` (git-ignored; *Select AL Target* in the Aproda extension or `Set-AprodaAlLocalSelection`), resolved from that project's `.vscode/launch.json` |
| `serviceUrl` | `http://{server}/{serverInstance}/cs?tenant={tenant}&company={companyName}` (web client, port 80) |
| app `name`, `version`, `publisher`, `id` | each app's `app.json` |
| `testExtensionId` | the test app's `app.json → id` |
| `testCodeunitRange` | the test app's `idRanges` (or config override) |
| `alcPath` | resolved only when the `alc.exe` fallback runs: folder of `altool.exe`, then the highest `ms-dynamics-smb.al-*` extension (`bin\alc.exe`, `bin\win32\alc.exe`) |

## Non-derivable (must be in config)

- **`appsInOrder`** — project dirs in **dependency order** (last = the test app). Scope is **this project's own apps only** — Aproda foundation/third-party dependencies (ASFL, other Aproda modules, Fremd Module) are not project-repo artifacts and are never listed here; a missing one is caught by the engine's preflight (`Test-DeployRunVerifyTargetDependencies`) and resolved HITL (see [`../references/dependency-resolution.md`](../references/dependency-resolution.md)).
- **`runnerDir`** — project-local BASE folder for the AL test-runner DLLs. The engine uses a **version subfolder** `<runnerDir>/<major.minor>` matched to the BC server and validates that the client DLL **major** matches the target (see [`../references/runner.md`](../references/runner.md)). The whole `_runner/` folder is git-ignored — the 4 DLLs are **materialized on demand**.
- **Runner DLL source** — where the 4 version-pinned client DLLs come from:
  - `bcDvdRoot` + `bcCountry` *(preferred)* — the K: BC product DVD; the engine globs the highest minor at `<bcDvdRoot>\<major>\<bcCountry>.<major>.<minor>\Applications\TestFramework\TestRunner\Internal`.
  - `runnerClientSource` *(alternative, wins)* — explicit folder, searched recursively.
  - `runnerClientFromServer=true` *(fallback)* — pull from a remote BC Service folder via remote PowerShell.
- **`companyName`** — pinned into the serviceUrl (`/cs?tenant=<t>&company=<c>`) so the headless runner doesn't prompt for a company. Empty → `/cs/`.
- **`bcVersion`** *(optional)* — pin the target BC platform `major.minor` (selects the runner subfolder; the client DLL must match the **major**); empty = derive from the live server.
- **`authentication`** — not a config key any more: set it in the selected `launch.json` configuration. **Required, no default**: `Windows` or `UserPassword`; missing (`AUTH_MISSING`), `AAD`/`MicrosoftEntraID` (`AUTH_UNSUPPORTED`), unknown (`AUTH_UNKNOWN`) values and `UserPassword` over `http` (`USERPASSWORD_OVER_HTTP`) stop with `TARGET_BLOCKED: <codes>` before any connection.
- **`mgmtDllPath`** — server-side path to `Microsoft.Dynamics.Nav.Management.dll` (used inside the remote session).

## Target errors and migration (E-010)

The engine reads the target only from `aldc.local.json` + `launch.json` (library `skill-aproda-al-mcp/scripts/AprodaAlTarget.ps1`, loaded from the sibling skill; missing → `AL_MCP_SKILL_MISSING`).

| Message | Meaning / action |
|---|---|
| `CONFIG_MIGRATION_REQUIRED: <keys>` | The DRV config still carries a non-empty `launchConfig`, `server`, `serverInstance`, `tenant`, `scheme` or `authentication`. Move the choice into `aldc.local.json` (`Set-AprodaAlLocalSelection`) and delete those lines from the config. `fkhSyncMode` is a normal key and stays. |
| `CONFIG_OBSOLETE_KEY: <keys>` (warning) | The same keys with an empty value (`""`/`false`): harmless, delete them in the next commit. |
| `TARGET_SELECTION_<STATE>` (`ABSENT`, `INVALID`, `STALE`, `NOTOOLKIT`) | No usable selection; the message lists all `server` configurations so the user can choose. |
| `TARGET_BLOCKED: <codes>` | The selected `launch.json` configuration is not usable for a target run (`AUTH_MISSING`, `AUTH_UNSUPPORTED`, `AUTH_UNKNOWN`, `USERPASSWORD_OVER_HTTP`, `SERVER_INVALID`, `INSTANCE_MISSING`, `PORT_INVALID`, `NOT_ONPREM`, `DEPENDENCY_OPTION_INVALID`), followed by one message per issue. |

**Build-only** (`APRODA_DEPLOY_RUN_VERIFY_MODE='buildonly'`) needs no target: without a usable selection it continues with `TARGET: none (build-only)` and skips the preflight.

> The 3 glue scripts are **not** project config — they ship centrally in `scripts/runner-glue/` and are loaded content-based (SRP-safe) at run time.

## Preflight / HITL

The engine calls a preflight before the first publish: it pings the service and (if reachable) checks for the Test Toolkit. On failure it **warns and offers build-only** — it does not hard-block. Per the skill's operational-safety rule, deploying to a **shared OnPrem server** requires the launch.json environment selection to be acknowledged once per spec.

> **Historical status (before E-010).** The block below describes the live verification of the former Management-DLL deploy (uninstall → unpublish → publish → sync → install). That deploy route is gone: publishing is now the Dev Endpoint chain described above. Items 1, 2 and 6 still apply.
>
> **Status:** Engine **fully live-verified** end-to-end against Straub Medical AG Base + Test (BC 28, server `apd-svw-nst05`): config resolution, preflight, server/runner-version validation, build of both apps, **deploy** (uninstall → unpublish → publish → sync → install), **runner materialization from the K: BC DVD**, and the **test run → 27/27 passed** — all via the entry point. Issues found and fixed during verification:
> 1. JSONC comment stripper destroyed `http://` URLs in `launch.json` → `(?<!:)` lookbehind.
> 2. Entry point used `Import-Module`, blocked by SRP on the target machine → SRP-safe dot-sourcing (needs `$env:APRODA_DEPLOY_RUN_VERIFY_MODULE`).
> 3. Same-version redeploy with a changed table set: `Install-NAVApp` refuses against the stale synced schema → **ForceSync → Install** fallback (drops data for changed tables — expected in a dev loop).
> 4. `Sync -Mode Add` emits a benign non-terminating error on redeploy that leaked to the `ErrorAction=Stop` caller and aborted before the run → silenced + `$Error.Clear()`.
> 5. Install failures were masked (loop ran tests against a half-deployed server) → **fail-loud**: deploy verifies `IsInstalled` and throws `DEPLOY INCOMPLETE` otherwise.
> 6. The run-bootstrap loaded the glue path-based (SRP-blocked) → **content-based** `[ScriptBlock]::Create` loading of all 3 glue files, Add-Type the client DLLs **before** the `ClientContext` scriptblock, and neutralize PsTestFunctions' internal `. $clientContextScriptPath`.
