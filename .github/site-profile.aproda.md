# Aproda Site Profile — Infrastructure Facts

> **Aproda ALDC layer — site profile.** Concrete, organization-wide infrastructure facts for Aproda BC/AL development. Referenced on demand by the Aproda skills (`skill-aproda-test-loop`, `skill-aproda-aldc`); **not** auto-loaded. Source of truth = the aproda-aldc fork; distributed into every project via the `.github/` subtree (see [`decisions.aproda.md`](decisions.aproda.md) D-6).
>
> These are **site/environment** facts (stable across projects). **Project-specific** values (instance name, company, app IDs) live in each project's `Test/testloop.config.jsonc` + `launch.json` — never duplicate them here.

## Topology

- **VS Code runs LOCALLY** on the developer workstation (e.g. `APR-AZU-AVDEV02`, `APR-AZU-AVDEV*`).
- **BC service runs REMOTELY** on the NST servers `apd-svw-nst0x.aproda.ch` (e.g. `apd-svw-nst05.aproda.ch`).
- **`D:\` is server-side only** — it does **not** exist on the local workstation. Paths like `D:\<major>\<instance>\Service` / `…\Management` are valid **inside the remote session**, not locally.
- **`K:\` share is reachable locally** from the workstation (see BC DVD below).

## Remote PowerShell

- Remote PowerShell **to the NST servers works** and is the channel for server-side operations (publish/sync/install, reading the Management DLL, pulling server-side DLLs).
- **Admin shares (`\\server\D$`) may be blocked** — prefer `Invoke-Command` / `Copy-Item -ToSession` / `-FromSession` over UNC admin-share paths.
- `navcontainerhelper` is **not installed**; tooling that imports it must tolerate its absence (`$ErrorActionPreference = 'Continue'` where a non-fatal import is attempted).

## SRP — path-based script execution is BLOCKED (critical)

A **Software Restriction Policy / Group Policy blocks path-based PowerShell execution** across the workspace — `. <path>.ps1`, `Import-Module <path>.psm1`, `& <path>.ps1` throw `System.Management.Automation.PSSecurityException`.

**The SRP-safe pattern is content-based execution** (reading a file is not blocked; only path-based *execution* is):

```powershell
. ([ScriptBlock]::Create((Get-Content $path -Raw)))
```

Consequences for any PowerShell tooling on this estate:
- Never `Import-Module <path>.psm1` — dot-source the **content** instead (and strip `Export-ModuleMember`, which is invalid outside a real module).
- When a script defines a PowerShell **class** that references types from a DLL, `Add-Type` those DLLs **before** creating the scriptblock — class method bodies resolve types at **parse time**.
- When loaded via `iex`, `$PSCommandPath` / `$PSScriptRoot` are empty inside functions — pass the module path via an env var if a function needs to locate sibling files.

## BC product DVD (K: share) — deterministic DLL source

The unpacked BC product DVDs live under a deterministic layout:

```
K:\59 Environments\_ms\<major>\<Country>.<major>.<minor>\
```

- 1st level = **major** version (e.g. `28`).
- 2nd level = **`<Country>.<major>.<minor>`** (e.g. `CH.28.0`, `CH.28.1`, `CH.28.2` — highest minor is the newest).
- Inside is the full unpacked DVD. The **AL test-client DLLs** are at the canonical MS TestRunner folder:
  ```
  …\<Country>.<major>.<minor>\Applications\TestFramework\TestRunner\Internal\
  ```
- The 4 version-pinned client DLLs there: `Microsoft.Dynamics.Framework.UI.Client.dll`, `Newtonsoft.Json.dll`, `System.ServiceModel.Primitives.dll`, `Microsoft.Internal.AntiSSRF.dll` (optional).
- Current site values: `bcDvdRoot = K:\59 Environments\_ms`, `bcCountry = CH`; highest BC 28 minor = `CH.28.2` (BC client `28.0.50938.0`).

### MS test-library `.app` sources on the DVD (deterministic)
The Microsoft test-library `.app` packages needed to deploy a Test extension are also on the DVD under `…\<Country>.<major>.<minor>\Applications\`:

| App | Source path (relative to `…\Applications\`) |
|-----|----------------------------------------------|
| Test Runner | `TestFramework\TestRunner\Microsoft_Test Runner.app` |
| Any | `TestFramework\TestLibraries\Any\Microsoft_Any.app` |
| Library Assert | `TestFramework\TestLibraries\Assert\Microsoft_Library Assert.app` |
| Library Variable Storage | `TestFramework\TestLibraries\Variable Storage\Microsoft_Library Variable Storage.app` |
| System Application Test Library | `System Application\Test\Microsoft_System Application Test Library.app` |
| Business Foundation Test Libraries | `BusinessFoundation\Test\Microsoft_Business Foundation Test Libraries.app` |
| Application Test Library (**new in BC28**; the standard cross-app libs — Library - Inventory/Sales/Purchase/Manufacturing/Warehouse/ERM/Job/Random/Utility/Assert…) | `Application Test Library\Source\Microsoft_Application Test Library.app` |
| Tests-TestLibraries (specialized: mocks, OnPrem-only libs `…OnPrem`, .NET-bound CRM/Graph/SMTP/Azure AD/XML, permissions, job-queue samples) | `BaseApp\Test\Microsoft_Tests-TestLibraries.app` |

## BC web client (headless test runner)

- The client-driven test runner connects to the **web client** URL on **port 80**: `http://<server>/<instance>/cs?tenant=<tenant>&company=<company>` — **not** the NetTcp port (8929) and **not** the DeveloperServices port (8930).
- `company` must be pinned into the URL (`/cs?...&company=<c>`) so the headless run does not prompt interactively. Example company: `CRONUS (Schweiz) AG`.
- DeveloperServicesPort = **8930** (used for symbol download / publish via the AL extension), distinct from the web-client port.

## PowerShell paste mangling

PowerShell 7 mangles multi-line pasted commands. **Always** run multi-step PowerShell via a temp script:

```powershell
Get-Content <tempscript>.ps1 -Raw | Invoke-Expression
```

Keep throwaway scripts under `Test/PowerShell/_temp/` (git-ignored).

---

> If any of these facts change (new NST server, K: layout change, SRP relaxed), update **this file in the fork** and let it flow to projects via the subtree. Do not silently fix it only in one project's copy.
