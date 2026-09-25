<#
.SYNOPSIS
    Verify the D-7 Upstream-edits register: every aproda-sync.json -> inPlaceEdits
    path must actually differ from the pinned upstream base (E-006 T-7).

.DESCRIPTION
    A path listed in `inPlaceEdits` claims "we edited this Upstream file in place".
    That claim silently rots if the edit is registered but never applied to disk —
    exactly what happened to tools/aldc-validate/index.js (E-006 T-9: registered
    2026-06-25, applied 2026-09-24; every release in between certified "ALDC Core
    v1.1 COMPLIANT" against a v1.2 config).

    For each `inPlaceEdits` entry (written in PROJECT layout, relative to .github/):
      1. Resolve its fork-side physical path via `layouts.fork.dotGithub`.
      2. Diff that path against `aldc.yaml -> aproda.basePin`.
      3. An EMPTY diff (file exists at the pin, unchanged since) means the
         registered edit was never applied -> reported as FAIL.

    Run this before every layer release (skill-aproda-aldc-release).

.PARAMETER RepoRoot
    Fork repo root. Defaults to the git root found by walking up from this script.

.PARAMETER BasePin
    Override the commit to diff against. Defaults to `aldc.yaml -> aproda.basePin`.

.EXAMPLE
    .\Test-InPlaceEditsRegister.ps1

.NOTES
    Decision: D-7 / D-4 (decisions.aproda.md). Manifest: aproda-sync.json. E-006 T-7.
    SRP-safe: cmdlets only, no path-based dot-sourcing / Import-Module of other scripts.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string] $RepoRoot,

    [Parameter(Mandatory = $false)]
    [string] $BasePin
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $env:APRODA_SYNC_SCRIPTDIR
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Pass it via `$env:APRODA_SYNC_SCRIPTDIR when loading content-based."
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $gitRoot = $null
    $dir = Get-Item -LiteralPath $scriptDir
    while ($null -ne $dir) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName '.git')) { $gitRoot = $dir.FullName; break }
        $dir = $dir.Parent
    }
    if (-not $gitRoot) { throw "Cannot find a .git root above $scriptDir. Pass -RepoRoot explicitly." }
    $RepoRoot = $gitRoot
}

$manifestPath = Join-Path $scriptDir 'aproda-sync.json'
if (-not (Test-Path $manifestPath)) { throw "Manifest not found: $manifestPath" }

# JSONC: strip // line comments before parsing (naive but sufficient — no // inside strings here).
$manifestRaw = Get-Content -LiteralPath $manifestPath -Raw
$manifestJson = ($manifestRaw -split "`n" | ForEach-Object {
        ($_ -replace '^\s*//.*$', '') -replace '(?<![:"])//.*$', ''
    }) -join "`n"
$manifest = $manifestJson | ConvertFrom-Json

$inPlaceEdits = @($manifest.inPlaceEdits)
$forkDotGithub = @()
if ($manifest.layouts -and $manifest.layouts.fork -and $manifest.layouts.fork.dotGithub) {
    $forkDotGithub = @($manifest.layouts.fork.dotGithub)
}

# Same glob machinery as Sync-AprodaLayer.ps1 (kept duplicated on purpose — no cross-script dot-sourcing).
function Convert-GlobToRegex([string] $glob) {
    $g = $glob -replace '\\', '/'
    $re = [System.Text.RegularExpressions.Regex]::Escape($g)
    $re = $re -replace '/\\\*\\\*', '(/.*)?'
    $re = $re -replace '\\\*\\\*', '.*'
    $re = $re -replace '\\\*', '[^/]*'
    $re = $re -replace '\\\?', '[^/]'
    return ('^' + $re + '$')
}

function Test-AnyGlob([string] $relPath, [string[]] $globs) {
    foreach ($g in $globs) {
        if ([string]::IsNullOrWhiteSpace($g)) { continue }
        if ($relPath -match (Convert-GlobToRegex $g)) { return $true }
    }
    return $false
}

# inPlaceEdits entries are written in PROJECT layout (relative to .github/); resolve
# the fork-side physical path the same way Sync-AprodaLayer.ps1's Get-PhysicalPath does.
function Get-ForkPhysicalPath([string] $logical) {
    if (Test-AnyGlob $logical $forkDotGithub) {
        return ('.github/' + $logical)
    }
    return $logical
}

function Test-CommitReachable([string] $rev) {
    git cat-file -e "$rev^{commit}" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Test-PathAtRev([string] $rev, [string] $path) {
    git cat-file -e "${rev}:${path}" 2>$null
    return ($LASTEXITCODE -eq 0)
}

if ([string]::IsNullOrWhiteSpace($BasePin)) {
    # aldc.yaml lives at <toolkitRoot>/aldc.yaml (T-33): .github/ in a project, the repo root in the fork.
    $aldcYamlPath = @((Join-Path '.github' 'aldc.yaml'), 'aldc.yaml') |
        ForEach-Object { Join-Path $RepoRoot $_ } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $aldcYamlPath) { throw "aldc.yaml not found under $RepoRoot (.github/ or repo root)" }
    $inAproda = $false
    foreach ($line in (Get-Content -LiteralPath $aldcYamlPath)) {
        if ($line -match '^aproda:\s*$') { $inAproda = $true; continue }
        if ($inAproda -and $line -match '^\S') { $inAproda = $false } # left the aproda: block
        if ($inAproda -and $line -match '^\s*basePin:\s*"([0-9a-f]{7,40})"') {
            $BasePin = $Matches[1]
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($BasePin)) { throw "Could not read aproda.basePin from $aldcYamlPath" }
}

Push-Location -LiteralPath $RepoRoot
try {
    if (-not (Test-CommitReachable $BasePin)) {
        throw "basePin '$BasePin' is not a reachable commit in this repo. Fetch the upstream mirror (origin/main) first."
    }

    $results = foreach ($logical in $inPlaceEdits) {
        $physical = Get-ForkPhysicalPath $logical
        $existsOnDisk = Test-Path -LiteralPath (Join-Path $RepoRoot $physical)
        $existsAtPin = Test-PathAtRev $BasePin $physical
        $diffStat = if ($existsAtPin) { git diff --stat "$BasePin" -- "$physical" 2>$null } else { $null }

        $status =
        if (-not $existsOnDisk) { 'MISSING-ON-DISK — registered path does not exist' }
        elseif ($existsAtPin -and [string]::IsNullOrWhiteSpace($diffStat)) { 'FAIL — byte-identical to upstream, registered edit not applied' }
        else { 'ok' }

        [pscustomobject]@{
            InPlaceEditsPath = $logical
            ForkPath         = $physical
            ExistsAtBasePin  = $existsAtPin
            Status           = $status
        }
    }
}
finally {
    Pop-Location
}

$results | Format-Table -AutoSize -Wrap

$failures = @($results | Where-Object { $_.Status -ne 'ok' })
if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Warning "$($failures.Count) of $($results.Count) inPlaceEdits path(s) failed register verification against basePin $BasePin."
    exit 1
}

Write-Host ""
Write-Host "All $($results.Count) inPlaceEdits paths verified against basePin $BasePin." -ForegroundColor Green
exit 0
