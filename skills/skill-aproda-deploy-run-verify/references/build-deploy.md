# Reference: Build & Deploy (BC OnPrem)

> Loaded on demand by [`../SKILL.md`](../SKILL.md). **SKELETON** — verified facts are marked ✅; `TODO` items need finishing/generalizing (current values are from the Audit Trail validation environment and must be parameterized).

## Environment (current reference values — parameterize via launch.json)

| Item | Value | Note |
|------|-------|------|
| Server / instance | `apd-svw-nst05` / `STRAUB_MEDICAL_AG_28_CH_FKO` | ✅ from launch.json |
| Tenant | `default` | |
| Auth | Windows | |
| Mgmt DLL | `D:\28\<instance>\Management\Microsoft.Dynamics.Nav.Management.dll` | ✅ |
| `alc.exe` | `…\ms-dynamics-smb.al-17.0.2273547\bin\win32\alc.exe` | AL Compiler 17.0.34 |

> TODO: source server/instance/tenant from the selected `launch.json` configuration instead of hardcoding.

## Build (version-dynamic)

✅ **Proven pattern** (`_Cycle.ps1`): read versions from `app.json`, never hardcode.

1. Build **Base** → `Aproda AG_<name>_<version>.app` (`/packagecachepath:Base\.alpackages /loglevel:Error`).
2. Remove the **old Base symbol** from `Test\.alpackages`, copy the **new** Base `.app` in.
3. Build **Test** against the refreshed Base symbol.

**Engine route (E-010).** Each app is built with `altool compile /project:<dir> /packagecachepath:<pkg> /out:<app> /loglevel:Error` (the verb passes the arguments to `alc`), falling back to `alc.exe` with the same arguments when `altool` is unavailable, has no `compile` command, cannot be started, or exits non-zero without an `error AL\d{4}` diagnostic. A compiler error fails the build and never triggers the fallback. `alc.exe` is located only when the fallback runs (config `alcPath`, then next to `altool.exe`, then the highest installed AL extension; `bin\alc.exe` and `bin\win32\alc.exe` layouts) — a missing `alc.exe` never blocks the config load. The package-cache refresh in step 2 happens on every route.

✅ `alc.exe` **exit code 0 = success** (warnings tolerated). Pre-existing warnings (AA0074, AA0210, Text→Code overflow, AL1025 from the `_runner` `TestResults.xml`) do **not** block.

## Deploy (dependency order: Base before Test)

**One publish chain for both adapters (E-010, D-53).** Per app, in dependency order:

1. **`altool publishapp <app> --server <ServerUrl> --serverinstance <inst> --port <port> --authentication <auth> --tenant <tenant> --environmenttype OnPrem --schemaupdatemode <Synchronize|ForceSync> [--forceupgrade]`** — the complete bundle from the selected `launch.json` configuration; **no `--project`** (nothing may merge from `launch.json`, whose first configuration would otherwise fill gaps). `UserPassword` credentials reach the child process only through its environment (`BC_SERVER_USERNAME` / `BC_SERVER_PASSWORD`), never the command line.
2. **Direct Dev Endpoint POST** — only when step 1 is unavailable or fails on invocation: `POST {ServerUrl}:{Port}/{ServerInstance}/dev/apps?SchemaUpdateMode=<synchronize|forcesync>&DependencyPublishingOption=<Default|Ignore|Strict>&tenant=<tenant>`, multipart as specified in the E-010 *dev-endpoint-publish-protocol* (`Windows` → default credentials; `UserPassword` → in-memory Basic header, HTTPS and ASCII credentials only). Never retried.
3. **Verify the state** of the exact version: `IsInstalled = True` and `SyncState = Synced` (ASINST via the Management DLL, Fkh via `fkh getappinfo`), else `DEPLOY INCOMPLETE`.

Both publishes are **DEV-scope** (Dev Endpoint). The Management DLL (`Publish-NAVApp`, Global/Tenant scope) is not used to publish: it cannot publish a DEV app and would mix scopes on the NST. The default schema mode is `Add` (`Synchronize`/`synchronize`); `ForceSync` when a destructive schema change requires it (inform the user briefly, D-39); `Recreate` is never used. Global-scope publishing is outside the engine and only on explicit user request.

**Classification and what to do.** `Duplicate` (HTTP 422, *duplicate package ID*) → stop and inspect the state; a rebuilt package with a new package ID publishes again under the same version. `AuthFailure` → one re-prompt for `UserPassword`, then blocker. `ProtocolError` (415) / `Rejected` (other 4xx/5xx, sync or schema message) → stop with the redacted server text. `InvocationFailure` → fall back from `altool` to the POST; from the POST → stop. Details: [`SKILL.md`](../SKILL.md) → *Target Adapter Selection*, [`redeploy-recovery.md`](redeploy-recovery.md).

### MS test-library prerequisite chain ✅ (live-verified 2026-06-29)

A Test app that depends on `Tests-TestLibraries` / `Application Test Library` will **not deploy** unless the full MS test-library chain is installed on the tenant first, in dependency order:

`Test Runner` → `Any` → , observed 2026-06-29 with the former Management-DLL publish):** the publish **blocks silently** (no PS error, no timeout) when a dependency is missing. The real cause appears **only in the Windows Event Log** (source `MicrosoftDynamicsNavServer$<instance>`, event 701): `error AL1024: …'Application Test Library'… could not be loaded` / `…'Business Foundation Test Libraries'… could not be found in the database`. The engine's dependency preflight (D-52) now catches a missing dependency before any publish; record what the Dev Endpoint reports if one slips through

**Hang symptom (no error):** `Publish-/Sync-NAVApp` **blocks silently** (no PS error, no timeout) when a dependency is missing. The real cause appears **only in the Windows Event Log** (source `MicrosoftDynamicsNavServer$<instance>`, event 701): `error AL1024: …'Application Test Library'… could not be loaded` / `…'Business Foundation Test Libraries'… could not be found in the database`.

**Diagnose before publish:** `(Get-NAVAppInfo -Path <app>).Dependencies` lists what each package needs. `.app` sources are on the K: DVD (see `site-profile.aproda.md → MS test-library .app sources`). Already-installed apps return harmless *"already published"* warnings; publish only the missing links.

> `Application Test Library` (BC28, 42 CUs) holds the standard cross-app libs — `Library - Inventory/Sales/Purchase/Manufacturing/Warehouse/ERM/Job/Random/Utility/Assert`. `Tests-TestLibraries` (128 CUs) is specialized: mocks, `…OnPrem` libs, .NET-bound CRM/Graph/SMTP/Azure AD/XML, permissions, job-queue samples — only needed if your tests touch those.

Cmdlet notes that still apply (the Management DLL is used to **read** state on ASINST):
- `Get-NAVAppInfo -Tenant default -TenantSpecificProperties` for **installed-state** queries (omit `-Tenant` for published-version queries; `-Tenant` **requires** `-TenantSpecificProperties` or it prompts). `PublishedAs` is absent on BC 28; a DEV package also reports `Scope=Tenant`, so provenance cannot be read from the NST.

> **Historical (replaced by E-010, D-53).** The former ASINST route copied the `.app` to a server temp dir and ran uninstall → unpublish → `Publish-NAVApp -Scope Tenant` → `Sync-NAVApp` → `Install-NAVApp` with an automatic ForceSync/data-upgrade escalation. It is gone from the engine: a schema failure is now a `Rejected` outcome and the agent decides on `fkhSyncMode = ForceSync` per D-39. Versions that route left on an NST are removed once, with HITL, through the cleanup procedure in [`../SKILL.md`](../SKILL.md) → *One-time ASINST cleanup*.

### Same-version redeploy ✅
A rebuilt package with the same app version but a new package ID publishes through the Dev Endpoint without removing dependent apps (validated on both adapters). The exact same package file is refused with HTTP 422 (`duplicate package ID`) — never repeat it. A changed table set under `Synchronize` is a `Rejected` outcome; re-run with `fkhSyncMode = ForceSync` (it can drop data of changed tables — acceptable in a development environment, not in production: bump the version there).

- **Fail-loud**: after every publish the engine verifies `IsInstalled` and `SyncState = Synced` for the exact version and throws `DEPLOY INCOMPLETE` otherwise — never run tests against a half-deployed server.

For the recovery order, including duplicate packages, `NotSynced` leftovers and the explicitly requested Global-scope recovery, see [`redeploy-recovery.md`](redeploy-recovery.md).

## PowerShell execution rules ✅

- Run multi-step PS via `Get-Content <file> -Raw | Invoke-Expression` (avoids multi-line paste mangling — direct multi-line terminal commands echo but produce no output).
- Confirm final state `Installed=True` for **both** apps before running tests.

## TODO

- Parameterize server/instance/tenant/DLL path from `launch.json` (server/instance/tenant: done via the engine config; Mgmt DLL path still per-project in `deploy-run-verify.config.jsonc`).

> Hygiene (resolved): the whole `_runner/` folder is git-ignored (DLLs materialized from the K: BC DVD, glue central) and scratch work lives in `Test/PowerShell/_temp/`; the `_runner` `TestResults.xml` AL1025 warning is harmless. See [`runner.md`](runner.md) → *Hygiene* + *versioned subfolders*.
