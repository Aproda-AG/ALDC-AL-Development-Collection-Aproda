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

✅ `alc.exe` **exit code 0 = success** (warnings tolerated). Pre-existing warnings (AA0074, AA0210, Text→Code overflow, AL1025 from the `_runner` `TestResults.xml`) do **not** block.

## Deploy (dependency order: Base before Test)

✅ **Proven sequence** (`_Cycle.ps1` / `_Deploy.ps1`):
uninstall Test → uninstall Base → unpublish both → publish/sync/install **Base** → publish/sync/install **Test**.

Key cmdlet flags (✅ verified):
- `Publish-NAVApp -SkipVerification -Scope Tenant -Tenant default`
- `Sync-NAVApp -Mode Add`
- `Get-NAVAppInfo -Tenant default -TenantSpecificProperties` for **installed-state** queries (omit `-Tenant` for published-version queries; `-Tenant` **requires** `-TenantSpecificProperties` or it prompts).
- Copy the `.app` to a server temp dir via `Copy-Item -ToSession`.

### Install-or-upgrade fallback ✅
`Install-NAVApp` fails when prior-version tenant data is retained ("…bereits eine frühere Version installiert ist… Start-NAVAppDataUpgrade…"). Pattern:

```powershell
try   { Install-NAVApp -ServerInstance $si -Name $name -Version $ver -Tenant $tenant -ErrorAction Stop }
catch { Start-NAVAppDataUpgrade -ServerInstance $si -Name $name -Version $ver -Tenant $tenant }
```

### Same-version redeploy → ForceSync ✅ (live-verified 2026-06-24)

A test-loop redeploys the **same version** (e.g. `28.0.0.7`) repeatedly while the schema changes. After uninstall + republish, `Sync -Mode Add` leaves the **stale** synced schema, so `Install-NAVApp` refuses:

> *"…weist einen anderen Satz von Tabellen und Tabellenerweiterungen auf als das zuvor synchronisierte Erweiterungspaket… die Synchronisierung des aktuellen Erweiterungspakets erzwingen."*

The engine's `InstallOrUpgrade` escalates (no localized-message parsing):

```powershell
try { Install-NAVApp … -ErrorAction Stop; return }            # 1) plain install
catch {                                                        # 2) ForceSync then install
  Sync-NAVApp … -Mode ForceSync -Force -ErrorAction Stop
  try { Install-NAVApp … -ErrorAction Stop; return }
  catch { Start-NAVAppDataUpgrade … }                          # 3) retained-data upgrade
}
```

- `-Mode ForceSync` **drops data for changed tables** — acceptable/expected inside a dev test-loop, *not* for production (there, bump the version instead).
- `Sync -Mode Add` can emit a **benign non-terminating error** on redeploy; silence it (`-ErrorAction SilentlyContinue`) and `$Error.Clear()` before returning, or it leaks to an `ErrorAction=Stop` caller and aborts the run.
- **Fail-loud**: after deploy, verify `IsInstalled` for every target app and `throw` (`DEPLOY INCOMPLETE`) otherwise — never run tests against a half-deployed server.

## PowerShell execution rules ✅

- Run multi-step PS via `Get-Content <file> -Raw | Invoke-Expression` (avoids multi-line paste mangling — direct multi-line terminal commands echo but produce no output).
- Confirm final state `Installed=True` for **both** apps before running tests.

## TODO

- Parameterize server/instance/tenant/DLL path from `launch.json` (server/instance/tenant: done via the engine config; Mgmt DLL path still per-project in `testloop.config.jsonc`).

> Hygiene (resolved): the whole `_runner/` folder is git-ignored (DLLs materialized from the K: BC DVD, glue central) and scratch work lives in `Test/PowerShell/_temp/`; the `_runner` `TestResults.xml` AL1025 warning is harmless. See [`runner.md`](runner.md) → *Hygiene* + *versioned subfolders*.
