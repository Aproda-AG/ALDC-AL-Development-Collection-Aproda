# Runner Glue (central, version-agnostic)

These three files are the **PowerShell glue** that drives the headless AL test run.
They are **version-agnostic** (pure logic against the client DLL API) and therefore
ship **centrally with the skill** — unlike the 4 BC client DLLs, which are
version-pinned and materialized per project under `<project>/.../_runner/<major.minor>/`
(see [`../../references/runner.md`](../../references/runner.md)).

| File | Origin | Modified? | Role |
|------|--------|-----------|------|
| `ClientContext.ps1` | Microsoft (BC test automation, MIT) | **No** (verbatim) | `ClientContext` class — wraps `Microsoft.Dynamics.Framework.UI.Client.dll` |
| `PsTestFunctions.ps1` | Microsoft (BC test automation, MIT) | **No** (verbatim) | `New-ClientContext`, `Run-Tests`, helpers; Add-Type's the client DLLs |
| `AprodaRunner.ps1` | **Aproda** | n/a (authored) | Thin `Run-AlTests` wrapper over `New-ClientContext` + `Run-Tests` |

> The two Microsoft files are the canonical scripts shipped in BC artifacts /
> BcContainerHelper / the AL Test Runner's `TestClient` folder. They are kept
> **verbatim** so they can be refreshed 1:1 from any BC install when needed.
> `AprodaRunner.ps1` replaces the former hand-cleaned `Runner.cleaned.txt`.

## How the engine consumes them

The run bootstrap in `AprodaDeployRunVerify.psm1` (`Invoke-DeployRunVerifyRun`) dot-sources, in order:

```powershell
. (Join-Path $glueDir 'PsTestFunctions.ps1') `
    -clientDllPath   (Join-Path $runnerDir 'Microsoft.Dynamics.Framework.UI.Client.dll') `
    -newtonSoftDllPath (Join-Path $runnerDir 'Newtonsoft.Json.dll') `
    -clientContextScriptPath (Join-Path $glueDir 'ClientContext.ps1')
. (Join-Path $glueDir 'AprodaRunner.ps1')
Run-AlTests -ServiceUrl $cfg.serviceUrl -ExtensionId $cfg.testExtensionId `
    -TestCodeunitsRange $cfg.testCodeunitRange -ResultsFilePath $resultPath
```

- `glueDir` = this folder (resolved from the engine module path).
- `runnerDir` = the project's version-pinned DLL folder (`_runner/<major.minor>/`).
- `PsTestFunctions.ps1` finds `Microsoft.Internal.AntiSSRF.dll` next to the client DLL
  (i.e. in `runnerDir`), so that DLL must be materialized there too.

## Refreshing the Microsoft files

```powershell
$tc = '<any BC install>\...\TestClient'   # or the AL Test Runner extension TestClient folder
Copy-Item "$tc\ClientContext.ps1"   .\ClientContext.ps1   -Force
Copy-Item "$tc\PsTestFunctions.ps1" .\PsTestFunctions.ps1 -Force
```
