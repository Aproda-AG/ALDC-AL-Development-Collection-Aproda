# Aproda Fleet — Layer Updater  (FORK-ONLY; not synced to project repos)
# PURPOSE : Update all local project repos whose Aproda-ALDC layer version is
#           older than this fork by running a layer pull per outdated repo.
# HOME    : <fork>/tools/aproda-sync/fleet/Start-FleetUpdate.ps1
# RUN     : Open → Select All → "PowerShell: Run Selection"  (SRP-safe)
#           Nothing to fill in — fork is self-resolved from this file's location.
#
# SKIPPED : repos with the same version as the fork (already current)
#           repos without Aproda-ALDC (no .github/aldc.yaml with layerVersion)
# BEST PRACTICE: run Get-AprodaFleetStatus first to preview which repos need update.

[CmdletBinding()]
param(
    [string]   $SearchRoot = '',  # Folder to scan. Default: parent folder of fork.
    [string[]] $SkipRepos  = @('BCQuality*', 'bcquality*'),
    [switch]   $WhatIf            # Dry-run: show what would be done, copy nothing.
)

$ErrorActionPreference = 'Stop'

# ── Self-locate fork root ─────────────────────────────────────────────────────
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
    } catch {}
}
if ([string]::IsNullOrWhiteSpace($forkPath) -or -not (Test-Path $forkPath)) {
    Write-Error 'Cannot self-locate fork. Set $env:APRODA_SYNC_SCRIPTDIR = "<fork>/tools/aproda-sync".'
    return
}
$aprSyncDir = Join-Path $forkPath 'tools\aproda-sync'

# ── Version helper ────────────────────────────────────────────────────────────
# aldc.yaml always sits at the REPO ROOT on both fork and project side (dual-variant, D-18).
function Get-LayerVersion([string] $repoRoot) {
    $yaml = Join-Path $repoRoot 'aldc.yaml'
    if (-not (Test-Path -LiteralPath $yaml)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $yaml -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s+layerVersion:\s*"([^"]+)"') { return $Matches[1] }
    }
    return $null
}

$forkVersion = Get-LayerVersion $forkPath
if (-not $forkVersion) {
    Write-Error "Could not read aproda.layerVersion from fork: $forkPath\aldc.yaml"
    return
}

# ── Scan repos ────────────────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($SearchRoot)) { $SearchRoot = Split-Path -Parent $forkPath }
Write-Host ''
Write-Host "Fork         : $forkPath" -ForegroundColor Cyan
Write-Host "Fork version : $forkVersion" -ForegroundColor Cyan
Write-Host "Scanning     : $SearchRoot" -ForegroundColor Cyan
if ($WhatIf) { Write-Host '             : WhatIf — no files will be changed' -ForegroundColor DarkYellow }
Write-Host ''

$repos = @(
    (& {
        $allTop = @(Get-ChildItem -Path $SearchRoot -Directory -ErrorAction SilentlyContinue)
        $found  = [System.Collections.Generic.List[string]]::new()
        foreach ($d in $allTop) {
            if (Test-Path (Join-Path $d.FullName '.git')) { $found.Add($d.FullName) | Out-Null }
            else {
                Get-ChildItem -Path $d.FullName -Directory -ErrorAction SilentlyContinue |
                    Where-Object { Test-Path (Join-Path $_.FullName '.git') } |
                    ForEach-Object { $found.Add($_.FullName) | Out-Null }
            }
        }
        $found
    }) |
    Where-Object { $_ -ne $forkPath } |
    Where-Object { $n = Split-Path -Leaf $_; -not ($SkipRepos | Where-Object { $n -like $_ }) } |
    Sort-Object
)
if ($repos.Count -eq 0) { Write-Host 'No git repos found in scan root.' -ForegroundColor Yellow; return }

# ── Classify repos ────────────────────────────────────────────────────────────
$toUpdate = [System.Collections.Generic.List[string]]::new()
$current  = [System.Collections.Generic.List[string]]::new()
$skipped  = [System.Collections.Generic.List[string]]::new()

foreach ($repo in $repos) {
    $version = Get-LayerVersion $repo
    if ($null -eq $version) { $skipped.Add($repo) | Out-Null; continue }
    if ($version -eq $forkVersion) { $current.Add($repo) | Out-Null; continue }
    $toUpdate.Add($repo) | Out-Null
    Write-Host ("[UPDATE]  {0,-45}  v={1}  ->  {2}" -f (Split-Path -Leaf $repo), $version, $forkVersion) -ForegroundColor Yellow
}
foreach ($r in $current) {
    Write-Host ("[OK    ]  {0,-45}  v={1}" -f (Split-Path -Leaf $r), $forkVersion) -ForegroundColor Green
}
foreach ($r in $skipped) {
    Write-Host ("[SKIP  ]  {0,-45}  no Aproda-ALDC" -f (Split-Path -Leaf $r)) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host ("Found: {0} to update,  {1} already current,  {2} skipped (no ALDC)" -f
    $toUpdate.Count, $current.Count, $skipped.Count) -ForegroundColor Cyan

if ($toUpdate.Count -eq 0) { Write-Host 'Nothing to do.' -ForegroundColor Green; Write-Host ''; return }

# ── Load engine content (SRP-safe) ────────────────────────────────────────────
$enginePath = Join-Path $aprSyncDir 'Sync-AprodaLayer.ps1'
if (-not (Test-Path $enginePath)) { Write-Error "Engine not found: $enginePath"; return }
$engineSrc = Get-Content -LiteralPath $enginePath -Raw

# ── Update each outdated repo ─────────────────────────────────────────────────
Write-Host ''
$env:APRODA_SYNC_SCRIPTDIR = $aprSyncDir  # engine self-location via env var
$updated = 0; $failed = 0

foreach ($repo in $toUpdate) {
    $name = Split-Path -Leaf $repo
    Write-Host "── Updating: $name ──────────────────────────────────────────" -ForegroundColor Cyan
    try {
        if ($WhatIf) {
            & ([ScriptBlock]::Create($engineSrc)) `
                -Direction pull -ForkPath $forkPath -ProjectRoot $repo -WhatIf
        } else {
            & ([ScriptBlock]::Create($engineSrc)) `
                -Direction pull -ForkPath $forkPath -ProjectRoot $repo
        }
        Write-Host "[DONE]  $name" -ForegroundColor Green
        $updated++
    }
    catch {
        Write-Host "[FAIL]  $name — $_" -ForegroundColor Red
        $failed++
    }
    Write-Host ''
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host '════════════════════════════════════════' -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host "WhatIf: $($toUpdate.Count) repo(s) would be updated." -ForegroundColor DarkYellow
} else {
    $col = if ($failed -eq 0) { 'Green' } else { 'Yellow' }
    Write-Host ("Updated: $updated  Failed: $failed  Skipped: $($skipped.Count)") -ForegroundColor $col
}
Write-Host ''
