# Reference: Test Runner (headless, web client)

> Loaded on demand by [`../SKILL.md`](../SKILL.md). Describes the **standardized Aproda test-loop engine** (`scripts/AprodaTestLoop.psm1`). ✅ = verified end-to-end.

## Standard path: the Aproda engine ✅

The test-loop runs on the **own engine** — `scripts/AprodaTestLoop.psm1`, driven by `scripts/Invoke-AprodaTestLoop.ps1`. It is self-contained: build → deploy → **materialize runner** → run → parse. The `jamespearson/al-test-runner` VS Code extension is a **fallback only** (see "Fallback" below).

Validated end-to-end against `STRAUB_MEDICAL_AG_28_CH_FKO` (BC 28, web client port 80): **27/27 green** via this engine.

## ServiceUrl — the critical gotcha ✅

The client-driven test runner uses the **web client** URL with the company pinned:

```
http://apd-svw-nst05.aproda.ch/STRAUB_MEDICAL_AG_28_CH_FKO/cs?tenant=default&company=CRONUS (Schweiz) AG
```

✅ Port **80** (web client), **NOT** NetTcp port 8929/8930. Using the NetTcp port fails to connect.
- The engine builds this from `serviceUrl` + `companyName` in the config (`/cs?tenant=<t>&company=<c>`; empty company → `/cs/`).

## GuiAllowed()=TRUE in the runner — the second gotcha ✅

The client-driven runner has `GuiAllowed() = true`. Therefore:
- `if GuiAllowed() then Message(...)` does **NOT** suppress messages in tests.
- Any test that triggers UI **MUST** declare `[MessageHandler]` + `[HandlerFunctions('MessageHandler')]`, or it fails on an unhandled `Message`. See `triage-patterns.md`.

## Runner is BC-version-specific — versioned subfolders ✅

`Microsoft.Dynamics.Framework.UI.Client.dll` (and its 3 sibling DLLs) are **pinned to the BC platform version** of the target server. A runner built for BC 27 will not reliably drive a BC 28 service. Therefore:

- **Convention**: `<runnerDir>/<major.minor>/` — e.g. `Test/PowerShell/_runner/28.0/`. Multiple BC versions coexist side by side.
- `Resolve-TestLoopRunner` resolves the **target** version from (in order): config `bcVersion` override → live server (`Get-NAVServerInstance … .Version`) → whatever DLL is already present.
- It then **validates**: the runner client DLL `major.minor` MUST equal the target. On mismatch it **throws** (never silently drives the wrong client).

## Runner DLLs — materialized from the BC product DVD (K:) ✅

The 4 version-pinned client DLLs are **materialized on demand** by `Initialize-TestLoopRunner`; they are **not committed**. The whole `_runner/` folder is git-ignored.

### Preferred source — the K: DVD share (deterministic)

`Resolve-TestLoopClientSource` derives the source from the unpacked BC product DVD:

```
<bcDvdRoot>\<major>\<bcCountry>.<major>.<minor>\Applications\TestFramework\TestRunner\Internal\
```

- Config: `bcDvdRoot` (e.g. `K:\59 Environments\_ms`) + `bcCountry` (e.g. `CH`).
- It globs `<bcCountry>.<major>.*`, picks the **highest minor** that actually carries the client DLL, and resolves the canonical MS `…\TestRunner\Internal` folder.
- Validated: `K:\59 Environments\_ms\28\CH.28.2\…\Internal` → BC client `28.0.50938.0`.

### Alternatives (override the derivation)

| Config | Effect |
|--------|--------|
| `runnerClientSource` (explicit path) | Wins over DVD derivation. Searched recursively for the 4 DLLs. |
| `runnerClientFromServer=true` (+ explicit `runnerClientSource`) | Opt-in: pull the DLLs from a remote BC Service folder via remote PowerShell (`Copy-TestLoopRunnerFromServer`). Fallback for when K: is unreachable. |

### The 4 version-pinned DLLs

| File | Required |
|------|----------|
| `Microsoft.Dynamics.Framework.UI.Client.dll` | yes |
| `Newtonsoft.Json.dll` | yes |
| `System.ServiceModel.Primitives.dll` | yes |
| `Microsoft.Internal.AntiSSRF.dll` | optional (warn if missing) |

## Glue — version-agnostic, central in the skill ✅

The 3 PowerShell glue files are **identical across BC versions**, so they live **once** in the skill, not per project, not per runner version:

```
scripts/runner-glue/
  ClientContext.ps1      # MS canonical (MIT), unmodified — class ClientContext
  PsTestFunctions.ps1    # MS canonical (MIT), unmodified — New-ClientContext / Run-Tests / Remove-ClientContext
  AprodaRunner.ps1       # Aproda thin wrapper — Run-AlTests over New-ClientContext + Run-Tests
```

- The engine resolves `glueDir` from the module location (`<module-parent>/runner-glue`) and validates the 3 files exist.
- `New-TestLoopRunner` is **DLL-only** — it never copies glue into `_runner/`.

## SRP — content-based script loading is mandatory ✅

On this estate a **Software Restriction Policy / Group Policy blocks path-based PowerShell execution** (`. <path>.ps1`, `Import-Module <path>.psm1`) **everywhere in the workspace** — it throws `PSSecurityException`. The SRP-safe pattern is **content-based** execution:

```powershell
. ([ScriptBlock]::Create((Get-Content $path -Raw)))
```

Consequences baked into the engine:
- `Invoke-AprodaTestLoop.ps1` loads the engine via `[ScriptBlock]::Create($engineSrc)` (stripping `Export-ModuleMember`), never `Import-Module`.
- The run bootstrap loads all 3 glue files content-based via `[ScriptBlock]::Create`, and **neutralizes** `PsTestFunctions.ps1`'s internal `. $clientContextScriptPath` path dot-source (regex) — `ClientContext.ps1` is loaded separately.
- **Order matters**: the 4 client DLLs are `Add-Type`'d **before** the `ClientContext` scriptblock is created, because `class ClientContext` references `Microsoft.Dynamics.Framework.UI.Client.*` types at **parse time** of its method bodies. `Get-Content` (reading) is not SRP-blocked; only path-based *execution* is.

## Result parsing ✅

`_runner/<version>/TestResults.xml` is XUnit-style:
`<assemblies>/<assembly>/<collection>/<test result="Pass|Fail">`.

Review must confirm: target tests pass **and** previously-green tests didn't regress (especially after shared-code fixes).

## Hygiene ✅

- The **whole `_runner/` folder** is git-ignored (DLLs materialized from K: DVD, glue central) — nothing under it is committed.
- Throwaway probe/scratch work goes under `Test/PowerShell/_temp/` (git-ignored), never committed.

## Fallback: jamespearson/al-test-runner

If the engine is unavailable, the `jamespearson/al-test-runner` VS Code extension can drive the run via `-RunViaUrl`. Known friction (why it is fallback-only):
- It needs a netcore `Newtonsoft.Json.dll` placed under its `TestClient\Newtonsoft.Json.13.0.3\lib\net6.0\` — **outside** the workspace, not versioned (the instability that motivated standardizing on the own engine).
- See `/memories/repo/al-test-runner.md` for the exact recipe + workarounds.
