---
name: skill-aproda-fkh
description: "Fkh transport and target resolution for Business Central development containers. Use when a selected OnPrem launch.json configuration targets an HTTPS *.cloudapp.azure.com endpoint, or when listing, sorting, publishing, or inspecting apps through Freddy's Kubernetes Helper (fkh). Aproda custom skill."
---

# Skill: Fkh Transport and Target Resolution

> **Aproda custom skill** — reusable Fkh capability used by [`skill-aproda-deploy-run-verify`](../skill-aproda-deploy-run-verify/SKILL.md). It owns Fkh target discovery and app transport; it does not own the Build → Deploy → Run → Review lifecycle.
> **Status: VALIDATED**, including through `skill-aproda-deploy-run-verify`'s engine entry point (2026-09-12, D-36): Fkh container discovery, local app sorting, publish, sync, install/upgrade, installed-state inspection, and a `UserPassword`-credentialed test run (26/26 passed) were all exercised live against `flobi-wan-kenobi-straub-dev-deployment`. D-39 makes Dev Endpoint publishing the default and supersedes the former Global-scope same-version removal path. `fkh getappinfo`'s JSON shape was captured live (2026-09-13): `{ container, tenant, apps: [ { AppId, Name, Publisher, Version, Dependencies, ExtensionType, Scope, IsInstalled, IsPublished, SyncState, NeedsUpgrade } ] }` — the engine matches the entry by version and checks `IsInstalled`/`SyncState`.

## When to Load

Load this skill when:

- The user selected an `OnPrem` `launch.json` configuration whose `server` is HTTPS and ends in `.cloudapp.azure.com`.
- An app must be listed, sorted by dependencies, published, synchronized, installed, or inspected through `fkh`.
- A Deploy-Run-Verify workflow has classified its selected target as Fkh.

Do not use this skill for an NST endpoint reached with Remote PowerShell and the NAV Management DLL. That remains the ASINST adapter of `skill-aproda-deploy-run-verify`.

## Target Resolution

Use the user-selected `launch.json` configuration. For the initial adapter selection, classify it as an Fkh candidate only when all three conditions hold:

1. `environmentType` is `OnPrem`.
2. `server` starts with `https://`.
3. The normalized server hostname ends in `.cloudapp.azure.com`.

For an Fkh candidate, verify the classification before any write:

```powershell
fkh listcontainers --all --asJson --backendUrl $backendUrl
```

Match the normalized launch server hostname exactly to the container's web-client hostname. For `publishapp`, `getappinfo`, and `invokescript`, use the matched container `appLabel` as `--name`; the Kubernetes deployment `name` returned by `listcontainers` is not accepted by those operations. If no container matches, multiple containers match, or the container is not running, stop and ask the user. Never infer the Fkh name by removing `-deployment` from a launch configuration name.

### Backend URL Resolution

The Fkh backend URL is workstation configuration. On Windows, resolve it from the VS Code user settings key `fkh.backendUrl` in `%APPDATA%\Code\User\settings.json`; do not commit the endpoint to an app repository or print it in command output.

```powershell
function Get-FkhBackendUrl {
  $settingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
  if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw 'VS Code user settings were not found.'
  }

  $settingsContent = Get-Content -LiteralPath $settingsPath -Raw
  $backendUrlMatch = [regex]::Match($settingsContent, '"fkh\.backendUrl"\s*:\s*"(?<value>[^"]+)"')
  if (-not $backendUrlMatch.Success) {
    throw 'The VS Code user setting fkh.backendUrl is not configured.'
  }

  return $backendUrlMatch.Groups['value'].Value
}
```

Pass the resolved value explicitly as `--backendUrl` for every Fkh command. This makes the target selection deterministic even when the Fkh client itself still has its placeholder default.

### Local Authentication

`--useOIDC` is only for GitHub Actions or Azure DevOps environments that expose their OIDC variables. It disables all local fallback authentication and must not be used from a developer workstation. For an interactive workstation, let Fkh use the active `gh auth` session (or pass `--ghUser` when a specific signed-in account is required); never print or persist its token.

### AL CLI Prerequisite

Fkh's dependency sorter calls `al GetPackageManifest`. Before applying its AL-Go overrides, ensure that the official Business Central AL CLI is available. Run the bundled script with the estate's SRP-safe content loading; it installs `Microsoft.Dynamics.BusinessCentral.Development.Tools` globally only when `al` is absent.

```powershell
$ensureAlCliScript = Join-Path $PSScriptRoot 'scripts\Ensure-BusinessCentralAlCli.ps1'
& ([ScriptBlock]::Create((Get-Content -LiteralPath $ensureAlCliScript -Raw)))
```

The script returns the resolved `al` command path. It does not modify project files or persist environment-specific configuration.

## Publish a Dependency-Ordered App Set

`fkh publishapp` accepts one `.app` file. Resolve order locally, then publish sequentially and stop at the first error. Fkh's bundled AL-Go override supplies the canonical sorter, which uses `al GetPackageManifest`; therefore the official `al` CLI must be available in `PATH`.

```powershell
$ErrorActionPreference = 'Stop'
$backendUrl = Get-FkhBackendUrl
$ensureAlCliScript = Join-Path $PSScriptRoot 'scripts\Ensure-BusinessCentralAlCli.ps1'
& ([ScriptBlock]::Create((Get-Content -LiteralPath $ensureAlCliScript -Raw)))
$container = '<appLabel from a verified fkh listcontainers match>'
$temporaryDirectory = Join-Path $env:TEMP ('fkh-sortapps-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null
try {
  fkh applyALGoOverrides --output $temporaryDirectory
  if ($LASTEXITCODE -ne 0) { throw "fkh applyALGoOverrides failed with exit code $LASTEXITCODE" }

  $sortScript = Join-Path $temporaryDirectory 'sortapps.ps1'
  $appFiles = @(Get-ChildItem '..\.installapps' -Filter '*.app' -File | Select-Object -ExpandProperty FullName)
  $sortResult = & ([scriptblock]::Create((Get-Content -LiteralPath $sortScript -Raw))) -appFiles $appFiles
  if ($sortResult.UnknownDependencies.Count -gt 0) {
    throw ('Unresolved dependencies: ' + ($sortResult.UnknownDependencies -join '; '))
  }

  foreach ($appFile in $sortResult.SortedApps) {
    fkh publishapp --name $container --appFile $appFile --devScope --syncMode Add --sync --install --backendUrl $backendUrl
    if ($LASTEXITCODE -ne 0) { throw "Publish failed: $appFile" }
  }
}
finally {
  Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
```

### FKH Deployment Scope

**FKH deployments use the Business Central Dev Endpoint (`--devScope`) by default, without scope confirmation. Use `fkh publishapp --devScope`.** Global-scope publishing is allowed only when explicitly requested by the user.

The default Dev Endpoint schema mode is `synchronize` (`--syncMode Add`). Use `--syncMode ForceSync` only when a destructive schema change requires it. Inform the user briefly when using `ForceSync`; explicit confirmation is not required. Do not hide errors with a bulk parallel publish: dependency order and fail-fast behavior are required.

Existing Global-scoped apps require an explicitly approved one-time migration before they can be republished in Dev scope. Do not remove or migrate them automatically.

For ASINST and explicitly requested FKH Global-scope same-version recovery, including reverse dependency removal and normal dependency publish/ForceSync/install, load [`redeploy-recovery.md`](../skill-aproda-deploy-run-verify/references/redeploy-recovery.md). This recovery is never the automatic fallback for Dev Endpoint publishing.

## Inspect State

After publishing, inspect the target app explicitly:

```powershell
fkh getappinfo --name $container --appName '<app name or wildcard>' --asJson --backendUrl $backendUrl
```

Confirm the required version is `Published`, `Installed`, and `Synced` before considering deployment complete.

## Credential Store (D-37)

For a `UserPassword` BC target, `scripts/FkhCredentialStore.ps1` caches the credential DPAPI-protected (current user + machine only) under `%LOCALAPPDATA%\AprodaFkh\credentials\<hostname>.cred.xml` — one file per Fkh container hostname, so different containers with the same or different passwords never collide. Load it content-safe like any other script here (`[ScriptBlock]::Create((Get-Content -Raw))`); it exposes `Get-FkhStoredCredential`, `Save-FkhCredential`, `Remove-FkhStoredCredential`. `skill-aproda-deploy-run-verify`'s engine consumes it (check store → fall back to `Get-Credential` → opt-in save only after a proven-working connection); any ad-hoc Fkh script should reuse the same functions instead of hardcoding credentials.

## Capability Boundary

| Capability | Status |
|---|---|
| Container discovery and launch-target verification | Validated |
| Dependency sorting via Fkh AL-Go overrides and `al` | Validated |
| Publish, sync, install/upgrade, and state inspection | Validated |
| Test execution inside an Fkh container | Validated, including through the DRV engine entry point (26/26, D-36) |
| Test-result retrieval and parsing from an Fkh container | Validated, including through the DRV engine entry point |

The shared runner must use the web-client URL, an explicit test extension ID and test-codeunit range, and SRP-safe content loading through `[ScriptBlock]::Create((Get-Content -Raw))`. Parse the generated XUnit-style XML before reporting a green runtime result.

## Constraints

- `skill-aproda-fkh` owns Fkh mechanics only. The lifecycle and its HITL environment-selection gate remain in `skill-aproda-deploy-run-verify`.
- Use a verified full Fkh container name; short aliases are not portable across Fkh client contexts.
- Keep backend URLs, tokens, and OIDC credentials out of committed configuration and output.