<#
.SYNOPSIS
    Aproda ALDC — one-time project initialization (idempotent), run after a pull.

.DESCRIPTION
    Seeds the project-local artifacts the toolkit needs but never syncs:
      1. plans/memory.md          — seeded once from the ALDC template (never pushed).
      2. .gitignore               — the Aproda machine-local patterns, kept inside a
                                     "# Aproda ALDC Tool - BEGIN/END" marker block so
                                     they are obvious and updated as one unit.
      3. *.code-workspace          — the .github root (toolkit discovery) + the external
                                     BCQuality knowledge root (consumed outside the build),
                                     plus the chat.useCustomizationsInParentRepositories
                                     setting so Copilot discovers the repo-root .github
                                     customizations even when a single app folder is opened.

    Split out of Start-Pull so the run script stays thin. SRP-safe: cmdlet-only, no
    path-based dot-sourcing — load its content and invoke:

        $src = Get-Content "$env:APRODA_SYNC_SCRIPTDIR\Initialize-AprodaProject.ps1" -Raw
        & ([ScriptBlock]::Create($src))

.NOTES
    Decision: D-19 (decisions.aproda.md). Sibling of Sync-AprodaLayer.ps1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ── Resolve roots ────────────────────────────────────────────────────────────
# Under SRP content-loading $PSScriptRoot is empty; fall back to the env var the
# Start-Pull script sets.
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $env:APRODA_SYNC_SCRIPTDIR
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Set `$env:APRODA_SYNC_SCRIPTDIR when loading content-based."
}

# Anchor at the REAL git root by walking up until a .git entry is found. This is
# encoding-safe (pure path ops) — parsing `git rev-parse` stdout mangles non-ASCII
# path segments (e.g. umlauts) under non-UTF-8 consoles. Robust for multi-app repos
# where .github sits at the repo root next to several app folders. Fall back to
# "scriptDir up 3" only when no .git is found (off-git).
$gitRoot = $null
$dir = Get-Item -LiteralPath $scriptDir
while ($null -ne $dir) {
    if (Test-Path -LiteralPath (Join-Path $dir.FullName '.git')) { $gitRoot = $dir.FullName; break }
    $dir = $dir.Parent
}
if ($gitRoot) {
    $projectRoot = $gitRoot
}
else {
    $projectRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
}
$githubRoot = Join-Path $projectRoot '.github'

# ── Init 1: seed plans/memory.md if not yet present (first pull only) ─────────
# The project-local memory.md is never synced back to the fork (plans/** is
# neverTouch for the syncer). This block seeds it once from the ALDC template.
$memoryTarget = Join-Path $githubRoot 'plans\memory.md'
$memorySource = Join-Path $githubRoot 'docs\templates\memory-template.md'
if (-not (Test-Path $memoryTarget)) {
    if (Test-Path $memorySource) {
        New-Item -ItemType Directory -Force (Split-Path $memoryTarget) | Out-Null
        Copy-Item $memorySource $memoryTarget
        Write-Host "Init: plans/memory.md created from template."
    }
    else {
        Write-Warning "Memory template not found at $memorySource — skipping init."
    }
}
else {
    Write-Host "Init: plans/memory.md already exists — skipped."
}

# ── Init 2: keep the Aproda machine-local .gitignore block in sync ────────────
# All Aproda patterns live inside one labelled marker block so they are easy to
# spot and maintained as a unit. Idempotent: if the block already matches it is
# left untouched (no EOL churn); otherwise it is replaced/appended in place.
$gitignorePath = Join-Path $projectRoot '.gitignore'
$beginMarker = '# Aproda ALDC Tool - BEGIN'
$endMarker = '# Aproda ALDC Tool - END'
$blockLines = @(
    $beginMarker,
    '# Local start scripts (machine-specific paths — copy from *.template and fill in)',
    '.github/tools/aproda-sync/Start-Push.ps1',
    '.github/tools/aproda-sync/Start-Pull.ps1',
    '# Test-loop scratch / probe / run output (throwaway work)',
    '**/PowerShell/_temp/',
    '# Test-loop runner — materialized from BC Service DLLs (Microsoft binaries), never source',
    '**/PowerShell/_runner/',
    $endMarker
)
# Wrap the whole conditional in @(...): a bare `else { @() }` would be enumerated to
# zero pipeline items and collapse to $null (PowerShell gotcha), crashing IndexOf on a
# fresh repo that has no .gitignore yet. @( if (...) { ... } ) yields a real empty array.
$lines = @(if (Test-Path $gitignorePath) { Get-Content $gitignorePath })
$beginIdx = [array]::IndexOf($lines, $beginMarker)
$endIdx = [array]::IndexOf($lines, $endMarker)

if ($beginIdx -ge 0 -and $endIdx -gt $beginIdx) {
    # Marker block exists — replace only if its content differs.
    $currentBlock = $lines[$beginIdx..$endIdx]
    if (($currentBlock -join "`n") -eq ($blockLines -join "`n")) {
        Write-Host "Init: .gitignore Aproda block already current — skipped."
    }
    else {
        $before = @(if ($beginIdx -gt 0) { $lines[0..($beginIdx - 1)] })
        $after = @(if ($endIdx -lt ($lines.Count - 1)) { $lines[($endIdx + 1)..($lines.Count - 1)] })
        Set-Content -Path $gitignorePath -Value ($before + $blockLines + $after)
        Write-Host "Init: .gitignore Aproda block updated."
    }
}
else {
    # No marker block — append one (separated by a blank line if the file is non-empty).
    $prefix = @(if ($lines.Count -gt 0 -and $lines[-1] -ne '') { '' })
    Add-Content -Path $gitignorePath -Value ($prefix + $blockLines)
    Write-Host "Init: .gitignore Aproda block added."
}

# ── Init 3: ensure the *.code-workspace carries the roots ALDC needs ──────────
# Two roots must be present for the toolkit to work when you open the workspace:
#   1) the .github root — the toolkit (copilot-instructions, instructions/, prompts/,
#      agents/) lives here; surfacing it as a folder keeps it editable/visible.
#   2) the BCQuality knowledge base — consumed multi-root from OUTSIDE the project
#      (../bcquality) so its example .al files never enter compilation.
# Both are added only when missing (idempotent). JSONC that does not parse is left
# untouched with a manual hint.
$requiredRoots = @(
    @{ name = '.github'; path = '.github'; match = '^\.github$' },
    @{ name = 'BCQuality (knowledge — not compiled)'; path = '../bcquality'; match = 'bcquality' }
)
# Settings ALDC needs surfaced in every workspace. parentCustomizations lets Copilot
# walk up to the .git root and pick up the repo-root .github customizations even when
# only a single app folder is opened (VS Code: chat.useCustomizationsInParentRepositories).
$parentCustomizationsKey = 'chat.useCustomizationsInParentRepositories'
$wsFiles = Get-ChildItem -Path $projectRoot -Filter '*.code-workspace' -File -ErrorAction SilentlyContinue
if (-not $wsFiles) {
    $ws = [ordered]@{
        folders  = @($requiredRoots | ForEach-Object { [ordered]@{ name = $_.name; path = $_.path } })
        settings = [ordered]@{ $parentCustomizationsKey = $true }
    }
    $target = Join-Path $projectRoot 'aldc.code-workspace'
    $ws | ConvertTo-Json -Depth 10 | Set-Content -Path $target -Encoding UTF8
    Write-Host "Init: aldc.code-workspace created (.github + BCQuality roots, parent customizations on)."
}
else {
    foreach ($wsFile in $wsFiles) {
        $raw = Get-Content $wsFile.FullName -Raw
        try {
            $json = $raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Warning "Init: could not parse $($wsFile.Name) (JSONC/comments?). Ensure it has roots: '.github' and a BCQuality folder."
            continue
        }
        if (-not $json.folders) {
            $json | Add-Member -NotePropertyName folders -NotePropertyValue @() -Force
        }
        $existingPaths = @($json.folders | ForEach-Object { "$($_.path)" })
        $added = @()
        foreach ($root in $requiredRoots) {
            $present = $existingPaths | Where-Object { $_ -match $root.match }
            if (-not $present) {
                $json.folders = @($json.folders) + ([pscustomobject]@{ name = $root.name; path = $root.path })
                $added += $root.path
            }
        }
        # Ensure the parent-customizations setting is present (idempotent).
        if (-not $json.settings) {
            $json | Add-Member -NotePropertyName settings -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $settingChanged = $false
        if ($json.settings.$parentCustomizationsKey -ne $true) {
            $json.settings | Add-Member -NotePropertyName $parentCustomizationsKey -NotePropertyValue $true -Force
            $settingChanged = $true
        }
        if ($added.Count -gt 0 -or $settingChanged) {
            $json | ConvertTo-Json -Depth 10 | Set-Content -Path $wsFile.FullName -Encoding UTF8
            $changes = @()
            if ($added.Count -gt 0) { $changes += "root(s): $($added -join ', ')" }
            if ($settingChanged) { $changes += $parentCustomizationsKey }
            Write-Host "Init: $($wsFile.Name) — updated ($($changes -join '; '))."
        }
        else {
            Write-Host "Init: $($wsFile.Name) already has the required roots and settings — skipped."
        }
    }
}
