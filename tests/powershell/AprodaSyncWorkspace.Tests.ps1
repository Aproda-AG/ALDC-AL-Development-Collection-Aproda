# E-011 phase 3: workspace seed, Init 3 and Migrate classification for the virtual `.external` root (S-11.L1 .. L5).
# Self-contained harness, no Pester. Run content-based (SRP-safe), pwsh 7:
#   $env:APRODA_TEST_REPOSITORY_ROOT = '<repo>'
#   Get-Content -LiteralPath tests\powershell\AprodaSyncWorkspace.Tests.ps1 -Raw | Invoke-Expression

# No StrictMode: folder entries are heterogeneous (uri or path), absent properties read as $null.

$repositoryRoot = $env:APRODA_TEST_REPOSITORY_ROOT
if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$syncRoot = Join-Path $repositoryRoot 'tools\aproda-sync'
$seedPath = Join-Path $syncRoot 'templates\workspace.seed.jsonc'
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP ('aproda-syncws-tests-' + [guid]::NewGuid().ToString('N'))))
$originalScriptDir = $env:APRODA_SYNC_SCRIPTDIR
$externalUri = 'aldc-external:/'

$script:passed = 0
$script:failed = [System.Collections.Generic.List[string]]::new()

function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Test)
    try {
        & $Test
        $script:passed++
        Write-Host "PASS: $Name"
    }
    catch {
        $script:failed.Add($Name)
        Write-Host "FAIL: $Name"
        Write-Host "      $($_.Exception.Message)"
    }
}

function Assert-True {
    param($Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if (-not ($Actual -ceq $Expected)) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Write-TestFile {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# Scratch project: .git + a copy of the scripts and templates under .github\tools\aproda-sync.
function New-ScratchProject {
    param([switch]$WithoutMigrate, [string]$Workspace)
    $project = Join-Path $tempRoot ('p-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $project '.git') -Force | Out-Null
    $scriptDir = Join-Path $project '.github\tools\aproda-sync'
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $syncRoot 'Initialize-AprodaProject.ps1') -Destination $scriptDir
    if (-not $WithoutMigrate) { Copy-Item -LiteralPath (Join-Path $syncRoot 'Migrate-AprodaProjectLayout.ps1') -Destination $scriptDir }
    Copy-Item -LiteralPath (Join-Path $syncRoot 'templates') -Destination $scriptDir -Recurse
    if ($Workspace) { Write-TestFile (Join-Path $project 'aldc.code-workspace') $Workspace }
    return [pscustomobject]@{ Root = $project; ScriptDir = $scriptDir; Workspace = (Join-Path $project 'aldc.code-workspace') }
}

function Invoke-SyncScript {
    param($Project, [string]$Name)
    $env:APRODA_SYNC_SCRIPTDIR = $Project.ScriptDir
    $source = Get-Content -LiteralPath (Join-Path $Project.ScriptDir $Name) -Raw
    return (& ([ScriptBlock]::Create($source)) *>&1 | Out-String)
}

function Read-Workspace {
    param($Project)
    return (Get-Content -LiteralPath $Project.Workspace -Raw | ConvertFrom-Json)
}

function Get-ExternalEntries {
    param($Json)
    return @($Json.folders | Where-Object { "$($_.uri)" -eq $externalUri })
}

$legacyWorkspace = @'
{
  "folders": [
    { "name": ".github", "path": ".github" },
    { "name": "App", "path": "App" },
    { "name": "BCQuality", "path": "../bcquality-aproda" }
  ],
  "settings": {
    "search.exclude": { "bcquality/**": true, "../bcquality-aproda/**": true, "**/*.bak": true },
    "files.watcherExclude": { "bcquality/**": true, "../bcquality-aproda/**": true },
    "terminal.integrated.env.windows": { "BCQUALITY_HOME": "C:\\x\\bcquality-aproda", "OTHER": "keep" }
  }
}
'@

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    # S-11.L1: seed
    Invoke-TestCase 'L1 seed has exactly one constant virtual root and no .external path root' {
        $seed = Get-Content -LiteralPath $seedPath -Raw | ConvertFrom-Json
        $entries = Get-ExternalEntries $seed
        Assert-Equal $entries.Count 1 'uri entries.'
        Assert-Equal $entries[0].name '.external' 'entry name.'
        Assert-True (@($seed.folders | Where-Object { "$($_.path)" -match '^\.?/?\.external$' }).Count -eq 0) 'seed still has a .external path root.'
    }
    Invoke-TestCase 'L1 seed keeps the bcquality/** excludes' {
        $seed = Get-Content -LiteralPath $seedPath -Raw | ConvertFrom-Json
        Assert-True ($seed.settings.'search.exclude'.'bcquality/**' -eq $true) 'search.exclude lost bcquality/**.'
        Assert-True ($seed.settings.'files.watcherExclude'.'bcquality/**' -eq $true) 'files.watcherExclude lost bcquality/**.'
    }

    # Init 3
    Invoke-TestCase 'L2 Init creates a fresh workspace with the uri entry' {
        $p = New-ScratchProject
        Invoke-SyncScript $p 'Initialize-AprodaProject.ps1' | Out-Null
        Assert-Equal (Get-ExternalEntries (Read-Workspace $p)).Count 1 'uri entries.'
    }
    Invoke-TestCase 'L2 Init adds a missing .external uri entry to an existing workspace' {
        $p = New-ScratchProject -Workspace '{ "folders": [ { "name": "App", "path": "App" } ] }'
        Invoke-SyncScript $p 'Initialize-AprodaProject.ps1' | Out-Null
        $json = Read-Workspace $p
        Assert-Equal (Get-ExternalEntries $json).Count 1 'uri entries.'
        Assert-True (@($json.folders | Where-Object { $_.name -eq 'App' }).Count -eq 1) 'App folder lost.'
    }
    Invoke-TestCase 'L3 Init leaves an existing uri entry alone (one entry)' {
        $p = New-ScratchProject -Workspace '{ "folders": [ { "name": ".github", "path": ".github" }, { "name": ".external", "uri": "aldc-external:/" } ] }'
        Invoke-SyncScript $p 'Initialize-AprodaProject.ps1' | Out-Null
        Assert-Equal (Get-ExternalEntries (Read-Workspace $p)).Count 1 'uri entries.'
    }

    # S-11.L4: legacy .external path root
    Invoke-TestCase 'L4 Init alone leaves a legacy .external path root as is' {
        $p = New-ScratchProject -WithoutMigrate -Workspace '{ "folders": [ { "name": ".github", "path": ".github" }, { "name": ".external", "path": ".external" } ] }'
        $out = Invoke-SyncScript $p 'Initialize-AprodaProject.ps1'
        $json = Read-Workspace $p
        Assert-Equal (Get-ExternalEntries $json).Count 0 'uri entries.'
        Assert-True (@($json.folders | Where-Object { $_.path -eq '.external' }).Count -eq 1) 'legacy path root changed.'
        Assert-True ($out -match 'Migrate-AprodaProjectLayout\.ps1 not in this project') 'missing the Init 5 skip notice.'
    }
    Invoke-TestCase 'L4 Init chaining Migrate converts the legacy .external path root in place' {
        $p = New-ScratchProject -Workspace '{ "folders": [ { "name": ".github", "path": ".github" }, { "name": ".external", "path": ".external" }, { "name": "App", "path": "App" } ] }'
        Invoke-SyncScript $p 'Initialize-AprodaProject.ps1' | Out-Null
        $json = Read-Workspace $p
        Assert-Equal (Get-ExternalEntries $json).Count 1 'uri entries.'
        Assert-Equal @($json.folders)[1].uri $externalUri 'entry was not replaced in place.'
        Assert-Equal @($json.folders).Count 3 'folder count.'
    }

    # Migrate (S-11.L3/L5)
    Invoke-TestCase 'L3 Migrate removes the legacy clone root, its globs and BCQUALITY_HOME; keeps the bare bcquality/** glob' {
        $p = New-ScratchProject -Workspace $legacyWorkspace
        Invoke-SyncScript $p 'Migrate-AprodaProjectLayout.ps1' | Out-Null
        $json = Read-Workspace $p
        Assert-Equal (Get-ExternalEntries $json).Count 1 'uri entries.'
        Assert-True (@($json.folders | Where-Object { "$($_.path)" -match 'bcquality' }).Count -eq 0) 'legacy clone root still present.'
        Assert-Equal @($json.folders).Count 3 'folder count (.github, App, .external).'
        foreach ($key in 'search.exclude', 'files.watcherExclude') {
            $globs = $json.settings.$key
            Assert-True ($null -eq $globs.PSObject.Properties['../bcquality-aproda/**']) "$key kept the stale clone glob."
            Assert-True ($globs.'bcquality/**' -eq $true) "$key lost the bare bcquality/** glob."
        }
        Assert-True ($json.settings.'search.exclude'.'**/*.bak' -eq $true) 'unrelated glob lost.'
        $env = $json.settings.'terminal.integrated.env.windows'
        Assert-True ($null -eq $env.PSObject.Properties['BCQUALITY_HOME']) 'BCQUALITY_HOME still present.'
        Assert-Equal $env.OTHER 'keep' 'unrelated env var lost.'
    }
    Invoke-TestCase 'L3 Migrate recognises a clone root by skills/entry.md and leaves unrelated roots untouched' {
        $p = New-ScratchProject
        $clone = Join-Path $p.Root 'someclone'
        Write-TestFile (Join-Path $clone 'skills\entry.md') '# entry'
        Write-TestFile $p.Workspace '{ "folders": [ { "name": "App", "path": "App" }, { "name": "Clone", "path": "someclone" }, { "name": "Docs", "path": "docs" } ] }'
        Invoke-SyncScript $p 'Migrate-AprodaProjectLayout.ps1' | Out-Null
        $json = Read-Workspace $p
        Assert-True (@($json.folders | Where-Object { $_.path -eq 'someclone' }).Count -eq 0) 'entry.md clone root not removed.'
        Assert-True (@($json.folders | Where-Object { $_.path -in 'App', 'docs' }).Count -eq 2) 'unrelated roots changed.'
        Assert-Equal (Get-ExternalEntries $json).Count 1 'uri entries.'
    }
    Invoke-TestCase 'L3 Migrate collapses duplicates to one constant entry' {
        $p = New-ScratchProject -Workspace '{ "folders": [ { "name": ".external", "uri": "aldc-external:/" }, { "name": "App", "path": "App" }, { "name": ".external", "uri": "aldc-external:/" }, { "name": ".external", "path": ".external" } ] }'
        Invoke-SyncScript $p 'Migrate-AprodaProjectLayout.ps1' | Out-Null
        $json = Read-Workspace $p
        Assert-Equal (Get-ExternalEntries $json).Count 1 'uri entries.'
        Assert-Equal @($json.folders).Count 2 'folder count.'
    }
    Invoke-TestCase 'L3 Migrate adds a missing .external entry at the end' {
        $p = New-ScratchProject -Workspace '{ "folders": [ { "name": "App", "path": "App" } ] }'
        Invoke-SyncScript $p 'Migrate-AprodaProjectLayout.ps1' | Out-Null
        $folders = @((Read-Workspace $p).folders)
        Assert-Equal $folders.Count 2 'folder count.'
        Assert-Equal $folders[-1].uri $externalUri 'entry is not last.'
    }
    Invoke-TestCase 'L5 Migrate is idempotent: a converged workspace is not rewritten' {
        $p = New-ScratchProject -Workspace $legacyWorkspace
        Invoke-SyncScript $p 'Migrate-AprodaProjectLayout.ps1' | Out-Null
        $before = Get-Content -LiteralPath $p.Workspace -Raw
        $stamp = (Get-Item -LiteralPath $p.Workspace).LastWriteTimeUtc
        Start-Sleep -Milliseconds 1100
        Invoke-SyncScript $p 'Migrate-AprodaProjectLayout.ps1' | Out-Null
        Assert-Equal (Get-Content -LiteralPath $p.Workspace -Raw) $before 'content changed on the second run.'
        Assert-True ((Get-Item -LiteralPath $p.Workspace).LastWriteTimeUtc -eq $stamp) 'workspace was rewritten on the second run.'
    }
    Invoke-TestCase 'L5 Migrate does not write a workspace that already has the constant entry' {
        $content = '{ "folders": [ { "name": ".github", "path": ".github" }, { "name": ".external", "uri": "aldc-external:/" } ] }'
        $p = New-ScratchProject -Workspace $content
        Invoke-SyncScript $p 'Migrate-AprodaProjectLayout.ps1' | Out-Null
        Assert-Equal (Get-Content -LiteralPath $p.Workspace -Raw) $content 'content changed.'
        Assert-True (-not (Test-Path -LiteralPath "$($p.Workspace).bak")) 'a .bak was written for a no-op.'
    }
    Invoke-TestCase 'L5 Migrate keeps a .bak of the original on the first rewrite' {
        $p = New-ScratchProject -Workspace $legacyWorkspace
        Invoke-SyncScript $p 'Migrate-AprodaProjectLayout.ps1' | Out-Null
        Assert-Equal (Get-Content -LiteralPath "$($p.Workspace).bak" -Raw) $legacyWorkspace 'bak differs from the original.'
    }
}
finally {
    $env:APRODA_SYNC_SCRIPTDIR = $originalScriptDir
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:failed.Count -gt 0) {
    throw "FAIL: $($script:failed.Count) of $($script:passed + $script:failed.Count) failed: $($script:failed -join '; ')"
}
Write-Host "PASS: $($script:passed) tests, 0 failed."
