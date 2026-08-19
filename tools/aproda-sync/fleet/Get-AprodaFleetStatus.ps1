# Aproda Fleet — Status Inspector  (FORK-ONLY; not synced to project repos)
# PURPOSE : Scan local project repos, report Aproda-ALDC layer version and
#           optionally compare layer content (SHA-256) against this fork.
# HOME    : <fork>/tools/aproda-sync/fleet/Get-AprodaFleetStatus.ps1
# RUN     : Open → Select All → "PowerShell: Run Selection"  (SRP-safe)
#           Nothing to fill in — fork is self-resolved from this file's location.
#
# STATUS LEGEND
#   [OK    ]  same version as fork; no content drift (or -FullDiff not used)
#   [UPDATE]  repo has an older layer version  →  run Start-FleetUpdate
#   [DRIFT ]  same version but content differs  →  run Start-FleetGather or investigate
#   [NO-VER]  aproda-sync present but layerVersion missing from aldc.yaml
#   [NONE  ]  no Aproda-ALDC detected  (only shown with -IncludeNonAproda)

[CmdletBinding()]
param(
    [string]   $SearchRoot = '',        # Folder to scan. Default: parent folder of fork.
    [string[]] $SkipRepos = @('BCQuality*', 'bcquality*'),  # Name patterns to silently ignore.
    [switch]   $IncludeNonAproda,          # Also report repos without Aproda-ALDC layer.
    [switch]   $FullDiff                   # SHA-256 layer content compare (slower; default: version only).
)

$ErrorActionPreference = 'Stop'

# ── Self-locate fork root ─────────────────────────────────────────────────────
# Resolution order:
#   $PSScriptRoot             → fleet/ dir  → fork = 3 parents up
#   $env:APRODA_SYNC_SCRIPTDIR → aproda-sync/ dir → fork = 2 parents up
#   $psEditor current file     → fleet/ dir  → fork = 3 parents up
$forkPath = $null
if ($PSScriptRoot) {
    $forkPath = Split-Path (Split-Path (Split-Path $PSScriptRoot))
}
elseif ($env:APRODA_SYNC_SCRIPTDIR) {
    $forkPath = Split-Path (Split-Path $env:APRODA_SYNC_SCRIPTDIR)
}
elseif ($psEditor) {
    try {
        $d = Split-Path -Parent $psEditor.GetEditorContext().CurrentFile.Path
        $forkPath = Split-Path (Split-Path (Split-Path $d))
    }
    catch {}
}
if ([string]::IsNullOrWhiteSpace($forkPath) -or -not (Test-Path $forkPath)) {
    Write-Error 'Cannot self-locate fork. Set $env:APRODA_SYNC_SCRIPTDIR = "<fork>/tools/aproda-sync" or open this file and use Run Selection.'
    return
}
$aprSyncDir = Join-Path $forkPath 'tools\aproda-sync'

# ── Version helper ────────────────────────────────────────────────────────────
# aldc.yaml always sits at the REPO ROOT on both fork and project side
# (dual-variant, D-18 — only toolkitRoot differs, the file path does not).
function Get-LayerVersion([string] $repoRoot) {
    $yaml = Join-Path $repoRoot 'aldc.yaml'
    if (-not (Test-Path -LiteralPath $yaml)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $yaml -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s+layerVersion:\s*"([^"]+)"') { return $Matches[1] }
    }
    return $null  # aldc.yaml exists but no layerVersion (upstream ALDC core, not Aproda fork)
}

$forkVersion = Get-LayerVersion $forkPath
if (-not $forkVersion) {
    Write-Error "Could not read aproda.layerVersion from fork: $forkPath\aldc.yaml"
    return
}

# ── Scan root ─────────────────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($SearchRoot)) { $SearchRoot = Split-Path -Parent $forkPath }
Write-Host ''
Write-Host "Fork         : $forkPath" -ForegroundColor Cyan
Write-Host "Fork version : $forkVersion" -ForegroundColor Cyan
Write-Host "Scanning     : $SearchRoot" -ForegroundColor Cyan
if ($FullDiff) { Write-Host '             : Full diff enabled (SHA-256)' -ForegroundColor DarkCyan }
Write-Host ''

# Scan direct children + one level deeper inside container folders (no .git at top)
function Test-SkipRepo([string] $name, [string[]] $patterns) {
    foreach ($p in $patterns) { if ($name -like $p) { return $true } }; return $false
}
$allTopDirs = @(Get-ChildItem -Path $SearchRoot -Directory -ErrorAction SilentlyContinue)
$rawRepos = [System.Collections.Generic.List[string]]::new()
foreach ($d in $allTopDirs) {
    if (Test-Path (Join-Path $d.FullName '.git')) {
        $rawRepos.Add($d.FullName) | Out-Null
    }
    else {
        # Container folder (no .git itself, e.g. _GitHub) — scan one level deeper
        Get-ChildItem -Path $d.FullName -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName '.git') } |
        ForEach-Object { $rawRepos.Add($_.FullName) | Out-Null }
    }
}
$repos = @(
    $rawRepos |
    Where-Object { $_ -ne $forkPath } |
    Where-Object { -not (Test-SkipRepo (Split-Path -Leaf $_) $SkipRepos) } |
    Sort-Object
)
if ($repos.Count -eq 0) { Write-Host 'No git repos found in scan root.' -ForegroundColor Yellow; return }

# ── Manifest + layer-map helpers (loaded only for -FullDiff) ─────────────────
$manifest = $null
$forkLayerMap = $null
if ($FullDiff) {
    $manifestPath = Join-Path $aprSyncDir 'aproda-sync.json'
    $raw = Get-Content -LiteralPath $manifestPath -Raw
    $json = ($raw -split "`n" | ForEach-Object {
            ($_ -replace '^\s*//.*$', '') -replace '(?<![:"])//.*$', ''
        }) -join "`n"
    $manifest = $json | ConvertFrom-Json

    $script:pBase = if ($manifest.layouts.project.base) { [string]$manifest.layouts.project.base } else { '.github' }
    $script:fBase = if ($manifest.layouts.fork.base) { [string]$manifest.layouts.fork.base }    else { '.' }
    $script:fDotGh = @($manifest.layouts.fork.dotGithub)
    $script:iGlob = @($manifest.includeGlobs)
    $script:iFiles = @($manifest.includeFiles)
    $script:iPE = @($manifest.inPlaceEdits)
    $script:nTouch = @($manifest.neverTouch)
    $script:nTE = @($manifest.neverTouchExceptions)

    function _cvtGlob([string]$g) {
        $r = [System.Text.RegularExpressions.Regex]::Escape(($g -replace '\\', '/'))
        $r = $r -replace '/\\\*\\\*', '(/.*)?'; $r = $r -replace '\\\*\\\*', '.*'
        $r = $r -replace '\\\*', '[^/]*'; $r = $r -replace '\\\?', '[^/]'; "^$r$"
    }
    function _testGlob([string]$rel, [string[]]$globs) {
        foreach ($g in $globs) { if (![string]::IsNullOrWhiteSpace($g) -and $rel -match (_cvtGlob $g)) { return $true } }
        return $false
    }
    function _logical([string]$phys, [string]$side) {
        $p = $phys -replace '\\', '/'
        if ($side -eq 'project') {
            $pfx = $script:pBase.TrimEnd('/') + '/'
            if ($p.StartsWith($pfx)) { return $p.Substring($pfx.Length) }; return $null
        }
        if ($p.StartsWith('.github/')) {
            $r = $p.Substring('.github/'.Length)
            if (_testGlob $r $script:fDotGh) { return $r }; return $null
        }
        return $p
    }
    function _allowed([string]$log) {
        if ((_testGlob $log $script:nTouch) -and ($script:nTE -notcontains $log)) { return $false }
        (_testGlob $log $script:iGlob) -or ($script:iFiles -contains $log) -or ($script:iPE -contains $log)
    }
    function Build-LayerMap([string]$root, [string]$side) {
        $m = @{}
        Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = ($_.FullName.Substring($root.TrimEnd('\\').Length + 1)) -replace '\\', '/'
            if ($rel -match '^(\.git/|node_modules/)') { return }
            $log = _logical $rel $side; if ([string]::IsNullOrWhiteSpace($log)) { return }
            if (-not (_allowed $log)) { return }
            if (-not $m.ContainsKey($log)) { $m[$log] = $_.FullName }
        }; $m
    }
    $forkLayerMap = Build-LayerMap $forkPath 'fork'
}

# ── Evaluate each repo ────────────────────────────────────────────────────────
$results = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($repo in $repos) {
    $repoName = Split-Path -Leaf $repo
    $version = Get-LayerVersion $repo

    # No Aproda-ALDC detected
    if ($null -eq $version) {
        if ($IncludeNonAproda) {
            $results.Add([pscustomobject]@{
                    Repo = $repoName; Status = 'NONE'; Version = '-'; Diffs = '-'; Path = $repo
                }) | Out-Null
        }
        continue
    }

    # Version present but empty (aldc.yaml exists, no layerVersion line)
    if ($version -eq '') {
        $results.Add([pscustomobject]@{
                Repo = $repoName; Status = 'NO-VER'; Version = '?'; Diffs = '?'; Path = $repo
            }) | Out-Null
        continue
    }

    # Outdated version
    if ($version -ne $forkVersion) {
        $results.Add([pscustomobject]@{
                Repo = $repoName; Status = 'UPDATE'; Version = $version; Diffs = '?'; Path = $repo
            }) | Out-Null
        continue
    }

    # Same version — optionally check content
    $diffs = '-'
    if ($FullDiff -and $forkLayerMap) {
        $projMap = Build-LayerMap $repo 'project'
        $diffCount = 0
        foreach ($k in $forkLayerMap.Keys) {
            if (-not $projMap.ContainsKey($k)) { $diffCount++; continue }
            $h1 = (Get-FileHash -LiteralPath $forkLayerMap[$k] -Algorithm SHA256).Hash
            $h2 = (Get-FileHash -LiteralPath $projMap[$k]      -Algorithm SHA256).Hash
            if ($h1 -ne $h2) { $diffCount++ }
        }
        foreach ($k in $projMap.Keys) { if (-not $forkLayerMap.ContainsKey($k)) { $diffCount++ } }
        $diffs = $diffCount
    }

    $status = if ($FullDiff -and [int]$diffs -gt 0) { 'DRIFT' } else { 'OK' }
    $results.Add([pscustomobject]@{
            Repo = $repoName; Status = $status; Version = $version; Diffs = $diffs; Path = $repo
        }) | Out-Null
}

# ── Console output ─────────────────────────────────────────────────────────────
$padRepo = [Math]::Max(10, ($results | ForEach-Object { $_.Repo.Length } | Measure-Object -Maximum).Maximum)
$padVer = [Math]::Max(7, ($results | ForEach-Object { $_.Version.ToString().Length } | Measure-Object -Maximum).Maximum)

foreach ($r in $results) {
    $color = switch ($r.Status) {
        'OK' { 'Green' }
        'UPDATE' { 'Yellow' }
        'DRIFT' { 'Magenta' }
        'NO-VER' { 'DarkYellow' }
        default { 'DarkGray' }
    }
    $diffsStr = if ($r.Diffs -eq '-') { '      -' } else { "diffs=$($r.Diffs.ToString().PadLeft(3))" }
    Write-Host ('[{0,-6}]  {1}  version={2}  {3}' -f
        $r.Status,
        $r.Repo.PadRight($padRepo),
        $r.Version.ToString().PadRight($padVer),
        $diffsStr) -ForegroundColor $color
}

Write-Host ''
$summary = $results | Group-Object Status | Sort-Object Name |
ForEach-Object { "$($_.Name):$($_.Count)" }
Write-Host ("Summary: {0}  (of {1} repo(s) scanned)" -f ($summary -join '  '), $repos.Count) -ForegroundColor Cyan

# ── JSON report ────────────────────────────────────────────────────────────────
$outDir = Join-Path $aprSyncDir 'fleet\_status-output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $outDir "fleet-status-$ts.json"
[pscustomobject]@{
    timestamp   = (Get-Date -Format 'o')
    forkVersion = $forkVersion
    forkPath    = $forkPath
    searchRoot  = $SearchRoot
    fullDiff    = $FullDiff.IsPresent
    results     = $results
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outFile -Encoding UTF8
Write-Host "Report : $outFile" -ForegroundColor Green
Write-Host ''
