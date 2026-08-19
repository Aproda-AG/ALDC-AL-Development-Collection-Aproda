# Aproda Fleet — Layer Gatherer  (FORK-ONLY; not synced to project repos)
# PURPOSE : Bring in-place edits from local project repos back into this fork.
#           Runs a layer push (project → fork) per selected repo.
# HOME    : <fork>/tools/aproda-sync/fleet/Start-FleetGather.ps1
# RUN     : Open → Select All → "PowerShell: Run Selection"  (SRP-safe)
#           Nothing to fill in — fork is self-resolved from this file's location.
#
# CONFLICT GUARD
#   Before writing to the fork, this script checks for uncommitted changes in the
#   fork (tracked files only). If any are found → abort with clear message.
#   Rationale: gather overwrites fork files; unresolved modifications would be
#   silently lost. Commit or stash first, then run again.
#
# SELECTION
#   Repos are selected interactively (Out-GridView or console index fallback),
#   consistent with Start-InitNewProject. Only repos WITH Aproda-ALDC are offered.
#
# BEST PRACTICE: run Get-AprodaFleetStatus -FullDiff first to identify which
#   repos have diverged (DRIFT status) before gathering.

[CmdletBinding()]
param(
    [string]   $SearchRoot = '',  # Folder to scan. Default: parent folder of fork.
    [string[]] $SkipRepos  = @('BCQuality*', 'bcquality*'),
    [switch]   $WhatIf            # Dry-run: show what would be copied, change nothing.
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
    }
    catch {}
}
if ([string]::IsNullOrWhiteSpace($forkPath) -or -not (Test-Path $forkPath)) {
    Write-Error 'Cannot self-locate fork. Set $env:APRODA_SYNC_SCRIPTDIR = "<fork>/tools/aproda-sync".'
    return
}
$aprSyncDir = Join-Path $forkPath 'tools\aproda-sync'

# ── Conflict guard: fork must be clean before gather ─────────────────────────
# Any uncommitted tracked modification in the fork risks being silently overwritten.
# Untracked files (??) are harmless: gather (push) is overlay-only and will not
# delete or touch files that don't exist in the project source.
if (-not $WhatIf) {
    $gitStatus = @(git -C $forkPath status --porcelain 2>$null |
        Where-Object { $_ -notmatch '^\?\?' -and $_ -match '\S' })
    if ($gitStatus.Count -gt 0) {
        Write-Host ''
        Write-Host 'KONFLIKT — Der Fork enthält nicht-committete Änderungen.' -ForegroundColor Red
        Write-Host 'Gather würde diese Dateien überschreiben. Bitte erst committen' -ForegroundColor Red
        Write-Host 'oder stashen, dann erneut ausführen.' -ForegroundColor Red
        Write-Host ''
        Write-Host 'Betroffene Dateien im Fork:' -ForegroundColor DarkRed
        $gitStatus | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
        Write-Host ''
        Write-Host 'Abbruch.' -ForegroundColor Red
        return
    }
}

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

# ── Scan repos with Aproda-ALDC ───────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($SearchRoot)) { $SearchRoot = Split-Path -Parent $forkPath }
Write-Host ''
Write-Host "Fork     : $forkPath" -ForegroundColor Cyan
Write-Host "Scanning : $SearchRoot" -ForegroundColor Cyan
if ($WhatIf) { Write-Host '         : WhatIf — no files will be changed' -ForegroundColor DarkYellow }
Write-Host ''

$allRepos = @(
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

$candidates = @($allRepos | Where-Object {
        $null -ne (Get-LayerVersion $_)
    })

if ($candidates.Count -eq 0) {
    Write-Host 'No repos with Aproda-ALDC found.' -ForegroundColor Yellow
    return
}

Write-Host "Repos with Aproda-ALDC ($($candidates.Count)):" -ForegroundColor Cyan
$candidates | ForEach-Object { Write-Host "  $(Split-Path -Leaf $_)" -ForegroundColor Gray }
Write-Host ''

# ── Interactive selection ─────────────────────────────────────────────────────
$selected = @()

# Tier 1: Out-GridView (GUI)
if ($candidates.Count -gt 0 -and (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
    Write-Host 'Select repo(s) to gather from (multi-select supported, or cancel to enter index manually)...'
    $picked = $candidates | Out-GridView -Title 'Select repo(s) to gather from (project → fork)' -OutputMode Multiple
    if ($picked) { $selected = @($picked) }
}

# Tier 2: Console index fallback
if ($selected.Count -eq 0) {
    Write-Host '=== Select repo(s) to gather from ===' -ForegroundColor Cyan
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        Write-Host "  [$i] $(Split-Path -Leaf $candidates[$i])" -ForegroundColor Yellow
    }
    Write-Host "  [A] All repos listed above" -ForegroundColor Yellow
    Write-Host ''
    $inp = (Read-Host "Enter index (0-$($candidates.Count-1)), comma-separated indices, or A for all").Trim()
    if ($inp -match '^[Aa]$') {
        $selected = @($candidates)
    }
    elseif ($inp -match '^[\d,\s]+$') {
        $indices = $inp -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ } | Where-Object { $_ -lt $candidates.Count }
        $selected = @($indices | ForEach-Object { $candidates[$_] })
    }
}

if ($selected.Count -eq 0) {
    Write-Host 'No repos selected. Aborted.' -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host "Selected for gather ($($selected.Count)):" -ForegroundColor Cyan
$selected | ForEach-Object { Write-Host "  $(Split-Path -Leaf $_)" -ForegroundColor White }
Write-Host ''

# ── Load engine content (SRP-safe) ────────────────────────────────────────────
$enginePath = Join-Path $aprSyncDir 'Sync-AprodaLayer.ps1'
if (-not (Test-Path $enginePath)) { Write-Error "Engine not found: $enginePath"; return }
$engineSrc = Get-Content -LiteralPath $enginePath -Raw
$env:APRODA_SYNC_SCRIPTDIR = $aprSyncDir

# ── Gather from each selected repo ───────────────────────────────────────────
$done = 0; $failed = 0

foreach ($repo in $selected) {
    $name = Split-Path -Leaf $repo
    Write-Host "── Gathering from: $name ─────────────────────────────────────" -ForegroundColor Cyan
    try {
        if ($WhatIf) {
            & ([ScriptBlock]::Create($engineSrc)) `
                -Direction push -ForkPath $forkPath -ProjectRoot $repo -WhatIf
        }
        else {
            & ([ScriptBlock]::Create($engineSrc)) `
                -Direction push -ForkPath $forkPath -ProjectRoot $repo
        }
        Write-Host "[DONE]  $name" -ForegroundColor Green
        $done++
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
    Write-Host "WhatIf: $($selected.Count) repo(s) would be gathered." -ForegroundColor DarkYellow
}
else {
    $col = if ($failed -eq 0) { 'Green' } else { 'Yellow' }
    Write-Host ("Gathered: $done  Failed: $failed") -ForegroundColor $col
    if ($done -gt 0) {
        Write-Host ''
        Write-Host 'Review the changes in the fork and commit when ready.' -ForegroundColor Cyan
    }
}
Write-Host ''
