<#
.SYNOPSIS
  Aproda Deploy-Run-Verify engine — Build -> Deploy -> Run for AL BC (OnPrem NST via ASINST,
  or an AKS container via Fkh). IMMUTABLE TEMPLATE. Do NOT edit per project; drive it via
  deploy-run-verify.config.jsonc.
  Derived from the proven Test/PowerShell/_Cycle.ps1 + _RunTests.ps1 (Audit Trail 26/26).
.NOTES
    E-010 (D-53): one route chain per step for both adapters - altool CLI first, legacy route second
    (build: alc.exe, deploy: direct Dev Endpoint POST, tests: web-client runner). The Management DLL
    (ASINST) is used only to read state and for the one-time cleanup. Fkh is used only to verify the
    target and to read the app state.
#>

Set-StrictMode -Version Latest

# Initialized up front: Set-StrictMode throws on a never-assigned Script-scope variable,
# and Get-DeployRunVerifyCredential's cache check reads this before any UserPassword run.
$Script:DeployRunVerifyCredential = $null
$Script:DeployRunVerifyCredentialFromStore = $false

# Per-run route state (E-010); Reset-DeployRunVerifyRunState re-initializes it at the start of each run.
$Script:DeployRunVerifyAlToolInfo = $null
$Script:DeployRunVerifyAlToolCaps = $null
$Script:DeployRunVerifyPinnedLegacy = @{}
$Script:DeployRunVerifyFallbacks = [System.Collections.Generic.List[string]]::new()
$Script:DeployRunVerifyRoutes = [ordered]@{
    Build  = [pscustomobject]@{ Route = 'n/a'; Reason = '' }
    Deploy = [pscustomobject]@{ Route = 'n/a'; Reason = '' }
    Tests  = [pscustomobject]@{ Route = 'n/a'; Reason = '' }
}

# Eagerly load skill-aproda-fkh's credential-store functions (Get-/Save-/Remove-FkhStored
# Credential) at module TOP LEVEL, content-safe (SRP-exempt). Doing this from inside a
# function would only bind them into that function's own scope, gone the instant it
# returns — dot-sourcing must happen at the scope where callers need to see the result.
# Optional dependency: a pure-ASINST setup without skill-aproda-fkh just warns and
# UserPassword runs (Fkh-only) fall back to prompting via Get-Credential every time.
try {
    $engineDirForFkhStore = $null
    if ($env:APRODA_DEPLOY_RUN_VERIFY_MODULE) { $engineDirForFkhStore = Split-Path -Parent $env:APRODA_DEPLOY_RUN_VERIFY_MODULE }
    elseif ($PSScriptRoot) { $engineDirForFkhStore = $PSScriptRoot }
    if ($engineDirForFkhStore) {
        $fkhStoreScript = Join-Path (Split-Path -Parent (Split-Path -Parent $engineDirForFkhStore)) 'skill-aproda-fkh\scripts\FkhCredentialStore.ps1'
        if (Test-Path -LiteralPath $fkhStoreScript) {
            . ([ScriptBlock]::Create((Get-Content -LiteralPath $fkhStoreScript -Raw)))
        }
    }
}
catch {
    Write-Warning "Fkh credential store unavailable ($($_.Exception.Message)) — UserPassword runs will prompt every time."
}

# Shared AL target library (E-010, D-53): the only source of the DRV target (aldc.local.json + launch.json).
# Loaded content-based at module top level for the same scope reason as the Fkh store; a missing
# sibling skill is reported when Resolve-DeployRunVerifyConfig runs, not at load.
$Script:DeployRunVerifyAlTargetLoadError = 'AL_MCP_SKILL_MISSING: cannot locate the engine dir to find skill-aproda-al-mcp. Set $env:APRODA_DEPLOY_RUN_VERIFY_MODULE to the AprodaDeployRunVerify.psm1 path.'
try {
    $engineDirForAlTarget = $null
    if ($env:APRODA_DEPLOY_RUN_VERIFY_MODULE) { $engineDirForAlTarget = Split-Path -Parent $env:APRODA_DEPLOY_RUN_VERIFY_MODULE }
    elseif ($PSScriptRoot) { $engineDirForAlTarget = $PSScriptRoot }
    if ($engineDirForAlTarget) {
        $alTargetScript = Join-Path (Split-Path -Parent (Split-Path -Parent $engineDirForAlTarget)) 'skill-aproda-al-mcp\scripts\AprodaAlTarget.ps1'
        if (Test-Path -LiteralPath $alTargetScript) {
            . ([ScriptBlock]::Create((Get-Content -LiteralPath $alTargetScript -Raw)))
            $Script:DeployRunVerifyAlTargetLoadError = $null
        }
        else {
            $Script:DeployRunVerifyAlTargetLoadError = "AL_MCP_SKILL_MISSING: $alTargetScript not found. skill-aproda-al-mcp ships together with this skill (skills/skill-aproda-*/**)."
        }
    }
}
catch {
    $Script:DeployRunVerifyAlTargetLoadError = "AL_MCP_SKILL_MISSING: skill-aproda-al-mcp could not be loaded ($($_.Exception.Message))"
}

# ---------------------------------------------------------------------------
# Adapter classification (D-26): the only hostname-based routing decision. Https +
# *.cloudapp.azure.com => Fkh (AKS container transport); everything else => the
# established ASINST path (Remote PowerShell + NAV Management DLL against an NST server).
# Deliberately conservative — an unmatched Fkh candidate must stop for HITL, never fall
# through to ASINST (skill-aproda-fkh owns that verification against `fkh listcontainers`).
# ---------------------------------------------------------------------------
function Get-DeployRunVerifyAdapter {
    param([Parameter(Mandatory)]$Cfg)
    if ($Cfg.scheme -eq 'https' -and $Cfg.server -match '(?i)\.cloudapp\.azure\.com$') { return 'Fkh' }
    return 'Asinst'
}

# ---------------------------------------------------------------------------
# Config resolution: merge deploy-run-verify.config.jsonc + the target selected in
# aldc.local.json (resolved via launch.json) + each app.json. -BuildOnly lets a run without a
# usable target continue with adapter 'none' (E-010 spec 5.2).
# ---------------------------------------------------------------------------
function Resolve-DeployRunVerifyConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath, [switch]$BuildOnly)

    if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath" }
    $cfgDir = Split-Path -Parent (Resolve-Path $ConfigPath)
    $cfgFile = (Resolve-Path $ConfigPath).Path

    # Strip // and /* */ comments, then parse. Lookbehind keeps URL '://' intact.
    $raw = Get-Content $ConfigPath -Raw
    $raw = [regex]::Replace($raw, '(?m)(?<!:)//.*?$', '')
    $raw = [regex]::Replace($raw, '(?s)/\*.*?\*/', '')
    $cfg = $raw | ConvertFrom-Json

    # --- Migration check: the target moved to aldc.local.json (E-010, D-53). fkhSyncMode is NOT a target key. ---
    $migrationRequired = @()
    $migrationObsolete = @()
    foreach ($key in @('launchConfig', 'server', 'serverInstance', 'tenant', 'scheme', 'authentication')) {
        $property = $cfg.PSObject.Properties[$key]
        if ($null -eq $property) { continue }
        $value = $property.Value
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) -or ($value -is [bool] -and -not $value)) { $migrationObsolete += $key }
        else { $migrationRequired += $key }
    }
    if ($migrationRequired.Count -gt 0) {
        throw ("CONFIG_MIGRATION_REQUIRED: $($migrationRequired -join ',')" + [Environment]::NewLine +
            "Target selection moved to aldc.local.json (E-010). Move the value there (Set-AprodaAlLocalSelection) and delete these lines from $cfgFile.")
    }
    if ($migrationObsolete.Count -gt 0) {
        Write-Warning "CONFIG_OBSOLETE_KEY: $($migrationObsolete -join ',') (empty) in $cfgFile - delete these lines in the next commit."
    }

    # --- Target from aldc.local.json + launch.json (library: skill-aproda-al-mcp) ---
    if (-not (Get-Command Get-AprodaAlLocalSelection -ErrorAction SilentlyContinue)) {
        if ($Script:DeployRunVerifyAlTargetLoadError) { throw $Script:DeployRunVerifyAlTargetLoadError }
        throw 'AL_MCP_SKILL_MISSING: the AL target library (skill-aproda-al-mcp) is not loaded.'
    }
    $repoRoot = $null
    $repoRootError = $null
    try { $repoRoot = Get-AprodaAlRepositoryRoot -StartPath $cfgDir }
    catch { $repoRootError = $_.Exception.Message }
    if ($repoRootError -and -not $BuildOnly) { throw $repoRootError }

    $selection = $null
    if ($repoRoot) { $selection = Get-AprodaAlLocalSelection -RepositoryRoot $repoRoot }
    $targetReady = $false
    if ($selection -and $selection.State -eq 'configured') {
        $blocking = @($selection.Issues)
        if ($blocking.Count -eq 0) { $targetReady = $true }
        elseif ($BuildOnly) {
            Write-Warning "TARGET_BLOCKED: $((@($blocking | ForEach-Object { $_.code }) -join ',')) (ignored: build-only)"
        }
        else {
            $blockedLines = @("TARGET_BLOCKED: $((@($blocking | ForEach-Object { $_.code }) -join ','))") + @($blocking | ForEach-Object { "$($_.code): $($_.message)" })
            throw ($blockedLines -join [Environment]::NewLine)
        }
    }
    elseif (-not $BuildOnly) {
        $state = [string]$selection.State
        $reasonText = if ($selection.Reason) { [string]$selection.Reason } elseif ($selection.Path) { "no usable AL target selection in $($selection.Path)" } else { 'no AL target selection' }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("TARGET_SELECTION_$($state.ToUpperInvariant()): $reasonText")
        $lines.Add('Available configurations (launchProject | name | server | serverInstance | authentication):')
        $available = @(Get-AprodaAlLaunchConfigurations -RepositoryRoot $repoRoot)
        if ($available.Count -eq 0) { $lines.Add("  (no 'server' configuration found in any AL project's launch.json)") }
        foreach ($entry in $available) { $lines.Add("  $($entry.LaunchProject) | $($entry.Name) | $($entry.Server) | $($entry.ServerInstance) | $($entry.Authentication)") }
        if ($state -eq 'noToolkit') { $lines.Add('No aldc.yaml was found under the repository root, so a selection cannot be stored.') }
        else { $lines.Add('Ask the user which configuration to use, then write it with Set-AprodaAlLocalSelection. A selection is not the environment acknowledgement.') }
        throw ($lines -join [Environment]::NewLine)
    }

    if ($targetReady) {
        $launch = $selection.ResolvedLaunch
        # Single consumer of the library's bundle rule; the bundle is kept for later routes (4b).
        $cfg | Add-Member targetBundle (Get-AprodaAlTargetBundle -Selection $selection) -Force
        # server stays the HOST only: credential key, remote sessions and the adapter rule use it.
        $cfg | Add-Member server $launch.host -Force
        $cfg | Add-Member scheme $launch.scheme -Force
        $cfg | Add-Member serverInstance $launch.serverInstance -Force
        $cfg | Add-Member tenant $launch.tenant -Force
        $cfg | Add-Member authentication $launch.authentication -Force
        $cfg | Add-Member port $launch.port -Force
        $cfg | Add-Member dependencyPublishingOption $launch.dependencyPublishingOption -Force
        $cfg | Add-Member launchProject $selection.Target.LaunchProject -Force
        $cfg | Add-Member launchConfig $selection.Target.LaunchConfig -Force
        $cfg | Add-Member adapter (Get-DeployRunVerifyAdapter -Cfg $cfg) -Force
    }
    else {
        foreach ($name in 'targetBundle', 'server', 'scheme', 'serverInstance', 'tenant', 'authentication', 'port', 'dependencyPublishingOption', 'launchProject', 'launchConfig') {
            $cfg | Add-Member $name $null -Force
        }
        $cfg | Add-Member adapter 'none' -Force
        Write-Host 'TARGET: none (build-only)'
    }

    # --- Glue dir (central, ships with the skill): <engine module dir>\runner-glue ---
    # When the engine is dot-loaded via iex, $PSScriptRoot is empty inside functions,
    # so prefer the module-path hint the entry point always sets.
    $glueBase = $env:APRODA_DEPLOY_RUN_VERIFY_MODULE
    if ($glueBase) { $glueBase = Split-Path -Parent $glueBase } elseif ($PSScriptRoot) { $glueBase = $PSScriptRoot }
    if (-not $glueBase) { throw "Cannot locate the engine dir to resolve runner-glue. Set `$env:APRODA_DEPLOY_RUN_VERIFY_MODULE to the AprodaDeployRunVerify.psm1 path." }
    $glueDir = Join-Path $glueBase 'runner-glue'
    foreach ($g in 'ClientContext.ps1', 'PsTestFunctions.ps1', 'AprodaRunner.ps1') {
        if (-not (Test-Path (Join-Path $glueDir $g))) { throw "Runner glue missing: $glueDir\$g (ships centrally with the skill)." }
    }
    $cfg | Add-Member glueDir "$glueDir" -Force

    # --- ServiceUrl (web client; scheme follows the adapter — http for ASINST/NST, https
    # for Fkh/AKS) ---
    # Company is required for a deterministic headless run; if set, pin it into the URL
    # (proven shape: /cs?tenant=<t>&company=<c>). Empty company falls back to /cs/.
    if (-not ($cfg.PSObject.Properties.Name -contains 'companyName')) { $cfg | Add-Member companyName '' -Force }
    if ($cfg.adapter -eq 'none') {
        $cfg | Add-Member serviceUrl $null -Force
    }
    elseif (-not [string]::IsNullOrWhiteSpace($cfg.companyName)) {
        $cfg | Add-Member serviceUrl ("{0}://{1}/{2}/cs?tenant={3}&company={4}" -f $cfg.scheme, $cfg.server, $cfg.serverInstance, $cfg.tenant, [uri]::EscapeDataString($cfg.companyName)) -Force
    }
    else {
        $cfg | Add-Member serviceUrl ("{0}://{1}/{2}/cs/" -f $cfg.scheme, $cfg.server, $cfg.serverInstance) -Force
    }

    # --- alc.exe auto-detect ---
    if ([string]::IsNullOrWhiteSpace($cfg.alcPath)) {
        $extRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
        $alc = Get-ChildItem $extRoot -Directory -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'bin\win32\alc.exe' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $alc) { throw "alc.exe not found — set alcPath in config." }
        $cfg.alcPath = $alc
    }

    # --- Resolve apps in dependency order ---
    if (-not $cfg.appsInOrder -or @($cfg.appsInOrder).Count -eq 0) { throw "appsInOrder is required (project dirs, dependency order, test app last)." }
    $apps = foreach ($rel in $cfg.appsInOrder) {
        $proj = Resolve-Path (Join-Path $cfgDir $rel)
        $aj = Get-Content (Join-Path $proj 'app.json') -Raw | ConvertFrom-Json
        [pscustomobject]@{
            ProjectDir = "$proj"
            Name       = $aj.name
            Version    = $aj.version
            Publisher  = $aj.publisher
            Id         = $aj.id
            IdRanges   = $aj.idRanges
            AppFile    = Join-Path $proj ("{0}_{1}_{2}.app" -f $aj.publisher, $aj.name, $aj.version)
        }
    }
    $cfg | Add-Member apps $apps -Force
    $testApp = $apps[-1]

    # Schema mode for BOTH adapters and both publish routes (D-39): Add -> Synchronize / synchronize,
    # ForceSync -> ForceSync / forcesync (destructive schema change; the agent informs the user briefly).
    if (-not ($cfg.PSObject.Properties.Name -contains 'fkhSyncMode') -or [string]::IsNullOrWhiteSpace($cfg.fkhSyncMode)) {
        $cfg | Add-Member fkhSyncMode 'Add' -Force
    }
    if ($cfg.fkhSyncMode -notin @('Add', 'ForceSync')) {
        throw "fkhSyncMode must be 'Add' or 'ForceSync'."
    }

    # --- Test extension id + codeunit range ---
    $cfg | Add-Member testExtensionId $testApp.Id -Force
    if ([string]::IsNullOrWhiteSpace($cfg.testCodeunitRange)) {
        $r = $testApp.IdRanges | Select-Object -First 1
        if ($r) { $cfg.testCodeunitRange = ("{0}..{1}" -f $r.from, $r.to) } else { throw "testCodeunitRange unresolved." }
    }
    # Optional explicit BC platform version override (e.g. "28.0"); empty = derive from live server.
    if (-not ($cfg.PSObject.Properties.Name -contains 'bcVersion')) { $cfg | Add-Member bcVersion '' -Force }
    # Source folder holding the 4 version-pinned BC client DLLs (Client, AntiSSRF, Newtonsoft,
    # ServiceModel.Primitives) — the BC Service folder works (next to the Server .exe), e.g.
    # "\\apd-svw-nst05\D$\28\<inst>\Service". Used by Initialize-DeployRunVerifyRunner to materialize
    # _runner/<ver>/ on demand.
    if (-not ($cfg.PSObject.Properties.Name -contains 'runnerClientSource')) { $cfg | Add-Member runnerClientSource '' -Force }
    # When the runner source lives ON the (remote) BC server and is only reachable via remote PS
    # (admin shares blocked) — same topology as deploy's mgmtDllPath — set this true and point
    # runnerClientSource at a SERVER-SIDE path (e.g. "D:\28\<inst>\Service"). DLLs are pulled
    # via Copy-Item -FromSession. Default false = treat runnerClientSource as a local/UNC path.
    if (-not ($cfg.PSObject.Properties.Name -contains 'runnerClientFromServer')) { $cfg | Add-Member runnerClientFromServer $false -Force }
    # PREFERRED (Aproda): derive runnerClientSource from the BC product-DVD share instead of
    # hardcoding it. The 4 client DLLs live deterministically under the MS TestRunner folder:
    #   <bcDvdRoot>\<major>\<bcCountry>.<major>.<minor>\Applications\TestFramework\TestRunner\Internal
    # e.g. K:\59 Environments\_ms\28\CH.28.2\Applications\TestFramework\TestRunner\Internal.
    # Set bcDvdRoot (+ bcCountry) once per site; the engine globs the highest minor for <major>.
    # An explicit runnerClientSource always wins over this derivation.
    if (-not ($cfg.PSObject.Properties.Name -contains 'bcDvdRoot')) { $cfg | Add-Member bcDvdRoot '' -Force }
    if (-not ($cfg.PSObject.Properties.Name -contains 'bcCountry')) { $cfg | Add-Member bcCountry '' -Force }
    # runnerDirFull is the BASE folder; the actual runner is a version subfolder (see Resolve-DeployRunVerifyRunner).
    $runnerBase = Join-Path $cfgDir $cfg.runnerDir
    if (-not (Test-Path $runnerBase)) { New-Item -ItemType Directory $runnerBase -Force | Out-Null }
    $cfg | Add-Member runnerDirFull ("$(Resolve-Path $runnerBase)") -Force
    return $cfg
}

# ---------------------------------------------------------------------------
# Runner versioning: runner client DLLs are BC-platform-version-specific.
# Convention: <runnerDir>/<major.minor>/ (e.g. _runner/28.0/). A flat
# <runnerDir> with DLLs is still accepted (legacy) with a migrate-warning.
# ---------------------------------------------------------------------------
function ConvertTo-DeployRunVerifyMajorMinor {
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    if ($Version -match '^(\d+)\.(\d+)') { return "$($Matches[1]).$($Matches[2])" }
    return $null
}

function ConvertTo-DeployRunVerifyMajor {
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    if ($Version -match '^(\d+)(\.|$)') { return $Matches[1] }
    return $null
}

function Get-DeployRunVerifyRunnerVersion {
    # Reads the BC client DLL ProductVersion present in a runner dir (or $null).
    param([Parameter(Mandatory)][string]$Dir)
    $dll = Join-Path $Dir 'Microsoft.Dynamics.Framework.UI.Client.dll'
    if (-not (Test-Path $dll)) { return $null }
    return (Get-Item $dll).VersionInfo.ProductVersion
}

function Get-DeployRunVerifyServerVersion {
    # Live BC platform version via a short remote session (or $null if unreachable).
    # Fkh/AKS targets have no Remote-PS/Management-DLL surface — rely on config bcVersion.
    param([Parameter(Mandatory)]$Cfg)
    if ($Cfg.adapter -eq 'Fkh') { return $null }
    if ([string]::IsNullOrWhiteSpace($Cfg.mgmtDllPath)) { return $null }
    try {
        $session = New-PSSession -ComputerName $Cfg.server -ErrorAction Stop
        try {
            $v = Invoke-Command -Session $session -ScriptBlock {
                param($mgmt, $si)
                Import-Module $mgmt -ErrorAction Stop
                (Get-NAVServerInstance -ServerInstance $si).Version
            } -ArgumentList $Cfg.mgmtDllPath, $Cfg.serverInstance
            return [string]$v
        }
        finally { Remove-PSSession $session }
    }
    catch { return $null }
}

function Resolve-DeployRunVerifyRunner {
    # Returns the runner dir to use; validates client DLL major == target BC major. The client DLL
    # keeps minor 0 for a whole major while the server reports the CU minor (E-010 B-1).
    param([Parameter(Mandatory)]$Cfg)
    $base = $Cfg.runnerDirFull

    # Target BC version: explicit config override > live server > (none = trust whatever DLL is present).
    $targetFull = $Cfg.bcVersion
    $target = ConvertTo-DeployRunVerifyMajorMinor $targetFull
    if (-not $target) {
        $targetFull = Get-DeployRunVerifyServerVersion -Cfg $Cfg
        $target = ConvertTo-DeployRunVerifyMajorMinor $targetFull
    }

    # Candidates: versioned subfolder first, then flat base (legacy).
    $candidates = @()
    if ($target) { $candidates += (Join-Path $base $target) }
    $candidates += $base

    foreach ($dir in $candidates) {
        $dllVersion = Get-DeployRunVerifyRunnerVersion -Dir $dir
        $rv = ConvertTo-DeployRunVerifyMajorMinor $dllVersion
        if (-not $rv) { continue }
        if ($target -and (ConvertTo-DeployRunVerifyMajor $rv) -ne (ConvertTo-DeployRunVerifyMajor $target)) {
            throw ("Runner version mismatch: '$dir' carries BC client $dllVersion but the target environment is BC $targetFull (major must match). " +
                "Create a matching runner with: New-DeployRunVerifyRunner -RunnerBase '$base' -TargetVersion $target " +
                "-ClientFrom '<BC Service or client install folder>'.")
        }
        if ($target) { Write-Host "Runner client DLL $dllVersion accepted for target BC $targetFull (major match): $dir" }
        if ($dir -eq $base -and $target) {
            Write-Warning "Using legacy flat runner '$base' (BC $rv). Recommended: move its files to versioned subfolder '$base\$target'."
        }
        return $dir
    }
    throw ("No runner found under '$base'" + ($(if ($target) { " for BC $target" } else { '' })) +
        ". Materialize one with New-DeployRunVerifyRunner (see references/runner.md).")
}

function New-DeployRunVerifyRunner {
    # Materializes a versioned runner DIR with the 4 version-pinned BC client DLLs.
    # Glue (ClientContext.ps1 / PsTestFunctions.ps1 / AprodaRunner.ps1) is NOT copied here —
    # it ships centrally with the skill (scripts/runner-glue) and is resolved at run time.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunnerBase,    # the base _runner dir
        [Parameter(Mandatory)][string]$TargetVersion, # e.g. "28.0"
        [Parameter(Mandatory)][string]$ClientFrom     # folder holding the 4 BC client DLLs (Service / RTC install)
    )
    $tv = ConvertTo-DeployRunVerifyMajorMinor $TargetVersion
    if (-not $tv) { throw "TargetVersion '$TargetVersion' is not a major.minor version." }
    $dest = Join-Path $RunnerBase $tv
    New-Item -ItemType Directory $dest -Force | Out-Null

    $dlls = 'Microsoft.Dynamics.Framework.UI.Client.dll', 'Microsoft.Internal.AntiSSRF.dll',
    'Newtonsoft.Json.dll', 'System.ServiceModel.Primitives.dll'
    foreach ($d in $dlls) {
        $src = Get-ChildItem -Path $ClientFrom -Recurse -Filter $d -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $src) {
            # AntiSSRF is optional (PsTestFunctions loads it only if present); the rest are required.
            if ($d -eq 'Microsoft.Internal.AntiSSRF.dll') { Write-Warning "Optional DLL not found under '$ClientFrom': $d (continuing)"; continue }
            throw "DLL not found under '$ClientFrom': $d"
        }
        Copy-Item $src.FullName (Join-Path $dest $d) -Force
    }
    $rv = Get-DeployRunVerifyRunnerVersion -Dir $dest
    Write-Host "Runner materialized at '$dest' (BC client $rv)."
    return $dest
}

# ---------------------------------------------------------------------------
# Pull the 4 version-pinned client DLLs from a SERVER-SIDE folder via a remote PS
# session (same topology as deploy's mgmtDllPath: local VS Code, remote BC, admin
# shares blocked but remote-PSH works). Materializes into <runnerBase>/<target>/.
# ---------------------------------------------------------------------------
function Copy-DeployRunVerifyRunnerFromServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunnerBase,
        [Parameter(Mandatory)][string]$TargetVersion,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$ServerSidePath   # e.g. D:\28\<inst>\Service
    )
    $tv = ConvertTo-DeployRunVerifyMajorMinor $TargetVersion
    if (-not $tv) { throw "TargetVersion '$TargetVersion' is not a major.minor version." }
    $dest = Join-Path $RunnerBase $tv
    New-Item -ItemType Directory $dest -Force | Out-Null

    $dlls = 'Microsoft.Dynamics.Framework.UI.Client.dll', 'Microsoft.Internal.AntiSSRF.dll',
    'Newtonsoft.Json.dll', 'System.ServiceModel.Primitives.dll'
    $session = New-PSSession -ComputerName $Server
    try {
        $present = Invoke-Command -Session $session -ScriptBlock {
            param($base, $names)
            $names | Where-Object { Test-Path (Join-Path $base $_) }
        } -ArgumentList $ServerSidePath, $dlls
        foreach ($d in $dlls) {
            if ($present -notcontains $d) {
                if ($d -eq 'Microsoft.Internal.AntiSSRF.dll') { Write-Warning "Optional DLL not on server: $d (continuing)"; continue }
                throw "DLL not found on server '$Server' under '$ServerSidePath': $d"
            }
            Copy-Item -Path (Join-Path $ServerSidePath $d) -Destination (Join-Path $dest $d) -FromSession $session -Force
        }
    }
    finally { Remove-PSSession $session }
    $rv = Get-DeployRunVerifyRunnerVersion -Dir $dest
    Write-Host "Runner materialized (from server '$Server') at '$dest' (BC client $rv)."
    return $dest
}

# ---------------------------------------------------------------------------
# Resolve the client-DLL source folder. Precedence:
#   1) explicit runnerClientSource (local/UNC or server-side) — always wins.
#   2) derived from the BC product-DVD share (bcDvdRoot + bcCountry + major):
#      <bcDvdRoot>\<major>\<bcCountry>.<major>.<minor>\Applications\TestFramework\TestRunner\Internal
#      The highest available <minor> that actually carries the 4 DLLs is chosen.
# Returns $null when neither is configured/resolvable (caller decides how to fail).
# ---------------------------------------------------------------------------
function Resolve-DeployRunVerifyClientSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Cfg,
        [string]$Target   # major.minor of the target BC platform (for the <major> segment)
    )
    if (-not [string]::IsNullOrWhiteSpace($Cfg.runnerClientSource)) { return $Cfg.runnerClientSource }
    if ([string]::IsNullOrWhiteSpace($Cfg.bcDvdRoot) -or [string]::IsNullOrWhiteSpace($Cfg.bcCountry)) { return $null }
    if ([string]::IsNullOrWhiteSpace($Target)) { return $null }

    $major = ($Target -split '\.')[0]
    $majorRoot = Join-Path $Cfg.bcDvdRoot $major
    if (-not (Test-Path $majorRoot)) {
        Write-Warning "BC DVD root '$majorRoot' not found — cannot derive runner client source."
        return $null
    }
    # Folders like 'CH.28.2'; rank by the trailing minor (numeric, descending).
    $prefix = "{0}.{1}." -f $Cfg.bcCountry, $major
    $candidates = Get-ChildItem $majorRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like ($prefix + '*') } |
    Sort-Object @{ Expression = { [int]($_.Name.Substring($prefix.Length) -replace '\D.*$', '') } } -Descending
    foreach ($c in $candidates) {
        $internal = Join-Path $c.FullName 'Applications\TestFramework\TestRunner\Internal'
        if (Test-Path (Join-Path $internal 'Microsoft.Dynamics.Framework.UI.Client.dll')) {
            Write-Host "Derived runner client source from BC DVD: $internal"
            return $internal
        }
    }
    Write-Warning "No '$prefix*' DVD under '$majorRoot' carries the TestRunner client DLLs."
    return $null
}

# ---------------------------------------------------------------------------
# Initialize the runner idempotently: ensure _runner/<target>/ has a valid set of
# version-pinned client DLLs; materialize from runnerClientSource if missing/mismatched.
# Safe to call before every run (survives an ephemeral/wiped workspace).
# ---------------------------------------------------------------------------
function Initialize-DeployRunVerifyRunner {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Cfg)
    $base = $Cfg.runnerDirFull

    # Target BC version: explicit override > live server.
    $target = ConvertTo-DeployRunVerifyMajorMinor $Cfg.bcVersion
    if (-not $target) { $target = ConvertTo-DeployRunVerifyMajorMinor (Get-DeployRunVerifyServerVersion -Cfg $Cfg) }

    # If a valid runner already resolves (right version DLLs present), keep it.
    try {
        $existing = Resolve-DeployRunVerifyRunner -Cfg $Cfg
        if ($existing) { Write-Host "Runner ready: $existing"; return $existing }
    }
    catch {
        Write-Host "Runner not ready ($($_.Exception.Message.Split([char]10)[0])) — materializing..."
    }

    if (-not $target) { throw "Cannot determine target BC version (server unreachable and no bcVersion override) — set 'bcVersion' in config to materialize the runner." }

    # Resolve the effective client-DLL source: explicit runnerClientSource wins; otherwise
    # derive it deterministically from the BC product-DVD share (bcDvdRoot + bcCountry).
    $clientSource = Resolve-DeployRunVerifyClientSource -Cfg $Cfg -Target $target
    if ([string]::IsNullOrWhiteSpace($clientSource)) {
        throw ("No valid runner under '$base' for BC $target and no client source resolved. " +
            "Set 'runnerClientSource' to the folder holding the 4 client DLLs (the BC Service folder, " +
            "or the DVD's Applications\TestFramework\TestRunner\Internal), or set 'bcDvdRoot' + 'bcCountry' " +
            "to derive it from the product-DVD share.")
    }

    # Server-pull only applies to an explicit server-side runnerClientSource; a DVD-derived
    # local/UNC path is always copied directly.
    if ($Cfg.runnerClientFromServer -and -not [string]::IsNullOrWhiteSpace($Cfg.runnerClientSource)) {
        Copy-DeployRunVerifyRunnerFromServer -RunnerBase $base -TargetVersion $target -Server $Cfg.server -ServerSidePath $clientSource | Out-Null
    }
    else {
        New-DeployRunVerifyRunner -RunnerBase $base -TargetVersion $target -ClientFrom $clientSource | Out-Null
    }
    return Resolve-DeployRunVerifyRunner -Cfg $Cfg
}

# ---------------------------------------------------------------------------
# Preflight (HITL-aware): reachability; caller owns the environment ack.
# HTTP(S) probe against the resolved ServiceUrl, not ICMP: an Azure load balancer (Fkh)
# commonly drops ICMP while the web client answers fine, which would otherwise silently
# downgrade a healthy Fkh target to build-only. Any HTTP response (even 4xx/5xx) proves
# the endpoint is reachable; only a transport-level failure means truly unreachable.
# ---------------------------------------------------------------------------
function Test-DeployRunVerifyPreflight {
    param([Parameter(Mandatory)]$Cfg)
    $reachable = $false
    try {
        Invoke-WebRequest -Uri $Cfg.serviceUrl -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop | Out-Null
        $reachable = $true
    }
    catch {
        # StrictMode-safe: not every transport failure (timeout/DNS/TLS) exposes .Response
        if ($_.Exception.PSObject.Properties.Match('Response').Count -gt 0 -and $_.Exception.Response) { $reachable = $true }
    }
    [pscustomobject]@{ Reachable = [bool]$reachable; ServiceUrl = $Cfg.serviceUrl }
}

# ---------------------------------------------------------------------------
# Route state and shared helpers (E-010 spec 6.2, 6.7)
# ---------------------------------------------------------------------------
function Reset-DeployRunVerifyRunState {
    $Script:DeployRunVerifyAlToolInfo = $null
    $Script:DeployRunVerifyAlToolCaps = $null
    $Script:DeployRunVerifyPinnedLegacy = @{}
    $Script:DeployRunVerifyFallbacks = [System.Collections.Generic.List[string]]::new()
    $Script:DeployRunVerifyRoutes = [ordered]@{
        Build  = [pscustomobject]@{ Route = 'n/a'; Reason = '' }
        Deploy = [pscustomobject]@{ Route = 'n/a'; Reason = '' }
        Tests  = [pscustomobject]@{ Route = 'n/a'; Reason = '' }
    }
}

function Get-DeployRunVerifyProperty {
    # StrictMode-safe property read on config / result / JSON objects.
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-DeployRunVerifyRoutePolicy {
    # auto | altool | devEndpoint (Deploy) | webClient (Tests); set by the orchestrator from the route env vars.
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][ValidateSet('Deploy', 'Tests')][string]$Step)
    $name = if ($Step -eq 'Deploy') { 'deployRoute' } else { 'testRoute' }
    $value = [string](Get-DeployRunVerifyProperty -Object $Cfg -Name $name -Default 'auto')
    if ([string]::IsNullOrWhiteSpace($value)) { return 'auto' }
    return $value
}

function Set-DeployRunVerifyRoute {
    # Records the route a step used; -Fallback adds one ROUTE-FALLBACK line per step (printed after TIMING).
    param(
        [Parameter(Mandatory)][ValidateSet('Build', 'Deploy', 'Tests')][string]$Step,
        [Parameter(Mandatory)][string]$Route,
        [string]$Reason = '',
        [switch]$Fallback
    )
    $Script:DeployRunVerifyRoutes[$Step] = [pscustomobject]@{ Route = $Route; Reason = $Reason }
    if ($Fallback) {
        $prefix = "ROUTE-FALLBACK: $($Step.ToLowerInvariant()) "
        $known = @($Script:DeployRunVerifyFallbacks | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::Ordinal) })
        if ($known.Count -eq 0) { $Script:DeployRunVerifyFallbacks.Add("$prefix$([char]0x2192) $Route ($Reason)") }
    }
}

function ConvertTo-DeployRunVerifyRedactedText {
    # Server / tool text that may reach a log: query strings, auth headers and secret-looking pairs removed.
    param([AllowNull()][string]$Text, [int]$MaxLength = 600)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $out = $Text.Trim()
    $out = [regex]::Replace($out, '(?i)(https?://[^\s?]+)\?[^\s]+', '$1?<redacted>')
    $out = [regex]::Replace($out, '(?i)\bAuthorization\s*[:=]\s*(Basic|Bearer|Negotiate|NTLM)\s+[^\s,;]+', 'Authorization: <redacted>')
    $out = [regex]::Replace($out, '(?i)\b(token|key|secret|password|BC_SERVER_PASSWORD|BC_ACCESS_TOKEN)(\s*[:=]\s*)[^\s,;]+', '$1$2<redacted>')
    if ($out.Length -gt $MaxLength) { $out = $out.Substring(0, $MaxLength) + '...' }
    return $out
}

# ---------------------------------------------------------------------------
# altool: locator, capability detection, child process (spec 2.4, 6.2, 6.3)
# ---------------------------------------------------------------------------
function Get-DeployRunVerifyAlTool {
    # Cached per run. An unavailable altool is data (Path = $null, Error = text), not an exception:
    # every step then takes its legacy route and records why.
    if ($null -ne $Script:DeployRunVerifyAlToolInfo) { return $Script:DeployRunVerifyAlToolInfo }
    $info = $null
    try {
        if (-not (Get-Command Find-AprodaAlTool -ErrorAction SilentlyContinue)) {
            throw 'AL_MCP_SKILL_MISSING: the AL target library (skill-aproda-al-mcp) is not loaded.'
        }
        $found = Find-AprodaAlTool
        foreach ($warning in @($found.Warnings)) { Write-Warning "$($warning.code): $($warning.message)" }
        $info = [pscustomobject]@{ Path = $found.Path; Version = $found.Version; Source = $found.Source; Error = $null }
    }
    catch {
        $info = [pscustomobject]@{ Path = $null; Version = $null; Source = 'none'; Error = $_.Exception.Message }
    }
    $Script:DeployRunVerifyAlToolInfo = $info
    return $info
}

function ConvertFrom-DeployRunVerifyAlToolHelp {
    # Help text is localized (German "Nutzung"/"Optionen"): only command and option names are matched.
    param([string]$MainHelp = '', [string]$RunTestsHelp = '')
    $hasRunTests = [regex]::IsMatch($MainHelp, '(?im)^\s+runtests\b')
    return [pscustomobject]@{
        Compile    = [regex]::IsMatch($MainHelp, '(?im)^\s+compile\b')
        PublishApp = [regex]::IsMatch($MainHelp, '(?im)^\s+publishapp\b')
        RunTests   = $hasRunTests
        TestGroups = ($hasRunTests -and [regex]::IsMatch($RunTestsHelp, '(?i)--testgroups\b'))
    }
}

function Get-DeployRunVerifyAlToolCapabilities {
    # `altool --help` and `altool runtests --help` once per run (cached).
    param([Parameter(Mandatory)]$AlTool)
    $cached = $Script:DeployRunVerifyAlToolCaps
    if ($null -ne $cached -and $cached.Path -eq $AlTool.Path) { return $cached.Caps }

    $helpText = {
        param($Call)
        if ($null -eq $Call -or (Get-DeployRunVerifyProperty -Object $Call -Name 'LaunchError') -or $Call.TimedOut) { return '' }
        return ([string]$Call.StdOut + [Environment]::NewLine + [string]$Call.StdErr)
    }
    $main = & $helpText (Invoke-DeployRunVerifyAlTool -AlTool $AlTool -Arguments @('--help') -TimeoutMs 60000)
    $runTestsHelp = ''
    if ([regex]::IsMatch($main, '(?im)^\s+runtests\b')) {
        $runTestsHelp = & $helpText (Invoke-DeployRunVerifyAlTool -AlTool $AlTool -Arguments @('runtests', '--help') -TimeoutMs 60000)
    }
    $caps = ConvertFrom-DeployRunVerifyAlToolHelp -MainHelp $main -RunTestsHelp $runTestsHelp
    $Script:DeployRunVerifyAlToolCaps = [pscustomobject]@{ Path = $AlTool.Path; Caps = $caps }
    return $caps
}

function Invoke-DeployRunVerifyAlTool {
    # One altool child process. Credentials reach it ONLY through ProcessStartInfo.Environment
    # (never $env:, never the command line); inherited BC_SERVER_* / BC_ACCESS_TOKEN are removed.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$AlTool,
        [Parameter(Mandatory)][string[]]$Arguments,
        $Credential,
        [int]$TimeoutMs = 0
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = [string]$AlTool.Path
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    foreach ($argument in $Arguments) { $psi.ArgumentList.Add($argument) }
    foreach ($name in @($psi.Environment.Keys | Where-Object { $_ -like 'BC_SERVER_*' -or $_ -eq 'BC_ACCESS_TOKEN' })) {
        [void]$psi.Environment.Remove($name)
    }
    if ($null -ne $Credential) {
        $psi.Environment['BC_SERVER_USERNAME'] = [string]$Credential.UserName
        $psi.Environment['BC_SERVER_PASSWORD'] = [string]$Credential.GetNetworkCredential().Password
    }
    Write-Host ('[altool] ' + (($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '))

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = $null
    try { $process = [System.Diagnostics.Process]::Start($psi) }
    catch {
        return [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = ''; DurationMs = [int]$stopwatch.ElapsedMilliseconds; TimedOut = $false; LaunchError = $_.Exception.Message }
    }
    finally { if ($psi.Environment.ContainsKey('BC_SERVER_PASSWORD')) { [void]$psi.Environment.Remove('BC_SERVER_PASSWORD') } }

    $timedOut = $false
    try {
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        $exited = $true
        if ($TimeoutMs -gt 0) { $exited = $process.WaitForExit($TimeoutMs) } else { $process.WaitForExit() }
        if (-not $exited) {
            $timedOut = $true
            try { $process.Kill($true) } catch { try { $process.Kill() } catch { $null = $_ } }
            [void]$process.WaitForExit(10000)
        }
        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($outTask, $errTask), 10000) } catch { $null = $_ }
        $stdout = if ($outTask.IsCompleted -and -not $outTask.IsFaulted) { [string]$outTask.Result } else { '' }
        $stderr = if ($errTask.IsCompleted -and -not $errTask.IsFaulted) { [string]$errTask.Result } else { '' }
        $exitCode = -1
        try { $exitCode = [int]$process.ExitCode } catch { $null = $_ }
    }
    finally { $process.Dispose() }
    $stopwatch.Stop()
    return [pscustomobject]@{ ExitCode = $exitCode; StdOut = $stdout; StdErr = $stderr; DurationMs = [int]$stopwatch.ElapsedMilliseconds; TimedOut = $timedOut; LaunchError = $null }
}

# ---------------------------------------------------------------------------
# Build route (spec 6.5): altool compile (-> alc.exe) first, alc.exe second. Each app in order;
# the upstream .app is copied into every downstream .alpackages (Q-2). Compiler errors are real
# failures and never a fallback trigger.
# ---------------------------------------------------------------------------
function Invoke-DeployRunVerifyAlc {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)]$App, [Parameter(Mandatory)][string]$PackageDir)
    & $Cfg.alcPath /project:"$($App.ProjectDir)" /packagecachepath:"$PackageDir" /out:"$($App.AppFile)" /loglevel:Error
}

function Invoke-DeployRunVerifyBuild {
    param([Parameter(Mandatory)]$Cfg)
    $built = @()
    $alTool = Get-DeployRunVerifyAlTool
    foreach ($app in $Cfg.apps) {
        # Refresh upstream symbols into this app's .alpackages
        $pkg = Join-Path $app.ProjectDir '.alpackages'
        if (-not (Test-Path $pkg)) { New-Item -ItemType Directory $pkg -Force | Out-Null }
        foreach ($up in $built) {
            Get-ChildItem $pkg -Filter ("{0}_{1}_*.app" -f $up.Publisher, $up.Name) -EA SilentlyContinue | Remove-Item -Force
            Copy-Item $up.AppFile (Join-Path $pkg ("{0}_{1}_{2}.app" -f $up.Publisher, $up.Name, $up.Version)) -Force
        }
        if (Test-Path $app.AppFile) { Remove-Item $app.AppFile -Force }
        Write-Host "==== BUILD $($app.Name) $($app.Version) ===="

        $fallbackReason = $null
        $pinned = $Script:DeployRunVerifyPinnedLegacy.ContainsKey('Build')
        if ($pinned) { $fallbackReason = "pinned after invocation failure: $($Script:DeployRunVerifyPinnedLegacy['Build'])" }
        elseif (-not $alTool.Path) { $fallbackReason = "altool unavailable ($($alTool.Error))" }
        elseif (-not (Get-DeployRunVerifyAlToolCapabilities -AlTool $alTool).Compile) { $fallbackReason = 'altool has no compile command' }

        if (-not $fallbackReason) {
            $call = Invoke-DeployRunVerifyAlTool -AlTool $alTool -TimeoutMs 1800000 -Arguments @(
                'compile', "/project:$($app.ProjectDir)", "/packagecachepath:$pkg", "/out:$($app.AppFile)", '/loglevel:Error')
            $text = ([string]$call.StdOut + [Environment]::NewLine + [string]$call.StdErr)
            foreach ($line in ($text -split '\r?\n')) { if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host $line } }
            $launchError = Get-DeployRunVerifyProperty -Object $call -Name 'LaunchError'
            if ($launchError) { $fallbackReason = "altool could not be started: $launchError" }
            elseif ($call.TimedOut) { $fallbackReason = 'altool compile timed out' }
            elseif ($call.ExitCode -ne 0 -and $text -notmatch 'error AL\d{4}') { $fallbackReason = "altool compile exit $($call.ExitCode) without a compiler diagnostic" }
            elseif ($call.ExitCode -ne 0 -or -not (Test-Path $app.AppFile)) { throw "BUILD FAILED: $($app.Name) $($app.Version)" }
            else { Set-DeployRunVerifyRoute -Step Build -Route altool }
            if ($fallbackReason) { $Script:DeployRunVerifyPinnedLegacy['Build'] = $fallbackReason }
        }

        if ($fallbackReason) {
            Set-DeployRunVerifyRoute -Step Build -Route alc -Reason $fallbackReason -Fallback
            Invoke-DeployRunVerifyAlc -Cfg $Cfg -App $app -PackageDir $pkg
            if (-not (Test-Path $app.AppFile)) { throw "BUILD FAILED: $($app.Name) $($app.Version)" }
        }
        $built += $app
    }
    Write-Host "Build OK ($($built.Count) app(s))."
    return $true
}

# ---------------------------------------------------------------------------
# Missing-dependency preflight (D-52): adapter-agnostic detection, run before any
# publish attempt on either adapter. Detection only — resolution stays HITL (agent-
# executed, see references/dependency-resolution.md); this engine never installs a
# dependency it discovered itself.
# ---------------------------------------------------------------------------
function Get-DeployRunVerifyAppManifestDependencies {
    param([Parameter(Mandatory)][string]$AppFile)
    if (-not (Get-Command al -ErrorAction SilentlyContinue)) {
        Write-Warning "The 'al' CLI is not on PATH — cannot inspect $AppFile for manifest dependencies. Missing-dependency preflight is skipped for this app."
        return @()
    }
    # TODO (verify against a live app): al GetPackageManifest emits the package manifest as
    # JSON on stdout, expected to carry a `dependencies` array of { id, name, publisher,
    # version } — the same shape skill-aproda-fkh's bundled sortapps.ps1 already consumes.
    $raw = & al GetPackageManifest --package $AppFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "al GetPackageManifest failed for $AppFile (exit $LASTEXITCODE) — missing-dependency preflight is skipped for this app."
        return @()
    }
    try { return @(($raw | ConvertFrom-Json).dependencies) }
    catch {
        Write-Warning "Could not parse al GetPackageManifest output for $AppFile — missing-dependency preflight is skipped for this app."
        return @()
    }
}

function Get-DeployRunVerifyInstalledAppsFkh {
    param([Parameter(Mandatory)][string]$BackendUrl, [Parameter(Mandatory)][string]$AppLabel)
    $raw = & fkh getappinfo --name $AppLabel --appName '*' --asJson --backendUrl $BackendUrl
    if ($LASTEXITCODE -ne 0) { throw "fkh getappinfo failed while checking target dependencies (exit code $LASTEXITCODE)." }
    return @(($raw | ConvertFrom-Json).apps)
}

function Get-DeployRunVerifyInstalledAppsAsinst {
    param([Parameter(Mandatory)]$Cfg)
    $session = New-PSSession -ComputerName $Cfg.server
    try {
        return Invoke-Command -Session $session -ScriptBlock {
            param($si, $tenant, $mgmt)
            Import-Module $mgmt -ErrorAction Stop
            Get-NAVAppInfo -ServerInstance $si -Tenant $tenant -TenantSpecificProperties |
            Select-Object Name, Publisher, Version, IsInstalled
        } -ArgumentList $Cfg.serverInstance, $Cfg.tenant, $Cfg.mgmtDllPath
    }
    finally { Remove-PSSession $session }
}

function Test-DeployRunVerifyTargetDependencies {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Cfg)

    $configuredNames = @($Cfg.apps | ForEach-Object { $_.Name })
    $required = @{}
    foreach ($app in $Cfg.apps) {
        foreach ($dep in (Get-DeployRunVerifyAppManifestDependencies -AppFile $app.AppFile)) {
            if ($configuredNames -contains $dep.name) { continue }  # already covered by this project's own app set
            $key = "$($dep.name)|$($dep.version)"
            if (-not $required.ContainsKey($key)) { $required[$key] = [pscustomobject]@{ RequiredBy = $app.Name; Name = $dep.name; Version = $dep.version } }
        }
    }
    if ($required.Count -eq 0) { return }

    $installed = switch ($Cfg.adapter) {
        'Fkh' {
            $backendUrl = Get-DeployRunVerifyFkhBackendUrl
            $container = Resolve-DeployRunVerifyFkhContainer -Cfg $Cfg -BackendUrl $backendUrl
            Get-DeployRunVerifyInstalledAppsFkh -BackendUrl $backendUrl -AppLabel ([string]$container.appLabel)
        }
        default { Get-DeployRunVerifyInstalledAppsAsinst -Cfg $Cfg }
    }

    $missing = foreach ($req in $required.Values) {
        $found = @($installed) | Where-Object { $_.Name -eq $req.Name -and [bool]$_.IsInstalled }
        if (-not $found) { "$($req.Name) $($req.Version) (required by $($req.RequiredBy))" }
    }
    if ($missing) {
        throw ("MISSING TARGET DEPENDENCY on $($Cfg.server): " + ($missing -join '; ') +
            '. Resolution is HITL — do not auto-install. See skill-aproda-deploy-run-verify/references/dependency-resolution.md.')
    }
}

# ---------------------------------------------------------------------------
# Confirmed-file install of a single resolved dependency (D-52). The caller (agent) must
# already have matched the file against the known Aproda app sources and obtained the
# user's explicit confirmation — this function only executes the mechanics, adapter-
# dispatched, for exactly the file path it is given. It never discovers or picks a file.
# ---------------------------------------------------------------------------
function Install-DeployRunVerifyResolvedDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Cfg,
        [Parameter(Mandatory)][string]$AppFile,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version
    )
    if (-not (Test-Path -LiteralPath $AppFile)) { throw "Resolved dependency file not found: $AppFile" }

    # Same publish chain as the project's own apps (altool, then direct Dev Endpoint POST; both adapters).
    $context = Get-DeployRunVerifyPublishContext -Cfg $Cfg
    Invoke-DeployRunVerifyPublishApp -Cfg $Cfg -AppFile $AppFile -Name $Name -Version $Version -Context $context
    Write-Host "Resolved dependency installed: $Name $Version"
}

# ---------------------------------------------------------------------------
# Fkh backend URL: workstation-local VS Code user setting (D-33) — never committed,
# never printed.
# ---------------------------------------------------------------------------
function Get-DeployRunVerifyFkhBackendUrl {
    $settingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) { throw 'VS Code user settings were not found (the Fkh adapter requires fkh.backendUrl).' }
    $settingsContent = Get-Content -LiteralPath $settingsPath -Raw
    $m = [regex]::Match($settingsContent, '"fkh\.backendUrl"\s*:\s*"(?<value>[^"]+)"')
    if (-not $m.Success) { throw 'VS Code user setting fkh.backendUrl is not configured.' }
    return $m.Groups['value'].Value
}

# ---------------------------------------------------------------------------
# Match the launch.json host against a live Fkh container (skill-aproda-fkh's rule): an
# unmatched or ambiguous candidate stops for HITL, it never falls through to ASINST.
# ---------------------------------------------------------------------------
function Resolve-DeployRunVerifyFkhContainer {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$BackendUrl)
    if (-not (Get-Command fkh -ErrorAction SilentlyContinue)) { throw "The 'fkh' CLI is required for the Fkh adapter and was not found in PATH." }
    $raw = & fkh listcontainers --all --asJson --backendUrl $BackendUrl
    if ($LASTEXITCODE -ne 0) { throw "fkh listcontainers failed with exit code $LASTEXITCODE." }
    $data = $raw | ConvertFrom-Json
    $items = @($data.containers)
    $targetHost = $Cfg.server
    $match = @($items | Where-Object {
            try { ([uri][string]$_.webClient).Host -eq $targetHost } catch { $false }
        })
    if ($match.Count -eq 0) { throw "No Fkh container matches launch host '$targetHost' — stop and confirm the target with the user." }
    if ($match.Count -gt 1) { throw "Multiple Fkh containers match launch host '$targetHost' — stop and confirm the target with the user." }
    return $match[0]
}

# ---------------------------------------------------------------------------
# Publish route (E-010 spec 6.4): one chain for both adapters, per app in dependency order:
#   a. altool publishapp  ->  b. direct Dev Endpoint POST (only on InvocationFailure)  ->  verify state.
# ForceSync and forceUpgrade are never implied: schema mode comes from fkhSyncMode (D-39),
# --forceupgrade only from an explicit per-run request.
# ---------------------------------------------------------------------------
function Get-DeployRunVerifySchemaMode {
    param([Parameter(Mandatory)]$Cfg)
    $mode = [string](Get-DeployRunVerifyProperty -Object $Cfg -Name 'fkhSyncMode' -Default 'Add')
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = 'Add' }
    switch ($mode) {
        'Add' { return [pscustomobject]@{ Name = 'Add'; AlTool = 'Synchronize'; Endpoint = 'synchronize' } }
        'ForceSync' { return [pscustomobject]@{ Name = 'ForceSync'; AlTool = 'ForceSync'; Endpoint = 'forcesync' } }
        default { throw "fkhSyncMode must be 'Add' or 'ForceSync'." }
    }
}

function New-DeployRunVerifyBasicAuthorization {
    # In-memory HTTP Basic header for the direct POST (UserPassword). ASCII only (Q-19): an ASCII
    # encoder would silently turn umlauts into '?'. Never logged, never persisted.
    param([Parameter(Mandatory)]$Credential)
    $user = [string]$Credential.UserName
    $password = [string]$Credential.GetNetworkCredential().Password
    foreach ($part in @($user, $password)) {
        foreach ($char in $part.ToCharArray()) {
            if ([int]$char -gt 127) { throw 'CREDENTIAL_NON_ASCII: the user name or password contains non-ASCII characters; the direct Dev Endpoint publish rejects them (Q-19).' }
        }
    }
    $token = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($user + ':' + $password))
    return [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Basic', $token)
}

function Get-DeployRunVerifyPublishOutcome {
    # Classifies a publish attempt (spec 6.4). Returns { Outcome; Reason }.
    # Published | AuthFailure | Duplicate | ProtocolError | Rejected | InvocationFailure.
    # altool strings are PROVISIONAL until the scrubbed captures of L-4b.12 (OS-1).
    [CmdletBinding(DefaultParameterSetName = 'AlTool')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Http')][AllowNull()][Nullable[int]]$HttpStatus,
        [Parameter(Mandatory, ParameterSetName = 'AlTool')][int]$ExitCode,
        [string]$Output = '',
        [Parameter(ParameterSetName = 'AlTool')][switch]$TimedOut,
        [Parameter(ParameterSetName = 'AlTool')][string]$LaunchError
    )
    $reasonText = ConvertTo-DeployRunVerifyRedactedText -Text $Output
    $result = { param($Outcome, $Reason) [pscustomobject]@{ Outcome = $Outcome; Reason = $Reason } }

    if ($PSCmdlet.ParameterSetName -eq 'Http') {
        if ($null -eq $HttpStatus) { return (& $result 'InvocationFailure' ($(if ($reasonText) { $reasonText } else { 'no HTTP response' }))) }
        switch ([int]$HttpStatus) {
            { $_ -ge 200 -and $_ -lt 300 } { return (& $result 'Published' '') }
            401 { return (& $result 'AuthFailure' ("HTTP 401 $reasonText".Trim())) }
            415 { return (& $result 'ProtocolError' ("HTTP 415 $reasonText".Trim())) }
            422 { return (& $result 'Duplicate' ("HTTP 422 $reasonText".Trim())) }
            default { return (& $result 'Rejected' ("HTTP $HttpStatus $reasonText".Trim())) }
        }
    }

    if ($LaunchError) { return (& $result 'InvocationFailure' "altool could not be started: $(ConvertTo-DeployRunVerifyRedactedText -Text $LaunchError)") }
    if ($TimedOut) { return (& $result 'InvocationFailure' 'altool publishapp timed out') }
    if ($ExitCode -eq 0) { return (& $result 'Published' '') }
    if ($Output -match '(?i)UserNotAuthenticated|\bUnauthorized\b|HTTP\D{0,20}\b401\b') { return (& $result 'AuthFailure' $reasonText) }
    if ($Output -match '(?i)UnsupportedMediaType|HTTP\D{0,20}\b415\b') { return (& $result 'ProtocolError' $reasonText) }
    if ($Output -match '(?i)UnprocessableEntity|duplicate\s+package|HTTP\D{0,20}\b422\b') { return (& $result 'Duplicate' $reasonText) }
    if ($Output -match '(?i)HTTP\D{0,20}\b[45]\d\d\b|\b(BadRequest|Forbidden|NotFound|InternalServerError|BadGateway|ServiceUnavailable|GatewayTimeout)\b|\bschema\b|\bsynchroni[sz]\w*\b|\b(AL|PTE)\d{4}\b') {
        return (& $result 'Rejected' $reasonText)
    }
    if ($Output -match '(?i)ConnectionFailed|connection\s+(was\s+)?refused|actively\s+refused|No such host|name or service not known|remote name could not be resolved|SSL|TLS|certificate|timed?\s*out|A task was canceled|retryable"?\s*:\s*true|SocketException|HttpRequestException') {
        return (& $result 'InvocationFailure' $reasonText)
    }
    # Unrecognized failure: stop rather than fall back; a second publish attempt could repeat a half-done one.
    return (& $result 'Rejected' $reasonText)
}

function Publish-DeployRunVerifyDevEndpoint {
    # Direct multipart POST to {ServerUrl}:{Port}/{ServerInstance}/dev/apps (dev-endpoint-publish-protocol.md 2-5).
    # Returns { Outcome; Reason; HttpStatus; Body }. Never retries.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Cfg,
        [Parameter(Mandatory)][string]$AppFile,
        $Credential,
        [ValidateSet('synchronize', 'forcesync')][string]$SchemaUpdateMode = 'synchronize',
        [switch]$ForceUpgrade
    )
    if ($ForceUpgrade) { throw 'FORCEUPGRADE_REQUIRES_ALTOOL: --forceupgrade is only available through altool publishapp; the direct Dev Endpoint publish cannot apply it.' }
    $bundle = Get-DeployRunVerifyProperty -Object $Cfg -Name 'targetBundle'
    if ($null -eq $bundle) { throw 'TARGET_NOT_CONFIGURED: the direct Dev Endpoint publish needs the target bundle of the resolved config.' }
    if (-not (Test-Path -LiteralPath $AppFile -PathType Leaf)) { throw "APP_FILE_NOT_FOUND: $AppFile" }

    $authorization = $null
    if ($bundle.Authentication -eq 'UserPassword') {
        if ([string]$bundle.ServerUrl -notmatch '^https://') { throw 'USERPASSWORD_OVER_HTTP: UserPassword publishes only over HTTPS; the Basic header would expose the password.' }
        if ($null -eq $Credential) { throw 'CREDENTIAL_MISSING: UserPassword needs a credential from the Fkh store flow (D-43).' }
        $authorization = New-DeployRunVerifyBasicAuthorization -Credential $Credential
    }
    $dependencyOption = [string](Get-DeployRunVerifyProperty -Object $Cfg -Name 'dependencyPublishingOption' -Default 'Default')
    $url = '{0}:{1}/{2}/dev/apps?SchemaUpdateMode={3}&DependencyPublishingOption={4}&tenant={5}' -f $bundle.ServerUrl, $bundle.Port,
    [uri]::EscapeDataString([string]$bundle.ServerInstance), $SchemaUpdateMode, [uri]::EscapeDataString($dependencyOption), [uri]::EscapeDataString([string]$bundle.Tenant)

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client = $null; $multipart = $null; $fileStream = $null; $response = $null
    try {
        $handler.UseDefaultCredentials = ($null -eq $authorization)
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
        $client.DefaultRequestHeaders.ExpectContinue = $false
        if ($null -ne $authorization) { $client.DefaultRequestHeaders.Authorization = $authorization }

        $fileName = [System.IO.Path]::GetFileName($AppFile)
        $multipart = [System.Net.Http.MultipartFormDataContent]::new()
        $fileStream = [System.IO.FileStream]::new($AppFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $part = [System.Net.Http.StreamContent]::new($fileStream)
        $disposition = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new('form-data')
        $disposition.Name = $fileName
        $disposition.FileName = $fileName
        $disposition.FileNameStar = $fileName
        $part.Headers.ContentDisposition = $disposition
        $multipart.Add($part)

        $status = $null
        $body = ''
        try {
            $response = $client.PostAsync($url, $multipart).GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
        }
        catch {
            $classified = Get-DeployRunVerifyPublishOutcome -HttpStatus $null -Output $_.Exception.Message
            return [pscustomobject]@{ Outcome = $classified.Outcome; Reason = $classified.Reason; HttpStatus = $null; Body = '' }
        }
        # The status decides; a body that cannot be read must not turn an answered request into a transport failure.
        try { $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch { $body = '' }
        $classified = Get-DeployRunVerifyPublishOutcome -HttpStatus $status -Output $body
        return [pscustomobject]@{ Outcome = $classified.Outcome; Reason = $classified.Reason; HttpStatus = $status; Body = (ConvertTo-DeployRunVerifyRedactedText -Text $body) }
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $multipart) { $multipart.Dispose() }
        if ($null -ne $fileStream) { $fileStream.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
        $handler.Dispose()
        $authorization = $null
    }
}

function Invoke-DeployRunVerifyAlToolPublish {
    # Route a. No --project: nothing may merge from launch.json (C-1/C-2); the bundle is passed in full.
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)]$AlTool, [Parameter(Mandatory)][string]$AppFile, [Parameter(Mandatory)]$Schema, $Credential, [switch]$ForceUpgrade)
    $bundle = $Cfg.targetBundle
    $arguments = @('publishapp', $AppFile, '--server', [string]$bundle.ServerUrl, '--serverinstance', [string]$bundle.ServerInstance,
        '--port', [string]$bundle.Port, '--authentication', [string]$bundle.Authentication, '--tenant', [string]$bundle.Tenant,
        '--environmenttype', 'OnPrem', '--schemaupdatemode', [string]$Schema.AlTool)
    if ($ForceUpgrade) { $arguments += '--forceupgrade' }
    $call = Invoke-DeployRunVerifyAlTool -AlTool $AlTool -Arguments $arguments -Credential $Credential -TimeoutMs 600000
    $output = ([string]$call.StdOut + [Environment]::NewLine + [string]$call.StdErr)
    foreach ($line in ($output -split '\r?\n')) {
        $text = ConvertTo-DeployRunVerifyRedactedText -Text $line -MaxLength 400
        if ($text) { Write-Host "  $text" }
    }
    $launchError = [string](Get-DeployRunVerifyProperty -Object $call -Name 'LaunchError' -Default '')
    return Get-DeployRunVerifyPublishOutcome -ExitCode ([int]$call.ExitCode) -Output $output -TimedOut:([bool]$call.TimedOut) -LaunchError $launchError
}

function Get-DeployRunVerifyPublishContext {
    # Fkh: verify the target against `fkh listcontainers` (D-26) and keep appLabel/backend for state reads.
    # ASINST: the state read needs the Management DLL, so a missing mgmtDllPath stops BEFORE any publish.
    param([Parameter(Mandatory)]$Cfg)
    if ($Cfg.adapter -ne 'Fkh') {
        if ([string]::IsNullOrWhiteSpace([string](Get-DeployRunVerifyProperty -Object $Cfg -Name 'mgmtDllPath' -Default ''))) {
            throw 'mgmtDllPath is required for the ASINST adapter (state verification after the publish).'
        }
        return $null
    }
    $backendUrl = Get-DeployRunVerifyFkhBackendUrl
    $container = Resolve-DeployRunVerifyFkhContainer -Cfg $Cfg -BackendUrl $backendUrl
    $appLabel = [string]$container.appLabel
    if ([string]::IsNullOrWhiteSpace($appLabel)) { throw 'Resolved Fkh container has no appLabel.' }
    Write-Host "Fkh target: appLabel=$appLabel"
    return [pscustomobject]@{ BackendUrl = $backendUrl; AppLabel = $appLabel }
}

function Get-DeployRunVerifyAppState {
    # Read-only state of one exact version: Fkh via `fkh getappinfo`, ASINST via the Management DLL (remote session).
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version, $Context)
    $entry = $null
    if ($Cfg.adapter -eq 'Fkh') {
        $raw = & fkh getappinfo --name $Context.AppLabel --appName $Name --asJson --backendUrl $Context.BackendUrl
        if ($LASTEXITCODE -ne 0) { throw "Fkh getappinfo failed: $Name" }
        $info = $raw | ConvertFrom-Json
        if ($info.PSObject.Properties.Name -contains 'apps') { $entry = @($info.apps) | Where-Object { $_.Version -eq $Version } | Select-Object -First 1 }
    }
    else {
        $mgmtDllPath = [string](Get-DeployRunVerifyProperty -Object $Cfg -Name 'mgmtDllPath' -Default '')
        if ([string]::IsNullOrWhiteSpace($mgmtDllPath)) { throw 'mgmtDllPath is required for the ASINST adapter (state verification).' }
        $session = New-PSSession -ComputerName $Cfg.server
        try {
            $entry = Invoke-Command -Session $session -ScriptBlock {
                param($si, $tenant, $mgmt, $name, $version)
                Import-Module $mgmt -ErrorAction Stop
                Get-NAVAppInfo -ServerInstance $si -Tenant $tenant -TenantSpecificProperties -Name $name |
                Where-Object { [string]$_.Version -eq $version } | Select-Object -First 1 -Property Name, Version, IsInstalled, SyncState
            } -ArgumentList $Cfg.serverInstance, $Cfg.tenant, $mgmtDllPath, $Name, $Version
        }
        finally { Remove-PSSession $session }
    }
    if (-not $entry) { return [pscustomobject]@{ Found = $false; IsInstalled = $false; SyncState = $null } }
    return [pscustomobject]@{
        Found       = $true
        IsInstalled = [bool](Get-DeployRunVerifyProperty -Object $entry -Name 'IsInstalled' -Default $false)
        SyncState   = [string](Get-DeployRunVerifyProperty -Object $entry -Name 'SyncState' -Default '')
    }
}

function Assert-DeployRunVerifyAppPublished {
    # Never run tests against a half-deployed server: the exact version must be installed and Synced.
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version, $Context)
    $state = Get-DeployRunVerifyAppState -Cfg $Cfg -Name $Name -Version $Version -Context $Context
    $problem = $null
    if (-not $state.Found) { $problem = 'not found on the target' }
    elseif (-not $state.IsInstalled) { $problem = 'IsInstalled=False' }
    elseif ($state.SyncState -ne 'Synced') { $problem = "SyncState=$($state.SyncState)" }
    if ($problem) { throw "DEPLOY INCOMPLETE ($($Cfg.adapter)) - not installed/synced: $Name $Version ($problem)" }
}

function Save-DeployRunVerifyCredentialAfterSuccess {
    # D-43: a credential that just worked is saved (or refreshed) without a prompt.
    param([Parameter(Mandatory)]$Cfg, $Credential)
    if ($Cfg.authentication -ne 'UserPassword' -or $null -eq $Credential) { return }
    if ($Script:DeployRunVerifyCredentialFromStore) { return }
    if (-not (Get-Command Save-FkhCredential -ErrorAction SilentlyContinue)) { return }
    Save-FkhCredential -Key $Cfg.server -Credential $Credential
    $Script:DeployRunVerifyCredentialFromStore = $true
    Write-Host "Fkh-Credential-Store aktualisiert: $($Cfg.server)"
}

function Assert-DeployRunVerifyPublishResult {
    # Returns for Published / AuthFailure; every other outcome is a stop with the guidance for it.
    param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$Route, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version, [string]$Policy = 'auto')
    switch ($Result.Outcome) {
        { $_ -in @('Published', 'AuthFailure') } { return }
        'Duplicate' {
            throw ("PUBLISH_DUPLICATE: $Name $Version was refused as a duplicate package (HTTP 422, route $Route). Do not repeat the publish: inspect the target state (references/redeploy-recovery.md). " +
                'A rebuilt package with a new package ID publishes again; a NotSynced leftover is removed only after confirmation.')
        }
        'ProtocolError' { throw "PUBLISH_PROTOCOL_ERROR: $Name $Version - HTTP 415 on route $Route is an engine defect (multipart shape), not a target problem. $($Result.Reason)" }
        'Rejected' { throw "PUBLISH_REJECTED: $Name $Version was rejected by the target (route $Route). $($Result.Reason)" }
        'InvocationFailure' {
            if ($Policy -eq 'devEndpoint') { throw "ROUTE_UNAVAILABLE: deploy=devEndpoint ($($Result.Reason))" }
            throw "PUBLISH_FAILED: $Name $Version - route $Route could not reach the target. $($Result.Reason)"
        }
        default { throw "PUBLISH_FAILED: $Name $Version - unknown outcome '$($Result.Outcome)'." }
    }
}

function Invoke-DeployRunVerifyPublishRoutes {
    # One publish attempt through the route chain. Returns the result of the route that decided
    # (Published or AuthFailure); anything else throws.
    param(
        [Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$AppFile, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)]$Schema, [Parameter(Mandatory)][string]$Policy, $Credential, [switch]$ForceUpgrade
    )
    $alTool = Get-DeployRunVerifyAlTool
    $unavailable = $null
    if ($Script:DeployRunVerifyPinnedLegacy.ContainsKey('Deploy')) { $unavailable = "pinned after invocation failure: $($Script:DeployRunVerifyPinnedLegacy['Deploy'])" }
    elseif (-not $alTool.Path) { $unavailable = "altool unavailable ($($alTool.Error))" }
    elseif (-not (Get-DeployRunVerifyAlToolCapabilities -AlTool $alTool).PublishApp) { $unavailable = 'altool has no publishapp command' }

    $fallbackReason = $null
    if ($Policy -eq 'altool' -and $unavailable) { throw "ROUTE_UNAVAILABLE: deploy=altool ($unavailable)" }
    if ($Policy -ne 'devEndpoint') {
        if ($unavailable) { $fallbackReason = $unavailable }
        else {
            $splat = @{}
            if ($null -ne $Credential) { $splat.Credential = $Credential }
            $result = Invoke-DeployRunVerifyAlToolPublish -Cfg $Cfg -AlTool $alTool -AppFile $AppFile -Schema $Schema -ForceUpgrade:$ForceUpgrade @splat
            if ($result.Outcome -ne 'InvocationFailure') {
                Assert-DeployRunVerifyPublishResult -Result $result -Route altool -Name $Name -Version $Version
                if ($result.Outcome -eq 'Published') { Set-DeployRunVerifyRoute -Step Deploy -Route altool }
                return $result
            }
            if ($Policy -eq 'altool') { throw "ROUTE_UNAVAILABLE: deploy=altool ($($result.Reason))" }
            $Script:DeployRunVerifyPinnedLegacy['Deploy'] = $result.Reason
            $fallbackReason = $result.Reason
        }
    }

    $splat = @{}
    if ($null -ne $Credential) { $splat.Credential = $Credential }
    $result = Publish-DeployRunVerifyDevEndpoint -Cfg $Cfg -AppFile $AppFile -SchemaUpdateMode $Schema.Endpoint -ForceUpgrade:$ForceUpgrade @splat
    Assert-DeployRunVerifyPublishResult -Result $result -Route devEndpoint -Name $Name -Version $Version -Policy $Policy
    if ($result.Outcome -eq 'Published') {
        if ($fallbackReason) { Set-DeployRunVerifyRoute -Step Deploy -Route devEndpoint -Reason $fallbackReason -Fallback }
        else { Set-DeployRunVerifyRoute -Step Deploy -Route devEndpoint -Reason $(if ($Policy -eq 'devEndpoint') { 'forced (DEPLOY_ROUTE)' } else { '' }) }
    }
    return $result
}

function Invoke-DeployRunVerifyPublishApp {
    # One app file: route chain with the D-43 auth retry (re-prompt once, then blocker), then state verification.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$AppFile, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version,
        $Context, [switch]$ForceUpgrade
    )
    $schema = Get-DeployRunVerifySchemaMode -Cfg $Cfg
    $policy = Get-DeployRunVerifyRoutePolicy -Cfg $Cfg -Step Deploy
    Write-Host "[publish] $Name $Version (schema=$($schema.Name))"
    $maxAttempts = 2
    $credential = $null
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $credential = $null
        if ($Cfg.authentication -eq 'UserPassword') { $credential = Get-DeployRunVerifyCredential -Cfg $Cfg -SkipStore:($attempt -gt 1) }
        $result = Invoke-DeployRunVerifyPublishRoutes -Cfg $Cfg -AppFile $AppFile -Name $Name -Version $Version -Schema $schema -Policy $policy -Credential $credential -ForceUpgrade:$ForceUpgrade
        if ($result.Outcome -eq 'Published') { break }
        if ($attempt -lt $maxAttempts -and $Cfg.authentication -eq 'UserPassword') {
            Write-Warning "Authentication for $($Cfg.server) was refused. Retrying once with a freshly prompted credential..."
            Reset-DeployRunVerifyCredential
            continue
        }
        throw "PUBLISH_AUTH_FAILED: $($Cfg.server) refused the credentials for $Name $Version ($($Cfg.authentication)). $($result.Reason) Check the account; no other route is tried."
    }
    Save-DeployRunVerifyCredentialAfterSuccess -Cfg $Cfg -Credential $credential
    Assert-DeployRunVerifyAppPublished -Cfg $Cfg -Name $Name -Version $Version -Context $Context
}

function Invoke-DeployRunVerifyPublish {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Cfg, [switch]$ForceUpgrade)
    $schema = Get-DeployRunVerifySchemaMode -Cfg $Cfg
    if ($schema.Name -eq 'ForceSync') { Write-Host 'SCHEMA MODE: ForceSync (fkhSyncMode)' }
    if ($ForceUpgrade) { Write-Warning 'forceUpgrade requested for this run (Tier 3): --forceupgrade is passed to altool publishapp.' }
    $context = Get-DeployRunVerifyPublishContext -Cfg $Cfg
    foreach ($app in $Cfg.apps) {
        Invoke-DeployRunVerifyPublishApp -Cfg $Cfg -AppFile $app.AppFile -Name $app.Name -Version $app.Version -Context $context -ForceUpgrade:$ForceUpgrade
    }
    Write-Host "Deploy done ($($Cfg.adapter))."
    return $true
}

# ---------------------------------------------------------------------------
# One-time cleanup of leftovers from the former Management-DLL publish route (ASINST, HITL; spec 6.9).
# Provenance cannot be read from the NST (PublishedAs is absent on BC 28, Q-22), so the agent lists
# candidates by full package identity and the human decides per package. Never in a loop or phase gate.
# ---------------------------------------------------------------------------
function Select-DeployRunVerifyCleanupCandidates {
    # Pure row logic. Rows: Name, Publisher, Version, Scope, IsInstalled, SyncState. An installed version is never a candidate.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows)
    foreach ($row in $Rows) {
        $installed = [bool](Get-DeployRunVerifyProperty -Object $row -Name 'IsInstalled' -Default $false)
        $syncState = [string](Get-DeployRunVerifyProperty -Object $row -Name 'SyncState' -Default '')
        $scope = [string](Get-DeployRunVerifyProperty -Object $row -Name 'Scope' -Default '')
        $reason = 'installed - never a candidate'
        if (-not $installed) {
            $reason = if ($syncState -eq 'NotSynced') { 'published, not installed, NotSynced (failed or superseded publish)' }
            elseif ($syncState) { "published, not installed (SyncState=$syncState)" }
            else { 'published, no tenant state found' }
            if ($scope -eq 'Global') { $reason += '; Global scope - removal affects every tenant' }
        }
        [pscustomobject]@{
            Name        = [string]$row.Name
            Publisher   = [string]$row.Publisher
            Version     = [string]$row.Version
            Scope       = $scope
            IsInstalled = $installed
            SyncState   = $syncState
            Candidate   = (-not $installed)
            Reason      = $reason
        }
    }
}

function Get-DeployRunVerifyCleanupCandidates {
    # Read-only: all published versions of the configured apps joined with the tenant state.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Cfg)
    if ($Cfg.adapter -ne 'Asinst') { throw "CLEANUP_ASINST_ONLY: the one-time cleanup applies to the ASINST adapter (adapter is '$($Cfg.adapter)')." }
    $mgmtDllPath = [string](Get-DeployRunVerifyProperty -Object $Cfg -Name 'mgmtDllPath' -Default '')
    if ([string]::IsNullOrWhiteSpace($mgmtDllPath)) { throw 'mgmtDllPath is required for the ASINST adapter.' }
    $names = @($Cfg.apps | ForEach-Object { $_.Name })
    $session = New-PSSession -ComputerName $Cfg.server
    try {
        $rows = Invoke-Command -Session $session -ScriptBlock {
            param($si, $tenant, $mgmt, $names)
            Import-Module $mgmt -ErrorAction Stop
            foreach ($name in $names) {
                $tenantState = @(Get-NAVAppInfo -ServerInstance $si -Tenant $tenant -TenantSpecificProperties -Name $name)
                foreach ($published in @(Get-NAVAppInfo -ServerInstance $si -Name $name)) {
                    $state = $tenantState | Where-Object { [string]$_.Version -eq [string]$published.Version -and $_.Publisher -eq $published.Publisher } | Select-Object -First 1
                    [pscustomobject]@{
                        Name        = [string]$published.Name
                        Publisher   = [string]$published.Publisher
                        Version     = [string]$published.Version
                        Scope       = [string]$published.Scope
                        IsInstalled = [bool]($state -and $state.IsInstalled)
                        SyncState   = $(if ($state) { [string]$state.SyncState } else { '' })
                    }
                }
            }
        } -ArgumentList $Cfg.serverInstance, $Cfg.tenant, $mgmtDllPath, $names
    }
    finally { Remove-PSSession $session }
    return @(Select-DeployRunVerifyCleanupCandidates -Rows @($rows))
}

function Remove-DeployRunVerifyAppVersion {
    # The only unpublish in the engine. Refuses an installed version; no ClearSchema / DoNotSaveData / ForceSync.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Publisher, [Parameter(Mandatory)][string]$Version)
    if ($Cfg.adapter -ne 'Asinst') { throw "CLEANUP_ASINST_ONLY: the one-time cleanup applies to the ASINST adapter (adapter is '$($Cfg.adapter)')." }
    $mgmtDllPath = [string](Get-DeployRunVerifyProperty -Object $Cfg -Name 'mgmtDllPath' -Default '')
    if ([string]::IsNullOrWhiteSpace($mgmtDllPath)) { throw 'mgmtDllPath is required for the ASINST adapter.' }
    $session = New-PSSession -ComputerName $Cfg.server
    try {
        $outcome = Invoke-Command -Session $session -ScriptBlock {
            param($si, $tenant, $mgmt, $name, $publisher, $version)
            Import-Module $mgmt -ErrorAction Stop
            $published = Get-NAVAppInfo -ServerInstance $si -Name $name -Publisher $publisher -Version $version | Select-Object -First 1
            if (-not $published) { return 'NOT_PUBLISHED' }
            $state = Get-NAVAppInfo -ServerInstance $si -Tenant $tenant -TenantSpecificProperties -Name $name -Publisher $publisher -Version $version | Select-Object -First 1
            if ($state -and $state.IsInstalled) { return 'INSTALLED' }
            if ([string]$published.Scope -eq 'Tenant') {
                Unpublish-NAVApp -ServerInstance $si -Name $name -Publisher $publisher -Version $version -Tenant $tenant -ErrorAction Stop
            }
            else {
                Unpublish-NAVApp -ServerInstance $si -Name $name -Publisher $publisher -Version $version -ErrorAction Stop
            }
            $still = Get-NAVAppInfo -ServerInstance $si -Name $name -Publisher $publisher -Version $version | Select-Object -First 1
            if ($still) { return 'STILL_PUBLISHED' }
            return 'REMOVED'
        } -ArgumentList $Cfg.serverInstance, $Cfg.tenant, $mgmtDllPath, $Name, $Publisher, $Version
    }
    finally { Remove-PSSession $session }
    switch ($outcome) {
        'REMOVED' { Write-Host "Removed: $Name $Version ($Publisher)"; return $true }
        'INSTALLED' { throw "REMOVE_REFUSED_INSTALLED: $Name $Version is installed on tenant '$($Cfg.tenant)'; the cleanup never removes an installed version." }
        'NOT_PUBLISHED' { throw "REMOVE_NOT_FOUND: $Name $Version ($Publisher) is not published on '$($Cfg.serverInstance)'." }
        default { throw "REMOVE_NOT_CONFIRMED: $Name $Version is still published after the removal; inspect the target." }
    }
}

# ---------------------------------------------------------------------------
# Run: headless AL test runner via the web client (proven _RunTests pattern)
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Loads skill-aproda-fkh's credential-store functions content-safe (SRP-exempt), from the
# sibling skill (D-26: Fkh owns auth/transport mechanics, this engine only consumes it).
# Idempotent — a second call is a no-op once the functions are already defined.
# ---------------------------------------------------------------------------
function Get-DeployRunVerifyCredential {
    # UserPassword targets (Fkh) only. Checks the skill-aproda-fkh credential store first
    # (unless -SkipStore, used on a retry so a stale stored credential can't repeat forever);
    # only prompts via Get-Credential (never from config, chat, or environment) on a miss.
    # Cached in module scope so a multi-phase run does not re-prompt.
    param([Parameter(Mandatory)]$Cfg, [switch]$SkipStore)
    if ($Cfg.authentication -ne 'UserPassword') { return $null }
    if ($Script:DeployRunVerifyCredential) { return $Script:DeployRunVerifyCredential }
    $stored = $null
    if (-not $SkipStore -and (Get-Command Get-FkhStoredCredential -ErrorAction SilentlyContinue)) {
        $stored = Get-FkhStoredCredential -Key $Cfg.server
    }
    if ($stored) {
        Write-Host "Using stored Fkh credential for $($Cfg.server)."
        $Script:DeployRunVerifyCredential = $stored
        $Script:DeployRunVerifyCredentialFromStore = $true
        return $stored
    }
    # Fail-fast: a non-interactive session (redirected stdin — an unattended/automated
    # invocation) can never answer a console Get-Credential prompt; it would otherwise hang
    # indefinitely. Surface a clear, actionable error instead.
    if ([Console]::IsInputRedirected) {
        throw ("UserPassword credential required for $($Cfg.server), no stored credential found, and " +
            "this session is non-interactive (redirected input) — cannot prompt. Populate the Fkh " +
            "credential store with one interactive run first, or seed it via Save-FkhCredential.")
    }
    $Script:DeployRunVerifyCredential = Get-Credential -Message "Credentials for $($Cfg.server)/$($Cfg.serverInstance)"
    if (-not $Script:DeployRunVerifyCredential) { throw 'Credential entry was cancelled; UserPassword authentication requires one.' }
    $Script:DeployRunVerifyCredentialFromStore = $false
    return $Script:DeployRunVerifyCredential
}

function Reset-DeployRunVerifyCredential {
    # Forces the next Get-DeployRunVerifyCredential call to re-prompt (used after a
    # connection attempt never reaches stage='ran' — see Invoke-DeployRunVerifyRun).
    $Script:DeployRunVerifyCredential = $null
    $Script:DeployRunVerifyCredentialFromStore = $false
}

function Invoke-DeployRunVerifyRunOnce {
    # Single connection+test attempt against the given credential. Split out of
    # Invoke-DeployRunVerifyRun so the retry loop there never re-materializes the runner.
    param([Parameter(Mandatory)]$Cfg, $Credential)
    $pwsh = (Get-Process -Id $PID).Path
    $runnerDir = Initialize-DeployRunVerifyRunner -Cfg $Cfg
    $log = Join-Path $runnerDir 'progress.log'
    $resultJson = Join-Path $runnerDir '_result.json'
    foreach ($f in @($log, $resultJson)) { if (Test-Path $f) { Remove-Item $f -Force } }
    $credential = $Credential

    $vars = @{ dir = $runnerDir; glue = $Cfg.glueDir; url = $Cfg.serviceUrl; ext = $Cfg.testExtensionId; range = $Cfg.testCodeunitRange; suite = $Cfg.testSuite; auth = $Cfg.authentication } | ConvertTo-Json -Compress
    $b64vars = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($vars))

    $bootstrap = @'
$ErrorActionPreference = 'Stop'
$cfg = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($env:APRODA_TL_VARS)) | ConvertFrom-Json
$dir = $cfg.dir; $glue = $cfg.glue
$log = Join-Path $dir 'progress.log'; $resultJson = Join-Path $dir '_result.json'
function Note($m) { ("{0}  {1}" -f (Get-Date -Format HH:mm:ss.fff), $m) | Out-File -FilePath $log -Append -Encoding UTF8 }
function global:Write-Log { Note ('[LOG] ' + ($args -join ' ')) }
$res = [ordered]@{ stage='start'; ok=$false; error=''; console=''; xml='' }; Note 'start'
try {
    # SRP-safe glue loading: some machines block path-based script execution (.ps1/.psm1)
    # under the workspace via Software Restriction Policy / Group Policy. So we NEVER
    # dot-source the glue by path; we read its content and run it via [ScriptBlock]::Create
    # (content execution is SRP-exempt). The 4 client DLLs are Add-Type'd FIRST because the
    # canonical ClientContext class references Microsoft.Dynamics.Framework.UI.Client.* types
    # at PARSE time of its method bodies.
    $clientDll = Join-Path $dir 'Microsoft.Dynamics.Framework.UI.Client.dll'
    $newtonDll = Join-Path $dir 'Newtonsoft.Json.dll'
    $antiSSRF  = Join-Path $dir 'Microsoft.Internal.AntiSSRF.dll'
    Add-Type -Path $newtonDll
    if (Test-Path $antiSSRF) { Add-Type -Path $antiSSRF }
    Add-Type -Path $clientDll

    $ccSrc   = Get-Content (Join-Path $glue 'ClientContext.ps1') -Raw
    $pstfSrc = Get-Content (Join-Path $glue 'PsTestFunctions.ps1') -Raw
    # Neutralize PsTestFunctions' internal path-based dot-source of ClientContext (would hit SRP);
    # we have already loaded ClientContext content-safe above.
    $pstfSrc = [regex]::Replace($pstfSrc, '(?m)^\s*\.\s+\$clientContextScriptPath\b.*$', '# (ClientContext loaded by engine bootstrap)')
    $arSrc   = Get-Content (Join-Path $glue 'AprodaRunner.ps1') -Raw

    . ([ScriptBlock]::Create($ccSrc)) -clientDllPath $clientDll
    . ([ScriptBlock]::Create($pstfSrc)) -clientDllPath $clientDll -newtonSoftDllPath $newtonDll -clientContextScriptPath (Join-Path $glue 'ClientContext.ps1')
    . ([ScriptBlock]::Create($arSrc))
    $resultPath = Join-Path $dir 'TestResults.xml'
    if (Test-Path $resultPath) { Remove-Item $resultPath -Force }
    Note ("running Run-AlTests ({0}, auth={1})..." -f $cfg.range, $cfg.auth)
    $childCredential = $null
    if ($cfg.auth -eq 'UserPassword' -and $env:APRODA_TL_USER -and $env:APRODA_TL_PWD) {
        $childCredential = [System.Management.Automation.PSCredential]::new($env:APRODA_TL_USER, ($env:APRODA_TL_PWD | ConvertTo-SecureString))
    }
    $console = & {
        if ($childCredential) {
            Run-AlTests -ServiceUrl $cfg.url -AutorizationType 'UserPassword' -Credential $childCredential -ExtensionId $cfg.ext `
                -TestCodeunitsRange $cfg.range -TestSuite $cfg.suite -SaveResultFile $true `
                -ResultsFilePath $resultPath -Detailed $true
        }
        else {
            Run-AlTests -ServiceUrl $cfg.url -AutorizationType $cfg.auth -ExtensionId $cfg.ext `
                -TestCodeunitsRange $cfg.range -TestSuite $cfg.suite -SaveResultFile $true `
                -ResultsFilePath $resultPath -Detailed $true
        }
    } *>&1 | Out-String
    $res.stage='ran'; $res.console=$console; Note 'ran'
    if (Test-Path $resultPath) { $res.xml = Get-Content $resultPath -Raw } else { $res.xml = 'NO-RESULT-FILE' }
    $res.ok = $true
} catch { $res.error = $_.Exception.ToString(); Note ('ERROR: ' + $_.Exception.Message) }
$res | ConvertTo-Json -Depth 6 -Compress | Out-File -FilePath $resultJson -Encoding UTF8; Note 'result-written'
'@
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($bootstrap))
    $env:APRODA_TL_VARS = $b64vars
    if ($credential) {
        # DPAPI-protected (current user + machine only), never plaintext; cleared below.
        $env:APRODA_TL_USER = $credential.UserName
        $env:APRODA_TL_PWD = $credential.Password | ConvertFrom-SecureString
    }
    else {
        Remove-Item Env:\APRODA_TL_USER -ErrorAction SilentlyContinue
        Remove-Item Env:\APRODA_TL_PWD -ErrorAction SilentlyContinue
    }
    Write-Host "Running AL tests via $($Cfg.serviceUrl) (range $($Cfg.testCodeunitRange))..."
    $p = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) -PassThru -NoNewWindow
    if (-not $p.WaitForExit([int]$Cfg.runTimeoutMs)) { Write-Host "TIMEOUT - killing $($p.Id)"; try { $p.Kill($true) } catch { $p.Kill() } }
    Remove-Item Env:\APRODA_TL_USER -ErrorAction SilentlyContinue
    Remove-Item Env:\APRODA_TL_PWD -ErrorAction SilentlyContinue

    if (-not (Test-Path $resultJson)) { Write-Host "NO-RESULT-JSON"; return $null }
    $obj = Get-Content $resultJson -Raw | ConvertFrom-Json
    return Get-DeployRunVerifySummary -ResultObject $obj
}

# ---------------------------------------------------------------------------
# Run: at most 2 attempts. "ClientSession State is Uninitialized" (stage never reaches
# 'ran') is an AMBIGUOUS signal — live-confirmed (2026-09-13) to mean the connection never
# came up at all, which can be wrong credentials but just as easily network/service/company
# — there is no reliable text to distinguish them. So: one retry with a freshly re-prompted
# credential is cheap and often fixes a typo; a second consecutive failure is a real
# blocker, not brute-forced further. A run that DOES reach 'ran' (regardless of pass/fail
# counts) proves the credential worked — it is then saved/updated in the store
# unconditionally, no confirmation prompt (explicit decision, D-43 addendum).
# ---------------------------------------------------------------------------
function Invoke-DeployRunVerifyRun {
    param([Parameter(Mandatory)]$Cfg)
    $maxAttempts = 2
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $credential = Get-DeployRunVerifyCredential -Cfg $Cfg -SkipStore:($attempt -gt 1)
        $summary = Invoke-DeployRunVerifyRunOnce -Cfg $Cfg -Credential $credential
        if (-not $summary) { return $summary }

        if ($summary.Stage -eq 'ran') {
            if ($Cfg.authentication -eq 'UserPassword' -and -not $Script:DeployRunVerifyCredentialFromStore -and
                (Get-Command Save-FkhCredential -ErrorAction SilentlyContinue)) {
                Save-FkhCredential -Key $Cfg.server -Credential $credential
                Write-Host "Fkh-Credential-Store aktualisiert: $($Cfg.server)"
            }
            return $summary
        }

        if ($attempt -lt $maxAttempts -and $Cfg.authentication -eq 'UserPassword') {
            Write-Warning ("Verbindung zu $($Cfg.server) kam nicht zustande (evtl. falsches Passwort - kann aber auch " +
                "Netzwerk/Service/Company sein). Erneuter Versuch mit neu abgefragten Zugangsdaten...")
            Reset-DeployRunVerifyCredential
            continue
        }
        return $summary
    }
}

# ---------------------------------------------------------------------------
# Summary: parse XUnit-style TestResults.xml into pass/fail counts + failures
# ---------------------------------------------------------------------------
function Get-DeployRunVerifySummary {
    param([Parameter(Mandatory)]$ResultObject)
    $summary = [ordered]@{ Stage = $ResultObject.stage; Ok = $ResultObject.ok; Total = 0; Passed = 0; Failed = 0; Skipped = 0; Failures = @() }
    if ($ResultObject.error) { $summary.Error = $ResultObject.error }
    if ($ResultObject.xml -and $ResultObject.xml -ne 'NO-RESULT-FILE') {
        try {
            [xml]$x = $ResultObject.xml
            $tests = $x.SelectNodes('//test')
            foreach ($t in $tests) {
                $summary.Total++
                if ($t.result -eq 'Pass') { $summary.Passed++ } else { $summary.Failed++; $summary.Failures += $t.name }
            }
        }
        catch { $summary.Error = "XML parse failed: $($_.Exception.Message)" }
    }
    [pscustomobject]$summary
}

# ---------------------------------------------------------------------------
# Test route (E-010 spec 6.6): altool runtests --testgroups first, web-client runner second.
# ---------------------------------------------------------------------------
function Get-DeployRunVerifyTestCodeunits {
    # Test codeunits of the test app inside the range. Returns { Codeunits [int[]]; Reason }.
    # Reason RANGE_UNSUPPORTED / MULTI_OBJECT_FILE means: use the web-client runner.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectDir, [Parameter(Mandatory)][AllowEmptyString()][string]$Range)
    $unsupported = { param($Reason) [pscustomobject]@{ Codeunits = [int[]]@(); Reason = $Reason } }

    $spans = [System.Collections.Generic.List[object]]::new()
    foreach ($token in ($Range -split '\|')) {
        $text = $token.Trim()
        if ($text -match '^(?<a>\d+)$') { $spans.Add([pscustomobject]@{ From = [long]$Matches['a']; To = [long]$Matches['a'] }) }
        elseif ($text -match '^(?<a>\d+)\.\.(?<b>\d+)$' -and [long]$Matches['a'] -le [long]$Matches['b']) { $spans.Add([pscustomobject]@{ From = [long]$Matches['a']; To = [long]$Matches['b'] }) }
        else { return (& $unsupported 'RANGE_UNSUPPORTED') }
    }

    $found = [System.Collections.Generic.SortedSet[int]]::new()
    $files = @(Get-ChildItem -LiteralPath $ProjectDir -Recurse -Filter '*.al' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName.Substring($ProjectDir.Length) -notmatch '(^|[\\/])\.(alpackages|snapshots|output)([\\/]|$)' })
    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if ([string]::IsNullOrEmpty($content)) { continue }
        $declarations = [regex]::Matches($content, '(?im)^\s*codeunit\s+(?<id>\d+)\s')
        if ($declarations.Count -gt 1) { return (& $unsupported 'MULTI_OBJECT_FILE') }
        if ($declarations.Count -eq 0) { continue }
        if ($content -notmatch '(?i)\bSubtype\s*=\s*Test\s*;') { continue }
        $id = [long]$declarations[0].Groups['id'].Value
        if (@($spans | Where-Object { $id -ge $_.From -and $id -le $_.To }).Count -gt 0) { [void]$found.Add([int]$id) }
    }
    return [pscustomobject]@{ Codeunits = [int[]]@($found); Reason = $null }
}

function ConvertFrom-DeployRunVerifyAlToolJson {
    # The result object is the first line starting with '{' from which a JSON object with a
    # 'succeeded' property parses; diagnostic noise before (or after) it is ignored.
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $lines = $Text -split '\r?\n'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $lines[$i].TrimStart().StartsWith('{')) { continue }
        $candidate = ($lines[$i..($lines.Count - 1)] -join "`n")
        $start = $candidate.IndexOf('{')
        $depth = 0; $inString = $false; $escaped = $false; $end = -1
        for ($j = $start; $j -lt $candidate.Length; $j++) {
            $c = $candidate[$j]
            if ($inString) {
                if ($escaped) { $escaped = $false } elseif ($c -eq '\') { $escaped = $true } elseif ($c -eq '"') { $inString = $false }
                continue
            }
            if ($c -eq '"') { $inString = $true } elseif ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $j; break } }
        }
        if ($end -lt 0) { continue }
        try { $parsed = $candidate.Substring($start, $end - $start + 1) | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        if ($null -ne $parsed.PSObject.Properties['succeeded']) { return $parsed }
    }
    return $null
}

function Get-DeployRunVerifyTestRecords {
    # data.results records that carry a method name; the blank-method completion records are dropped.
    param($Json)
    $data = Get-DeployRunVerifyProperty -Object $Json -Name 'data'
    $results = @(Get-DeployRunVerifyProperty -Object $data -Name 'results' -Default @())
    return @($results | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-DeployRunVerifyProperty -Object $_ -Name 'methodName' -Default '')) })
}

function Get-DeployRunVerifyTestOutcome {
    # Classifies a `runtests` run (spec 6.6). Returns { Outcome; Reason; Json }.
    # Green | Red | AuthFailure | Incomplete | InvocationFailure. altool strings are PROVISIONAL (OS-1, L-4b.12).
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Output = '',
        [int]$ExitCode = 0,
        [switch]$TimedOut,
        [string]$LaunchError,
        [int[]]$RequestedCodeunits = @()
    )
    $result = { param($Outcome, $Reason, $Json) [pscustomobject]@{ Outcome = $Outcome; Reason = $Reason; Json = $Json } }
    if ($LaunchError) { return (& $result 'InvocationFailure' "altool could not be started: $(ConvertTo-DeployRunVerifyRedactedText -Text $LaunchError)" $null) }
    if ($TimedOut) { return (& $result 'InvocationFailure' 'altool runtests timed out' $null) }

    $json = ConvertFrom-DeployRunVerifyAlToolJson -Text $Output
    if ($null -eq $json) {
        if ($Output -match 'UserNotAuthenticated') { return (& $result 'AuthFailure' 'UserNotAuthenticated' $null) }
        return (& $result 'InvocationFailure' "no parseable result JSON (exit $ExitCode)" $null)
    }

    $errorDetails = Get-DeployRunVerifyProperty -Object $json -Name 'errorDetails'
    $errorCode = [string](Get-DeployRunVerifyProperty -Object $errorDetails -Name 'code' -Default '')
    $errorText = if ($errorDetails) { ($errorDetails | ConvertTo-Json -Depth 5 -Compress) } else { '' }
    if (-not [bool]$json.succeeded) {
        if ($errorCode -eq 'TestRunFailed') { return (& $result 'Red' 'TestRunFailed' $json) }
        if ($errorText -match 'UserNotAuthenticated' -or $Output -match 'UserNotAuthenticated') { return (& $result 'AuthFailure' 'UserNotAuthenticated' $json) }
        $detail = if ($errorCode) { $errorCode } else { 'succeeded=false' }
        return (& $result 'InvocationFailure' "altool reported $detail" $json)
    }

    $records = @(Get-DeployRunVerifyTestRecords -Json $json)
    if ($records.Count -eq 0) { return (& $result 'Incomplete' 'no test results (empty run)' $json) }
    $present = @($records | ForEach-Object { [string](Get-DeployRunVerifyProperty -Object $_ -Name 'codeunitId' -Default '') } | Sort-Object -Unique)
    $missing = @($RequestedCodeunits | Where-Object { [string]$_ -notin $present })
    if ($missing.Count -gt 0) { return (& $result 'Incomplete' "requested codeunit(s) missing from the result: $($missing -join ', ')" $json) }
    $failed = @($records | Where-Object { [string](Get-DeployRunVerifyProperty -Object $_ -Name 'status' -Default '') -notmatch '^(?i)(pass|skip)' })
    return (& $result $(if ($failed.Count -gt 0) { 'Red' } else { 'Green' }) '' $json)
}

function ConvertTo-DeployRunVerifyTestSummary {
    # Normalizes a runtests JSON into the existing summary shape (counts from non-empty methodName only).
    param([Parameter(Mandatory)]$Json)
    $summary = [ordered]@{ Stage = 'ran'; Ok = $true; Total = 0; Passed = 0; Failed = 0; Skipped = 0; Failures = @(); FailureDetails = @() }
    foreach ($record in @(Get-DeployRunVerifyTestRecords -Json $Json)) {
        $status = [string](Get-DeployRunVerifyProperty -Object $record -Name 'status' -Default '')
        $name = '{0}:{1}' -f (Get-DeployRunVerifyProperty -Object $record -Name 'codeunitId' -Default '?'), (Get-DeployRunVerifyProperty -Object $record -Name 'methodName')
        $summary.Total++
        if ($status -match '^(?i)pass') { $summary.Passed++ }
        elseif ($status -match '^(?i)skip') { $summary.Skipped++ }
        else {
            # fail* and any unknown status count as failed
            $summary.Failed++
            $summary.Failures += $name
            $summary.FailureDetails += [pscustomobject]@{ Test = $name; Status = $status; Output = [string](Get-DeployRunVerifyProperty -Object $record -Name 'output' -Default '') }
        }
    }
    return [pscustomobject]$summary
}

function Select-DeployRunVerifyTestRoute {
    # Decides the test route up front. Returns { Route = altool|webClient; Reason; Codeunits; AlTool }.
    param([Parameter(Mandatory)]$Cfg)
    $webClient = { param($Reason) [pscustomobject]@{ Route = 'webClient'; Reason = $Reason; Codeunits = [int[]]@(); AlTool = $null } }
    $suite = [string](Get-DeployRunVerifyProperty -Object $Cfg -Name 'testSuite' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($suite) -and $suite -ine 'DEFAULT') { return (& $webClient 'TESTSUITE_SET') }
    if ([string]::IsNullOrWhiteSpace([string](Get-DeployRunVerifyProperty -Object $Cfg -Name 'companyName' -Default ''))) { return (& $webClient 'COMPANY_EMPTY') }
    if ($Script:DeployRunVerifyPinnedLegacy.ContainsKey('Tests')) { return (& $webClient "pinned after failure: $($Script:DeployRunVerifyPinnedLegacy['Tests'])") }
    $alTool = Get-DeployRunVerifyAlTool
    if (-not $alTool.Path) { return (& $webClient "altool unavailable ($($alTool.Error))") }
    $caps = Get-DeployRunVerifyAlToolCapabilities -AlTool $alTool
    if (-not $caps.RunTests) { return (& $webClient 'altool has no runtests command') }
    if (-not $caps.TestGroups) { return (& $webClient 'altool runtests has no --testgroups option') }
    $testApp = @($Cfg.apps)[-1]
    $selection = Get-DeployRunVerifyTestCodeunits -ProjectDir $testApp.ProjectDir -Range ([string]$Cfg.testCodeunitRange)
    if ($selection.Reason) { return (& $webClient $selection.Reason) }
    if (@($selection.Codeunits).Count -eq 0) { return (& $webClient 'NO_TEST_CODEUNITS') }
    return [pscustomobject]@{ Route = 'altool'; Reason = ''; Codeunits = [int[]]@($selection.Codeunits); AlTool = $alTool }
}

function Invoke-DeployRunVerifyAlToolTestRun {
    # One runtests process: groups file, raw stdout kept, classified. Returns { Outcome; Reason; Json }.
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)]$Decision, $Credential)
    $bundle = $Cfg.targetBundle
    $testApp = @($Cfg.apps)[-1]
    $workDir = Join-Path $Cfg.runnerDirFull '_altool'
    if (-not (Test-Path -LiteralPath $workDir)) { New-Item -ItemType Directory -Path $workDir -Force | Out-Null }
    $groupFile = Join-Path $workDir 'testgroups.json'
    $groups = @($Decision.Codeunits | ForEach-Object { [ordered]@{ codeunitId = [int]$_ } })
    [System.IO.File]::WriteAllText($groupFile, (ConvertTo-Json -InputObject $groups -Depth 3), [System.Text.UTF8Encoding]::new($false))

    $arguments = @('runtests', '--testgroups', $groupFile, '--project', [string]$testApp.ProjectDir, '--company', [string]$Cfg.companyName,
        '--server', [string]$bundle.ServerUrl, '--serverinstance', [string]$bundle.ServerInstance, '--port', [string]$bundle.Port,
        '--authentication', [string]$bundle.Authentication, '--tenant', [string]$bundle.Tenant, '--environmenttype', 'OnPrem')
    Write-Host "Running AL tests via altool runtests (codeunits $($Decision.Codeunits -join ', '))..."
    $splat = @{}
    if ($null -ne $Credential) { $splat.Credential = $Credential }
    $call = Invoke-DeployRunVerifyAlTool -AlTool $Decision.AlTool -Arguments $arguments -TimeoutMs ([int]$Cfg.runTimeoutMs) @splat
    [System.IO.File]::WriteAllText((Join-Path $workDir 'runtests.out.txt'), [string]$call.StdOut, [System.Text.UTF8Encoding]::new($false))
    $launchError = [string](Get-DeployRunVerifyProperty -Object $call -Name 'LaunchError' -Default '')
    return Get-DeployRunVerifyTestOutcome -Output ([string]$call.StdOut) -ExitCode ([int]$call.ExitCode) -TimedOut:([bool]$call.TimedOut) -LaunchError $launchError -RequestedCodeunits $Decision.Codeunits
}

function Invoke-DeployRunVerifyTests {
    # Test step: route choice, altool run with the D-43 auth retry, fallback to the web-client runner
    # only on InvocationFailure / Incomplete. A red result is a result, never a trigger.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Cfg)
    $policy = Get-DeployRunVerifyRoutePolicy -Cfg $Cfg -Step Tests
    if ($policy -eq 'webClient') {
        Set-DeployRunVerifyRoute -Step Tests -Route webClient -Reason 'forced (TEST_ROUTE)'
        return Invoke-DeployRunVerifyRun -Cfg $Cfg
    }
    $decision = Select-DeployRunVerifyTestRoute -Cfg $Cfg
    if ($decision.Route -eq 'webClient') {
        if ($policy -eq 'altool') { throw "ROUTE_UNAVAILABLE: tests=altool ($($decision.Reason))" }
        Set-DeployRunVerifyRoute -Step Tests -Route webClient -Reason $decision.Reason -Fallback
        return Invoke-DeployRunVerifyRun -Cfg $Cfg
    }

    $maxAttempts = 2
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $credential = $null
        if ($Cfg.authentication -eq 'UserPassword') { $credential = Get-DeployRunVerifyCredential -Cfg $Cfg -SkipStore:($attempt -gt 1) }
        $splat = @{}
        if ($null -ne $credential) { $splat.Credential = $credential }
        $run = Invoke-DeployRunVerifyAlToolTestRun -Cfg $Cfg -Decision $decision @splat
        if ($run.Outcome -in @('Green', 'Red')) {
            Set-DeployRunVerifyRoute -Step Tests -Route altool
            Save-DeployRunVerifyCredentialAfterSuccess -Cfg $Cfg -Credential $credential
            return (ConvertTo-DeployRunVerifyTestSummary -Json $run.Json)
        }
        if ($run.Outcome -eq 'AuthFailure') {
            if ($attempt -lt $maxAttempts -and $Cfg.authentication -eq 'UserPassword') {
                Write-Warning "Authentication for $($Cfg.server) was refused. Retrying once with a freshly prompted credential..."
                Reset-DeployRunVerifyCredential
                continue
            }
            throw "TESTS_AUTH_FAILED: $($Cfg.server) refused the credentials ($($Cfg.authentication)). Check the account; no other route is tried."
        }
        # InvocationFailure / Incomplete: the only fallback triggers.
        if ($policy -eq 'altool') { throw "ROUTE_UNAVAILABLE: tests=altool ($($run.Reason))" }
        $Script:DeployRunVerifyPinnedLegacy['Tests'] = $run.Reason
        Set-DeployRunVerifyRoute -Step Tests -Route webClient -Reason "$($run.Outcome): $($run.Reason)" -Fallback
        return Invoke-DeployRunVerifyRun -Cfg $Cfg
    }
}

# ---------------------------------------------------------------------------
# Orchestrator: Build -> Deploy -> Run. (The fix step is the agent's job.)
# Modes: full | -BuildOnly | -SkipBuild | -RunOnly (tests only: service preflight, no dependency
# check, no publish). -DeployRoute / -TestRoute force a route for comparisons and live validation;
# a forced route that is unavailable stops with ROUTE_UNAVAILABLE instead of falling back.
# ---------------------------------------------------------------------------
function Format-DeployRunVerifyTiming {
    param($Elapsed, [string]$Missing = 'skipped')
    if ($null -eq $Elapsed) { return $Missing }
    return ('{0:N1}s' -f $Elapsed.TotalSeconds)
}

function Get-DeployRunVerifyRouteReport {
    # Routes + altool for the summary object; prints ROUTE: and one ROUTE-FALLBACK: line per fallback.
    $routes = [pscustomobject]@{
        Build  = $Script:DeployRunVerifyRoutes['Build']
        Deploy = $Script:DeployRunVerifyRoutes['Deploy']
        Tests  = $Script:DeployRunVerifyRoutes['Tests']
    }
    $alTool = Get-DeployRunVerifyAlTool
    Write-Host ("ROUTE: build={0} {3} deploy={1} {3} tests={2}" -f $routes.Build.Route, $routes.Deploy.Route, $routes.Tests.Route, [char]0x00B7)
    foreach ($line in $Script:DeployRunVerifyFallbacks) { Write-Host $line }
    return [pscustomobject]@{
        Routes = $routes
        AlTool = [pscustomobject]@{ Path = $alTool.Path; Version = $alTool.Version; Source = $alTool.Source }
    }
}

function Invoke-AprodaDeployRunVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [switch]$BuildOnly,
        [switch]$SkipBuild,
        [switch]$RunOnly,
        [switch]$ForceUpgrade,
        [ValidateSet('auto', 'altool', 'devEndpoint')][string]$DeployRoute = 'auto',
        [ValidateSet('auto', 'altool', 'webClient')][string]$TestRoute = 'auto'
    )
    Reset-DeployRunVerifyRunState
    $cfg = Resolve-DeployRunVerifyConfig -ConfigPath $ConfigPath -BuildOnly:$BuildOnly
    $cfg | Add-Member deployRoute $DeployRoute -Force
    $cfg | Add-Member testRoute $TestRoute -Force
    $totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $timings = [ordered]@{ Build = $null; Deploy = $null; Tests = $null }
    $hasTarget = $cfg.adapter -ne 'none'
    if ($hasTarget) {
        Write-Host "Server $($cfg.server)/$($cfg.serverInstance)  tenant=$($cfg.tenant)  adapter=$($cfg.adapter)  auth=$($cfg.authentication)"
    }
    Write-Host ("Apps: " + (($cfg.apps | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ' -> '))

    if ($hasTarget) {
        $pf = Test-DeployRunVerifyPreflight -Cfg $cfg
        if (-not $pf.Reachable) {
            Write-Warning "BC service '$($cfg.server)' not reachable. Quality is higher with a Cronus BC environment incl. Test Toolkit. Without a service only static validation (build) is possible — no runtime verification."
            if ($cfg.onServiceUnavailable -eq 'abort') { throw "Service unavailable and onServiceUnavailable=abort." }
            $BuildOnly = $true
        }
    }

    if (-not $SkipBuild -and -not $RunOnly) {
        $stageTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-DeployRunVerifyBuild -Cfg $cfg | Out-Null
        $stageTimer.Stop()
        $timings.Build = $stageTimer.Elapsed
    }
    if ($BuildOnly) {
        $totalTimer.Stop()
        Write-Host "BUILD-ONLY: skipping deploy + run."
        Write-Host ("TIMING: build={0} · deploy=n/a · tests=n/a · total={1}" -f (Format-DeployRunVerifyTiming $timings.Build), (Format-DeployRunVerifyTiming $totalTimer.Elapsed))
        $report = Get-DeployRunVerifyRouteReport
        return [pscustomobject]@{ BuildOnly = $true; Timings = [pscustomobject]$timings; TotalDuration = $totalTimer.Elapsed; Routes = $report.Routes; AlTool = $report.AlTool }
    }

    if (-not $RunOnly) {
        Test-DeployRunVerifyTargetDependencies -Cfg $cfg

        $stageTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-DeployRunVerifyPublish -Cfg $cfg -ForceUpgrade:$ForceUpgrade | Out-Null
        $stageTimer.Stop()
        $timings.Deploy = $stageTimer.Elapsed
    }

    $stageTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $summary = Invoke-DeployRunVerifyTests -Cfg $cfg
    $stageTimer.Stop()
    $timings.Tests = $stageTimer.Elapsed
    $totalTimer.Stop()
    if ($summary) {
        Write-Host ("RESULT: {0}/{1} passed, {2} failed." -f $summary.Passed, $summary.Total, $summary.Failed)
        if ($summary.Failed -gt 0) { Write-Host ("FAILURES: " + ($summary.Failures -join ', ')) }
        $summary | Add-Member Timings ([pscustomobject]$timings) -Force
        $summary | Add-Member TotalDuration $totalTimer.Elapsed -Force
    }
    Write-Host ("TIMING: build={0} · deploy={1} · tests={2} · total={3}" -f (Format-DeployRunVerifyTiming $timings.Build), (Format-DeployRunVerifyTiming $timings.Deploy), (Format-DeployRunVerifyTiming $timings.Tests), (Format-DeployRunVerifyTiming $totalTimer.Elapsed))
    $report = Get-DeployRunVerifyRouteReport
    if ($summary) {
        $summary | Add-Member Routes $report.Routes -Force
        $summary | Add-Member AlTool $report.AlTool -Force
    }
    return $summary
}

Export-ModuleMember -Function Resolve-DeployRunVerifyConfig, Test-DeployRunVerifyPreflight, Invoke-DeployRunVerifyBuild,
Invoke-DeployRunVerifyPublish, Invoke-DeployRunVerifyPublishApp, Publish-DeployRunVerifyDevEndpoint, Get-DeployRunVerifyPublishOutcome,
New-DeployRunVerifyBasicAuthorization, Get-DeployRunVerifySchemaMode, Invoke-DeployRunVerifyAlTool, Get-DeployRunVerifyAlToolCapabilities,
ConvertFrom-DeployRunVerifyAlToolHelp, Get-DeployRunVerifyAlTool, Reset-DeployRunVerifyRunState,
Invoke-DeployRunVerifyTests, Get-DeployRunVerifyTestCodeunits, ConvertFrom-DeployRunVerifyAlToolJson, Get-DeployRunVerifyTestOutcome,
ConvertTo-DeployRunVerifyTestSummary, Select-DeployRunVerifyCleanupCandidates, Get-DeployRunVerifyCleanupCandidates, Remove-DeployRunVerifyAppVersion,
Invoke-DeployRunVerifyRun,
Invoke-DeployRunVerifyRunOnce, Get-DeployRunVerifySummary, Invoke-AprodaDeployRunVerify, Get-DeployRunVerifyAdapter,
Get-DeployRunVerifyFkhBackendUrl, Resolve-DeployRunVerifyFkhContainer, Get-DeployRunVerifyCredential,
Reset-DeployRunVerifyCredential,
Resolve-DeployRunVerifyRunner, New-DeployRunVerifyRunner, Initialize-DeployRunVerifyRunner, Copy-DeployRunVerifyRunnerFromServer,
Resolve-DeployRunVerifyClientSource, Get-DeployRunVerifyServerVersion, Get-DeployRunVerifyRunnerVersion,
Test-DeployRunVerifyTargetDependencies, Install-DeployRunVerifyResolvedDependency, Get-DeployRunVerifyAppManifestDependencies,
Get-DeployRunVerifyInstalledAppsFkh, Get-DeployRunVerifyInstalledAppsAsinst
