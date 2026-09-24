<#
.SYNOPSIS
  Aproda Deploy-Run-Verify engine — Build -> Deploy -> Run for AL BC (OnPrem NST via ASINST,
  or an AKS container via Fkh). IMMUTABLE TEMPLATE. Do NOT edit per project; drive it via
  deploy-run-verify.config.jsonc.
  Derived from the proven Test/PowerShell/_Cycle.ps1 + _RunTests.ps1 (Audit Trail 26/26).
.NOTES
    Status: the ASINST adapter is live-verified across multiple projects. The Fkh adapter
    (Invoke-DeployRunVerifyDeployFkh) is live-verified through this entry point against a
    companion app (26/26 passed; see D-36).
#>

Set-StrictMode -Version Latest

# Initialized up front: Set-StrictMode throws on a never-assigned Script-scope variable,
# and Get-DeployRunVerifyCredential's cache check reads this before any UserPassword run.
$Script:DeployRunVerifyCredential = $null
$Script:DeployRunVerifyCredentialFromStore = $false

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
# Config resolution: merge deploy-run-verify.config.jsonc + launch.json + each app.json
# ---------------------------------------------------------------------------
function Resolve-DeployRunVerifyConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath" }
    $cfgDir = Split-Path -Parent (Resolve-Path $ConfigPath)

    # Strip // and /* */ comments, then parse. Lookbehind keeps URL '://' intact.
    $raw = Get-Content $ConfigPath -Raw
    $raw = [regex]::Replace($raw, '(?m)(?<!:)//.*?$', '')
    $raw = [regex]::Replace($raw, '(?s)/\*.*?\*/', '')
    $cfg = $raw | ConvertFrom-Json

    # --- launch.json (server/instance/tenant) ---
    if ([string]::IsNullOrWhiteSpace($cfg.server)) {
        $launchPath = Join-Path $cfgDir '.vscode\launch.json'
        if (Test-Path $launchPath) {
            $lj = (Get-Content $launchPath -Raw) -replace '(?m)(?<!:)//.*?$', '' | ConvertFrom-Json
            $configs = @($lj.configurations | Where-Object { $_.server })
            $pick = $null
            if ($cfg.launchConfig) { $pick = $configs | Where-Object { $_.name -eq $cfg.launchConfig } | Select-Object -First 1 }
            elseif ($configs.Count -eq 1) { $pick = $configs[0] }
            if ($pick) {
                $cfg.server = ($pick.server -replace '^https?://', '').TrimEnd('/')
                if (-not $cfg.serverInstance) { $cfg | Add-Member serverInstance $pick.serverInstance -Force }
                if (-not $cfg.tenant -and $pick.tenant) { $cfg.tenant = $pick.tenant }
                if (-not ($cfg.PSObject.Properties.Name -contains 'scheme')) { $cfg | Add-Member scheme '' -Force }
                if ([string]::IsNullOrWhiteSpace($cfg.scheme)) { $cfg.scheme = if ($pick.server -match '^https:') { 'https' } else { 'http' } }
                if (-not ($cfg.PSObject.Properties.Name -contains 'authentication')) { $cfg | Add-Member authentication '' -Force }
                if ([string]::IsNullOrWhiteSpace($cfg.authentication) -and $pick.authentication) { $cfg.authentication = [string]$pick.authentication }
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($cfg.server)) { throw "server/serverInstance unresolved — set them in config or provide a launch.json 'server' configuration." }
    if ([string]::IsNullOrWhiteSpace($cfg.tenant)) { $cfg.tenant = 'default' }
    # Adapter classification is mechanical and hostname-based (D-26): scheme and authentication
    # default here when neither the config nor a launch.json pick supplied them (e.g. an
    # explicit server override without a launchConfig).
    if (-not ($cfg.PSObject.Properties.Name -contains 'scheme') -or [string]::IsNullOrWhiteSpace($cfg.scheme)) { $cfg | Add-Member scheme 'http' -Force }
    if (-not ($cfg.PSObject.Properties.Name -contains 'authentication') -or [string]::IsNullOrWhiteSpace($cfg.authentication)) { $cfg | Add-Member authentication 'Windows' -Force }
    $cfg | Add-Member adapter (Get-DeployRunVerifyAdapter -Cfg $cfg) -Force

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
    if (-not [string]::IsNullOrWhiteSpace($cfg.companyName)) {
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

    # FKH Dev Endpoint uses Add as the non-destructive synchronize mode. ForceSync remains
    # available only for an explicitly selected destructive schema synchronization.
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
    # Returns the runner dir to use; validates client DLL major.minor == target BC version.
    param([Parameter(Mandatory)]$Cfg)
    $base = $Cfg.runnerDirFull

    # Target BC version: explicit config override > live server > (none = trust whatever DLL is present).
    $target = ConvertTo-DeployRunVerifyMajorMinor $Cfg.bcVersion
    if (-not $target) { $target = ConvertTo-DeployRunVerifyMajorMinor (Get-DeployRunVerifyServerVersion -Cfg $Cfg) }

    # Candidates: versioned subfolder first, then flat base (legacy).
    $candidates = @()
    if ($target) { $candidates += (Join-Path $base $target) }
    $candidates += $base

    foreach ($dir in $candidates) {
        $rv = ConvertTo-DeployRunVerifyMajorMinor (Get-DeployRunVerifyRunnerVersion -Dir $dir)
        if (-not $rv) { continue }
        if ($target -and $rv -ne $target) {
            throw ("Runner version mismatch: '$dir' carries BC $rv but the target environment is BC $target. " +
                "Create a matching runner with: New-DeployRunVerifyRunner -RunnerBase '$base' -TargetVersion $target " +
                "-ClientFrom '<BC Service or client install folder>' -GlueFrom '$dir'.")
        }
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
        if ($_.Exception.Response) { $reachable = $true }
    }
    [pscustomobject]@{ Reachable = [bool]$reachable; ServiceUrl = $Cfg.serviceUrl }
}

# ---------------------------------------------------------------------------
# Build: each app in order; copy upstream .app symbol into downstream .alpackages
# ---------------------------------------------------------------------------
function Invoke-DeployRunVerifyBuild {
    param([Parameter(Mandatory)]$Cfg)
    $built = @()
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
        & $Cfg.alcPath /project:"$($app.ProjectDir)" /packagecachepath:"$pkg" /out:"$($app.AppFile)" /loglevel:Error
        if (-not (Test-Path $app.AppFile)) { throw "BUILD FAILED: $($app.Name) $($app.Version)" }
        $built += $app
    }
    Write-Host "Build OK ($($built.Count) app(s))."
    return $true
}

# ---------------------------------------------------------------------------
# Deploy dispatcher (D-26): routes to the adapter resolved by Get-DeployRunVerifyAdapter.
# Both branches converge back into the shared Build -> Run -> Parse stages.
# ---------------------------------------------------------------------------
function Invoke-DeployRunVerifyDeploy {
    param([Parameter(Mandatory)]$Cfg)
    switch ($Cfg.adapter) {
        'Fkh' { return Invoke-DeployRunVerifyDeployFkh -Cfg $Cfg }
        default { return Invoke-DeployRunVerifyDeployAsinst -Cfg $Cfg }
    }
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
# Deploy via FKH's Business Central Dev Endpoint. This is the standard Aproda FKH path:
# it supports same-version redeploys without uninstalling dependent apps. Global-scope
# migration is deliberately outside this engine and requires explicit human approval.
# ---------------------------------------------------------------------------
function Invoke-DeployRunVerifyDeployFkh {
    param([Parameter(Mandatory)]$Cfg)
    $backendUrl = Get-DeployRunVerifyFkhBackendUrl
    $container = Resolve-DeployRunVerifyFkhContainer -Cfg $Cfg -BackendUrl $backendUrl
    $appLabel = [string]$container.appLabel
    if ([string]::IsNullOrWhiteSpace($appLabel)) { throw 'Resolved Fkh container has no appLabel.' }
    Write-Host "Fkh target: appLabel=$appLabel"
    if ($Cfg.fkhSyncMode -eq 'ForceSync') {
        Write-Warning 'FKH deployment uses ForceSync for a destructive schema synchronization.'
    }

    foreach ($app in $Cfg.apps) {
        Write-Host "[fkh] Dev Endpoint publish $($app.Name) $($app.Version) (syncMode=$($Cfg.fkhSyncMode))"
        $out = & fkh publishapp --name $appLabel --appFile $app.AppFile --devScope --syncMode $Cfg.fkhSyncMode --sync --install --backendUrl $backendUrl 2>&1
        $fkhExitCode = $LASTEXITCODE
        $out | ForEach-Object { Write-Host "  $_" }
        if ($fkhExitCode -ne 0) {
            $fkhDiagnostic = (@($out | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join [Environment]::NewLine).Trim()
            if ([string]::IsNullOrWhiteSpace($fkhDiagnostic)) { $fkhDiagnostic = 'No diagnostic output was returned by fkh.' }
            $fkhDiagnostic = [regex]::Replace($fkhDiagnostic, '(?i)(https?://[^\s?]+)\?[^\s]+', '$1?<redacted>')
            $fkhDiagnostic = [regex]::Replace($fkhDiagnostic, '(?i)\b(token|key|secret|password)(\s*[:=]\s*)[^\s,;]+', '$1$2<redacted>')
            throw "Fkh Dev Endpoint publish failed: $($app.Name) $($app.Version) (exit code $fkhExitCode). Fkh diagnostic: $fkhDiagnostic"
        }
    }

    $notInstalled = foreach ($app in $Cfg.apps) {
        $infoRaw = & fkh getappinfo --name $appLabel --appName $app.Name --asJson --backendUrl $backendUrl
        if ($LASTEXITCODE -ne 0) { throw "Fkh getappinfo failed: $($app.Name)" }
        $info = $infoRaw | ConvertFrom-Json
        # Verified shape (2026-09-13, live capture): { container, tenant, apps: [ { AppId,
        # Name, Publisher, Version, Dependencies, ExtensionType, Scope, IsInstalled,
        # IsPublished, SyncState, NeedsUpgrade } ] }. Match the entry by version; fall back
        # to the first entry if the exact version isn't present.
        $entry = $null
        if ($info.PSObject.Properties.Name -contains 'apps') {
            $entry = @($info.apps) | Where-Object { $_.Version -eq $app.Version } | Select-Object -First 1
            if (-not $entry) { $entry = @($info.apps) | Select-Object -First 1 }
        }
        if (-not $entry) {
            Write-Warning "Fkh getappinfo returned no app entry for $($app.Name) $($app.Version) — cannot verify installed state; relying on the publish exit code only."
        }
        elseif (-not [bool]$entry.IsInstalled) {
            "$($app.Name) $($app.Version) (IsInstalled=$($entry.IsInstalled))"
        }
        elseif ($entry.PSObject.Properties.Name -contains 'SyncState' -and $entry.SyncState -and $entry.SyncState -ne 'Synced') {
            "$($app.Name) $($app.Version) (SyncState=$($entry.SyncState))"
        }
    }
    if ($notInstalled) { throw ("DEPLOY INCOMPLETE (Fkh) — not installed/synced: " + ($notInstalled -join '; ')) }
    Write-Host "Fkh deploy done."
    return $true
}

# ---------------------------------------------------------------------------
# Deploy via ASINST: uninstall reverse order, unpublish, publish/sync/install forward
# ---------------------------------------------------------------------------
function Invoke-DeployRunVerifyDeployAsinst {
    param([Parameter(Mandatory)]$Cfg)
    if ([string]::IsNullOrWhiteSpace($Cfg.mgmtDllPath)) { throw "mgmtDllPath is required for the ASINST adapter." }
    $session = New-PSSession -ComputerName $Cfg.server
    try {
        $tempDir = "C:\Temp\AprodaDeployRunVerify_$(Get-Random)"
        Invoke-Command -Session $session -ScriptBlock { param($d) New-Item -ItemType Directory $d -Force | Out-Null } -ArgumentList $tempDir
        foreach ($app in $Cfg.apps) { Copy-Item $app.AppFile -Destination $tempDir -ToSession $session -Force }

        $appMeta = $Cfg.apps | ForEach-Object { @{ Name = $_.Name; Version = $_.Version; Publisher = $_.Publisher } }
        Invoke-Command -Session $session -ScriptBlock {
            param($d, $si, $tenant, $appMeta, $mgmt)
            $ErrorActionPreference = 'Continue'
            function Log($m) { Write-Host "[deploy] $m" }
            function Step($label, $sb) { try { & $sb; Log "OK   - $label" } catch { Log "FAIL - $label :: $($_.Exception.Message)" } }
            # Robust install for a Deploy-Run-Verify cycle that redeploys the SAME version
            # with a changed schema. No localized-message parsing: escalate sync strength,
            # then data-upgrade.
            #   1) plain Install
            #   2) ForceSync -> Install  (same-version redeploy whose table set changed; the
            #      platform refuses Install against the stale synced schema. ForceSync can drop
            #      data for changed tables — acceptable/expected inside a dev loop.)
            #   3) Start-NAVAppDataUpgrade (retained data from a prior version bump)
            function InstallOrUpgrade($si, $name, $ver, $tenant) {
                try { Install-NAVApp -ServerInstance $si -Name $name -Version $ver -Tenant $tenant -ErrorAction Stop; Log "INSTALLED $name $ver"; return }
                catch { Log "install#1 failed ($name $ver): $($_.Exception.Message)" }
                try {
                    Sync-NAVApp -ServerInstance $si -Name $name -Version $ver -Tenant $tenant -Mode ForceSync -Force -ErrorAction Stop
                    Log "OK   - ForceSync $name $ver"
                    Install-NAVApp -ServerInstance $si -Name $name -Version $ver -Tenant $tenant -ErrorAction Stop
                    Log "INSTALLED (after ForceSync) $name $ver"; return
                }
                catch { Log "install#2 (post-ForceSync) failed ($name $ver): $($_.Exception.Message)" }
                Step "DataUpgrade $name $ver" { Start-NAVAppDataUpgrade -ServerInstance $si -Name $name -Version $ver -Tenant $tenant }
            }
            Import-Module $mgmt -ErrorAction Stop

            $reverse = @($appMeta); [array]::Reverse($reverse)
            foreach ($a in $reverse) {
                foreach ($inst in Get-NAVAppInfo -ServerInstance $si -Tenant $tenant -TenantSpecificProperties -Name $a.Name) {
                    Step "Uninstall $($a.Name) $($inst.Version)" { Uninstall-NAVApp -ServerInstance $si -Name $a.Name -Version $inst.Version -Tenant $tenant -Force }
                }
            }
            foreach ($a in $reverse) {
                foreach ($pub in Get-NAVAppInfo -ServerInstance $si -Name $a.Name) {
                    Step "Unpublish $($a.Name) $($pub.Version)" { Unpublish-NAVApp -ServerInstance $si -Name $a.Name -Version $pub.Version }
                }
            }
            foreach ($a in $appMeta) {
                $path = (Get-ChildItem "$d\*$($a.Name)*_$($a.Version).app" | Select-Object -First 1).FullName
                Step "Publish $($a.Name) $($a.Version)" { Publish-NAVApp -ServerInstance $si -Path $path -SkipVerification -Scope Tenant -Tenant $tenant }
                # -Mode Add may emit a benign non-terminating error ("already synced / different
                # table set") on a same-version redeploy; that is reconciled by the ForceSync
                # fallback in InstallOrUpgrade, so silence it here to keep the error stream clean.
                Step "Sync $($a.Name) $($a.Version)" { Sync-NAVApp    -ServerInstance $si -Name $a.Name -Version $a.Version -Tenant $tenant -Mode Add -ErrorAction SilentlyContinue }
                InstallOrUpgrade $si $a.Name $a.Version $tenant
            }

            Log "=== Final installed state ==="
            $names = $appMeta | ForEach-Object { $_.Name }
            $state = Get-NAVAppInfo -ServerInstance $si -Tenant $tenant -TenantSpecificProperties |
            Where-Object { $_.Name -in $names }
            $state | ForEach-Object { Write-Host ("  {0,-36} {1,-12} Installed={2}" -f $_.Name, $_.Version, $_.IsInstalled) }
            Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue

            # Fail loudly: never let the loop run tests against a half-deployed server.
            $notInstalled = foreach ($a in $appMeta) {
                $row = $state | Where-Object { $_.Name -eq $a.Name -and $_.Version -eq $a.Version } | Select-Object -First 1
                if (-not $row -or -not $row.IsInstalled) { "$($a.Name) $($a.Version)" }
            }
            # Drop benign non-terminating errors collected along the way so they don't surface
            # as a remote failure to the (ErrorAction=Stop) caller and abort before the test run.
            $Error.Clear()
            if ($notInstalled) { throw ("DEPLOY INCOMPLETE — not installed: " + ($notInstalled -join '; ')) }
        } -ArgumentList $tempDir, $Cfg.serverInstance, $Cfg.tenant, $appMeta, $Cfg.mgmtDllPath
    }
    finally { Remove-PSSession $session }
    Write-Host "Deploy done."
    return $true
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
    $summary = [ordered]@{ Stage = $ResultObject.stage; Ok = $ResultObject.ok; Total = 0; Passed = 0; Failed = 0; Failures = @() }
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
# Orchestrator: Build -> Deploy -> Run. (The fix step is the agent's job.)
# ---------------------------------------------------------------------------
function Invoke-AprodaDeployRunVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [switch]$BuildOnly,
        [switch]$SkipBuild
    )
    $cfg = Resolve-DeployRunVerifyConfig -ConfigPath $ConfigPath
    $totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $timings = [ordered]@{ Build = $null; Deploy = $null; Tests = $null }
    Write-Host "Server $($cfg.server)/$($cfg.serverInstance)  tenant=$($cfg.tenant)  adapter=$($cfg.adapter)  auth=$($cfg.authentication)"
    Write-Host ("Apps: " + (($cfg.apps | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ' -> '))

    $pf = Test-DeployRunVerifyPreflight -Cfg $cfg
    if (-not $pf.Reachable) {
        Write-Warning "BC service '$($cfg.server)' not reachable. Quality is higher with a Cronus BC environment incl. Test Toolkit. Without a service only static validation (build) is possible — no runtime verification."
        if ($cfg.onServiceUnavailable -eq 'abort') { throw "Service unavailable and onServiceUnavailable=abort." }
        $BuildOnly = $true
    }

    if (-not $SkipBuild) {
        $stageTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-DeployRunVerifyBuild -Cfg $cfg | Out-Null
        $stageTimer.Stop()
        $timings.Build = $stageTimer.Elapsed
    }
    if ($BuildOnly) {
        $totalTimer.Stop()
        Write-Host "BUILD-ONLY: skipping deploy + run."
        Write-Host ("TIMING: build={0} · deploy=n/a · tests=n/a · total={1}" -f $(if ($timings.Build) { '{0:N1}s' -f $timings.Build.TotalSeconds } else { 'skipped' }), ('{0:N1}s' -f $totalTimer.Elapsed.TotalSeconds))
        return [pscustomobject]@{ BuildOnly = $true; Timings = [pscustomobject]$timings; TotalDuration = $totalTimer.Elapsed }
    }

    $stageTimer = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-DeployRunVerifyDeploy -Cfg $cfg | Out-Null
    $stageTimer.Stop()
    $timings.Deploy = $stageTimer.Elapsed

    $stageTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $summary = Invoke-DeployRunVerifyRun -Cfg $cfg
    $stageTimer.Stop()
    $timings.Tests = $stageTimer.Elapsed
    $totalTimer.Stop()
    if ($summary) {
        Write-Host ("RESULT: {0}/{1} passed, {2} failed." -f $summary.Passed, $summary.Total, $summary.Failed)
        if ($summary.Failed -gt 0) { Write-Host ("FAILURES: " + ($summary.Failures -join ', ')) }
        $summary | Add-Member Timings ([pscustomobject]$timings) -Force
        $summary | Add-Member TotalDuration $totalTimer.Elapsed -Force
    }
    Write-Host ("TIMING: build={0} · deploy={1} · tests={2} · total={3}" -f $(if ($timings.Build) { '{0:N1}s' -f $timings.Build.TotalSeconds } else { 'skipped' }), ('{0:N1}s' -f $timings.Deploy.TotalSeconds), ('{0:N1}s' -f $timings.Tests.TotalSeconds), ('{0:N1}s' -f $totalTimer.Elapsed.TotalSeconds))
    return $summary
}

Export-ModuleMember -Function Resolve-DeployRunVerifyConfig, Test-DeployRunVerifyPreflight, Invoke-DeployRunVerifyBuild,
Invoke-DeployRunVerifyDeploy, Invoke-DeployRunVerifyDeployAsinst, Invoke-DeployRunVerifyDeployFkh, Invoke-DeployRunVerifyRun,
Invoke-DeployRunVerifyRunOnce, Get-DeployRunVerifySummary, Invoke-AprodaDeployRunVerify, Get-DeployRunVerifyAdapter,
Get-DeployRunVerifyFkhBackendUrl, Resolve-DeployRunVerifyFkhContainer, Get-DeployRunVerifyCredential,
Reset-DeployRunVerifyCredential,
Resolve-DeployRunVerifyRunner, New-DeployRunVerifyRunner, Initialize-DeployRunVerifyRunner, Copy-DeployRunVerifyRunnerFromServer,
Resolve-DeployRunVerifyClientSource, Get-DeployRunVerifyServerVersion, Get-DeployRunVerifyRunnerVersion
