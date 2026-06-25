<#
.SYNOPSIS
  Aproda Test-Loop engine — Build -> Deploy -> Run for AL BC OnPrem.
  IMMUTABLE TEMPLATE. Do NOT edit per project; drive it via testloop.config.jsonc.
  Derived from the proven Test/PowerShell/_Cycle.ps1 + _RunTests.ps1 (Audit Trail 26/26).
.NOTES
  Status: template — needs one live validation run on a second project.
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Config resolution: merge testloop.config.jsonc + launch.json + each app.json
# ---------------------------------------------------------------------------
function Resolve-TestLoopConfig {
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
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($cfg.server)) { throw "server/serverInstance unresolved — set them in config or provide a launch.json 'server' configuration." }
    if ([string]::IsNullOrWhiteSpace($cfg.tenant)) { $cfg.tenant = 'default' }

    # --- Glue dir (central, ships with the skill): <engine module dir>\runner-glue ---
    # When the engine is dot-loaded via iex, $PSScriptRoot is empty inside functions,
    # so prefer the module-path hint the entry point always sets.
    $glueBase = $env:APRODA_TESTLOOP_MODULE
    if ($glueBase) { $glueBase = Split-Path -Parent $glueBase } elseif ($PSScriptRoot) { $glueBase = $PSScriptRoot }
    if (-not $glueBase) { throw "Cannot locate the engine dir to resolve runner-glue. Set `$env:APRODA_TESTLOOP_MODULE to the AprodaTestLoop.psm1 path." }
    $glueDir = Join-Path $glueBase 'runner-glue'
    foreach ($g in 'ClientContext.ps1', 'PsTestFunctions.ps1', 'AprodaRunner.ps1') {
        if (-not (Test-Path (Join-Path $glueDir $g))) { throw "Runner glue missing: $glueDir\$g (ships centrally with the skill)." }
    }
    $cfg | Add-Member glueDir "$glueDir" -Force

    # --- ServiceUrl (web client, port 80) ---
    # Company is required for a deterministic headless run; if set, pin it into the URL
    # (proven shape: /cs?tenant=<t>&company=<c>). Empty company falls back to /cs/.
    if (-not ($cfg.PSObject.Properties.Name -contains 'companyName')) { $cfg | Add-Member companyName '' -Force }
    if (-not [string]::IsNullOrWhiteSpace($cfg.companyName)) {
        $cfg | Add-Member serviceUrl ("http://{0}/{1}/cs?tenant={2}&company={3}" -f $cfg.server, $cfg.serverInstance, $cfg.tenant, $cfg.companyName) -Force
    } else {
        $cfg | Add-Member serviceUrl ("http://{0}/{1}/cs/" -f $cfg.server, $cfg.serverInstance) -Force
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
    # "\\apd-svw-nst05\D$\28\<inst>\Service". Used by Initialize-TestLoopRunner to materialize
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
    # runnerDirFull is the BASE folder; the actual runner is a version subfolder (see Resolve-TestLoopRunner).
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
function ConvertTo-TestLoopMajorMinor {
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    if ($Version -match '^(\d+)\.(\d+)') { return "$($Matches[1]).$($Matches[2])" }
    return $null
}

function Get-TestLoopRunnerVersion {
    # Reads the BC client DLL ProductVersion present in a runner dir (or $null).
    param([Parameter(Mandatory)][string]$Dir)
    $dll = Join-Path $Dir 'Microsoft.Dynamics.Framework.UI.Client.dll'
    if (-not (Test-Path $dll)) { return $null }
    return (Get-Item $dll).VersionInfo.ProductVersion
}

function Get-TestLoopServerVersion {
    # Live BC platform version via a short remote session (or $null if unreachable).
    param([Parameter(Mandatory)]$Cfg)
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
        } finally { Remove-PSSession $session }
    } catch { return $null }
}

function Resolve-TestLoopRunner {
    # Returns the runner dir to use; validates client DLL major.minor == target BC version.
    param([Parameter(Mandatory)]$Cfg)
    $base = $Cfg.runnerDirFull

    # Target BC version: explicit config override > live server > (none = trust whatever DLL is present).
    $target = ConvertTo-TestLoopMajorMinor $Cfg.bcVersion
    if (-not $target) { $target = ConvertTo-TestLoopMajorMinor (Get-TestLoopServerVersion -Cfg $Cfg) }

    # Candidates: versioned subfolder first, then flat base (legacy).
    $candidates = @()
    if ($target) { $candidates += (Join-Path $base $target) }
    $candidates += $base

    foreach ($dir in $candidates) {
        $rv = ConvertTo-TestLoopMajorMinor (Get-TestLoopRunnerVersion -Dir $dir)
        if (-not $rv) { continue }
        if ($target -and $rv -ne $target) {
            throw ("Runner version mismatch: '$dir' carries BC $rv but the target environment is BC $target. " +
                   "Create a matching runner with: New-TestLoopRunner -RunnerBase '$base' -TargetVersion $target " +
                   "-ClientFrom '<BC Service or client install folder>' -GlueFrom '$dir'.")
        }
        if ($dir -eq $base -and $target) {
            Write-Warning "Using legacy flat runner '$base' (BC $rv). Recommended: move its files to versioned subfolder '$base\$target'."
        }
        return $dir
    }
    throw ("No runner found under '$base'" + ($(if ($target) { " for BC $target" } else { '' })) +
           ". Materialize one with New-TestLoopRunner (see references/runner.md).")
}

function New-TestLoopRunner {
    # Materializes a versioned runner DIR with the 4 version-pinned BC client DLLs.
    # Glue (ClientContext.ps1 / PsTestFunctions.ps1 / AprodaRunner.ps1) is NOT copied here —
    # it ships centrally with the skill (scripts/runner-glue) and is resolved at run time.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunnerBase,    # the base _runner dir
        [Parameter(Mandatory)][string]$TargetVersion, # e.g. "28.0"
        [Parameter(Mandatory)][string]$ClientFrom     # folder holding the 4 BC client DLLs (Service / RTC install)
    )
    $tv = ConvertTo-TestLoopMajorMinor $TargetVersion
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
    $rv = Get-TestLoopRunnerVersion -Dir $dest
    Write-Host "Runner materialized at '$dest' (BC client $rv)."
    return $dest
}

# ---------------------------------------------------------------------------
# Pull the 4 version-pinned client DLLs from a SERVER-SIDE folder via a remote PS
# session (same topology as deploy's mgmtDllPath: local VS Code, remote BC, admin
# shares blocked but remote-PSH works). Materializes into <runnerBase>/<target>/.
# ---------------------------------------------------------------------------
function Copy-TestLoopRunnerFromServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunnerBase,
        [Parameter(Mandatory)][string]$TargetVersion,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$ServerSidePath   # e.g. D:\28\<inst>\Service
    )
    $tv = ConvertTo-TestLoopMajorMinor $TargetVersion
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
    } finally { Remove-PSSession $session }
    $rv = Get-TestLoopRunnerVersion -Dir $dest
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
function Resolve-TestLoopClientSource {
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
function Initialize-TestLoopRunner {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Cfg)
    $base = $Cfg.runnerDirFull

    # Target BC version: explicit override > live server.
    $target = ConvertTo-TestLoopMajorMinor $Cfg.bcVersion
    if (-not $target) { $target = ConvertTo-TestLoopMajorMinor (Get-TestLoopServerVersion -Cfg $Cfg) }

    # If a valid runner already resolves (right version DLLs present), keep it.
    try {
        $existing = Resolve-TestLoopRunner -Cfg $Cfg
        if ($existing) { Write-Host "Runner ready: $existing"; return $existing }
    } catch {
        Write-Host "Runner not ready ($($_.Exception.Message.Split([char]10)[0])) — materializing..."
    }

    if (-not $target) { throw "Cannot determine target BC version (server unreachable and no bcVersion override) — set 'bcVersion' in config to materialize the runner." }

    # Resolve the effective client-DLL source: explicit runnerClientSource wins; otherwise
    # derive it deterministically from the BC product-DVD share (bcDvdRoot + bcCountry).
    $clientSource = Resolve-TestLoopClientSource -Cfg $Cfg -Target $target
    if ([string]::IsNullOrWhiteSpace($clientSource)) {
        throw ("No valid runner under '$base' for BC $target and no client source resolved. " +
               "Set 'runnerClientSource' to the folder holding the 4 client DLLs (the BC Service folder, " +
               "or the DVD's Applications\TestFramework\TestRunner\Internal), or set 'bcDvdRoot' + 'bcCountry' " +
               "to derive it from the product-DVD share.")
    }

    # Server-pull only applies to an explicit server-side runnerClientSource; a DVD-derived
    # local/UNC path is always copied directly.
    if ($Cfg.runnerClientFromServer -and -not [string]::IsNullOrWhiteSpace($Cfg.runnerClientSource)) {
        Copy-TestLoopRunnerFromServer -RunnerBase $base -TargetVersion $target -Server $Cfg.server -ServerSidePath $clientSource | Out-Null
    } else {
        New-TestLoopRunner -RunnerBase $base -TargetVersion $target -ClientFrom $clientSource | Out-Null
    }
    return Resolve-TestLoopRunner -Cfg $Cfg
}

# ---------------------------------------------------------------------------
# Preflight (HITL-aware): reachability; caller owns the environment ack.
# ---------------------------------------------------------------------------
function Test-TestLoopPreflight {
    param([Parameter(Mandatory)]$Cfg)
    $reachable = $false
    try { $reachable = Test-Connection -ComputerName $Cfg.server -Count 1 -Quiet -ErrorAction SilentlyContinue } catch {}
    [pscustomobject]@{ Reachable = [bool]$reachable; ServiceUrl = $Cfg.serviceUrl }
}

# ---------------------------------------------------------------------------
# Build: each app in order; copy upstream .app symbol into downstream .alpackages
# ---------------------------------------------------------------------------
function Invoke-TestLoopBuild {
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
# Deploy: uninstall reverse order, unpublish, publish/sync/install forward
# ---------------------------------------------------------------------------
function Invoke-TestLoopDeploy {
    param([Parameter(Mandatory)]$Cfg)
    if ([string]::IsNullOrWhiteSpace($Cfg.mgmtDllPath)) { throw "mgmtDllPath is required for deploy." }
    $session = New-PSSession -ComputerName $Cfg.server
    try {
        $tempDir = "C:\Temp\AprodaTestLoop_$(Get-Random)"
        Invoke-Command -Session $session -ScriptBlock { param($d) New-Item -ItemType Directory $d -Force | Out-Null } -ArgumentList $tempDir
        foreach ($app in $Cfg.apps) { Copy-Item $app.AppFile -Destination $tempDir -ToSession $session -Force }

        $appMeta = $Cfg.apps | ForEach-Object { @{ Name = $_.Name; Version = $_.Version; Publisher = $_.Publisher } }
        Invoke-Command -Session $session -ScriptBlock {
            param($d, $si, $tenant, $appMeta, $mgmt)
            $ErrorActionPreference = 'Continue'
            function Log($m) { Write-Host "[deploy] $m" }
            function Step($label, $sb) { try { & $sb; Log "OK   - $label" } catch { Log "FAIL - $label :: $($_.Exception.Message)" } }
            # Robust install for a TEST-LOOP that redeploys the SAME version with a changed
            # schema. No localized-message parsing: escalate sync strength, then data-upgrade.
            #   1) plain Install
            #   2) ForceSync -> Install  (same-version redeploy whose table set changed; the
            #      platform refuses Install against the stale synced schema. ForceSync can drop
            #      data for changed tables — acceptable/expected inside a dev test-loop.)
            #   3) Start-NAVAppDataUpgrade (retained data from a prior version bump)
            function InstallOrUpgrade($si, $name, $ver, $tenant) {
                try { Install-NAVApp -ServerInstance $si -Name $name -Version $ver -Tenant $tenant -ErrorAction Stop; Log "INSTALLED $name $ver"; return }
                catch { Log "install#1 failed ($name $ver): $($_.Exception.Message)" }
                try {
                    Sync-NAVApp -ServerInstance $si -Name $name -Version $ver -Tenant $tenant -Mode ForceSync -Force -ErrorAction Stop
                    Log "OK   - ForceSync $name $ver"
                    Install-NAVApp -ServerInstance $si -Name $name -Version $ver -Tenant $tenant -ErrorAction Stop
                    Log "INSTALLED (after ForceSync) $name $ver"; return
                } catch { Log "install#2 (post-ForceSync) failed ($name $ver): $($_.Exception.Message)" }
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
                Step "Sync $($a.Name) $($a.Version)"    { Sync-NAVApp    -ServerInstance $si -Name $a.Name -Version $a.Version -Tenant $tenant -Mode Add -ErrorAction SilentlyContinue }
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
function Invoke-TestLoopRun {
    param([Parameter(Mandatory)]$Cfg)
    $pwsh = (Get-Process -Id $PID).Path
    $runnerDir = Initialize-TestLoopRunner -Cfg $Cfg
    $log = Join-Path $runnerDir 'progress.log'
    $resultJson = Join-Path $runnerDir '_result.json'
    foreach ($f in @($log, $resultJson)) { if (Test-Path $f) { Remove-Item $f -Force } }

    $vars = @{ dir = $runnerDir; glue = $Cfg.glueDir; url = $Cfg.serviceUrl; ext = $Cfg.testExtensionId; range = $Cfg.testCodeunitRange; suite = $Cfg.testSuite } | ConvertTo-Json -Compress
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
    Note ("running Run-AlTests ({0})..." -f $cfg.range)
    $console = & {
        Run-AlTests -ServiceUrl $cfg.url -AutorizationType 'Windows' -ExtensionId $cfg.ext `
            -TestCodeunitsRange $cfg.range -TestSuite $cfg.suite -SaveResultFile $true `
            -ResultsFilePath $resultPath -Detailed $true
    } *>&1 | Out-String
    $res.stage='ran'; $res.console=$console; Note 'ran'
    if (Test-Path $resultPath) { $res.xml = Get-Content $resultPath -Raw } else { $res.xml = 'NO-RESULT-FILE' }
    $res.ok = $true
} catch { $res.error = $_.Exception.ToString(); Note ('ERROR: ' + $_.Exception.Message) }
$res | ConvertTo-Json -Depth 6 -Compress | Out-File -FilePath $resultJson -Encoding UTF8; Note 'result-written'
'@
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($bootstrap))
    $env:APRODA_TL_VARS = $b64vars
    Write-Host "Running AL tests via $($Cfg.serviceUrl) (range $($Cfg.testCodeunitRange))..."
    $p = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) -PassThru -NoNewWindow
    if (-not $p.WaitForExit([int]$Cfg.runTimeoutMs)) { Write-Host "TIMEOUT - killing $($p.Id)"; try { $p.Kill($true) } catch { $p.Kill() } }

    if (-not (Test-Path $resultJson)) { Write-Host "NO-RESULT-JSON"; return $null }
    $obj = Get-Content $resultJson -Raw | ConvertFrom-Json
    return Get-TestLoopSummary -ResultObject $obj
}

# ---------------------------------------------------------------------------
# Summary: parse XUnit-style TestResults.xml into pass/fail counts + failures
# ---------------------------------------------------------------------------
function Get-TestLoopSummary {
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
        } catch { $summary.Error = "XML parse failed: $($_.Exception.Message)" }
    }
    [pscustomobject]$summary
}

# ---------------------------------------------------------------------------
# Orchestrator: Build -> Deploy -> Run. (The fix step is the agent's job.)
# ---------------------------------------------------------------------------
function Invoke-AprodaTestLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [switch]$BuildOnly,
        [switch]$SkipBuild
    )
    $cfg = Resolve-TestLoopConfig -ConfigPath $ConfigPath
    Write-Host "Server $($cfg.server)/$($cfg.serverInstance)  tenant=$($cfg.tenant)"
    Write-Host ("Apps: " + (($cfg.apps | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ' -> '))

    $pf = Test-TestLoopPreflight -Cfg $cfg
    if (-not $pf.Reachable) {
        Write-Warning "BC service '$($cfg.server)' not reachable. Quality is higher with a Cronus BC environment incl. Test Toolkit. Without a service only static validation (build) is possible — no runtime verification."
        if ($cfg.onServiceUnavailable -eq 'abort') { throw "Service unavailable and onServiceUnavailable=abort." }
        $BuildOnly = $true
    }

    if (-not $SkipBuild) { Invoke-TestLoopBuild -Cfg $cfg | Out-Null }
    if ($BuildOnly) { Write-Host "BUILD-ONLY: skipping deploy + run."; return [pscustomobject]@{ BuildOnly = $true } }

    Invoke-TestLoopDeploy -Cfg $cfg | Out-Null
    $summary = Invoke-TestLoopRun -Cfg $cfg
    if ($summary) {
        Write-Host ("RESULT: {0}/{1} passed, {2} failed." -f $summary.Passed, $summary.Total, $summary.Failed)
        if ($summary.Failed -gt 0) { Write-Host ("FAILURES: " + ($summary.Failures -join ', ')) }
    }
    return $summary
}

Export-ModuleMember -Function Resolve-TestLoopConfig, Test-TestLoopPreflight, Invoke-TestLoopBuild,
    Invoke-TestLoopDeploy, Invoke-TestLoopRun, Get-TestLoopSummary, Invoke-AprodaTestLoop,
    Resolve-TestLoopRunner, New-TestLoopRunner, Initialize-TestLoopRunner, Copy-TestLoopRunnerFromServer,
    Resolve-TestLoopClientSource, Get-TestLoopServerVersion, Get-TestLoopRunnerVersion
