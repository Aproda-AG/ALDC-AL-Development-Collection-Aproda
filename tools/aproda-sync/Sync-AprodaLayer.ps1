<#
.SYNOPSIS
    Sync the Aproda ALDC layer between a project repo and the aproda-aldc fork,
    using an ALLOWLIST manifest (aproda-sync.json, D-18).

.DESCRIPTION
    Two directions, both OVERLAY-only (never delete files that are not part of
    the layer) and both restricted to the manifest allowlist:

        pull : fork  -> project   copy layer files INTO this repo's .github/
        push : project -> fork    stage layer files into a fork working clone

    Default = SAFE. Only paths resolved from the manifest are ever touched:
      - includeGlobs            (**/*.aproda.* ; skills/skill-aproda-*/**)
      - includeFiles            (named net-new files)
      - inPlaceEdits            (Upstream files we edited — the D-7 register)
      - aldc.yaml required/optional   (when includeAldcFramework = true)
    minus anything caught by neverTouch (unless listed in neverTouchExceptions).

    AL-Go system files, plans/, documentation/, app code and any UNKNOWN future
    file are never matched -> never overwritten, never uploaded.

    SRP-safe: this script is loaded content-based by the caller; it uses only
    cmdlets (no path-based dot-sourcing / Import-Module of other scripts).

.PARAMETER Direction
    'pull' or 'push'.

.PARAMETER ForkPath
    Local path to a clone of the aproda-aldc fork (the OTHER side of the sync).
    For pull: the source. For push: the destination working clone.

.PARAMETER ProjectRoot
    Repo root of THIS project (the one containing .github/). Defaults to two
    levels up from this script (.github/tools/aproda-sync -> repo root).

.PARAMETER WhatIf
    Dry-run: print the resolved file set and the planned copies, change nothing.

.EXAMPLE
    # Preview what a pull would bring in
    .\Sync-AprodaLayer.ps1 -Direction pull -ForkPath C:\src\aproda-aldc -WhatIf

.EXAMPLE
    # Apply a pull
    .\Sync-AprodaLayer.ps1 -Direction pull -ForkPath C:\src\aproda-aldc

.NOTES
    Decision: D-18 (decisions.aproda.md). Manifest: aproda-sync.json.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('pull', 'push')]
    [string] $Direction,

    [Parameter(Mandatory = $true)]
    [string] $ForkPath,

    [Parameter(Mandatory = $false)]
    [string] $ProjectRoot
)

$ErrorActionPreference = 'Stop'

# ── Resolve roots ────────────────────────────────────────────────────────────
# This script: <repoRoot>/.github/tools/aproda-sync/Sync-AprodaLayer.ps1
# Under SRP content-loading $PSScriptRoot may be empty; fall back to env var.
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $env:APRODA_SYNC_SCRIPTDIR
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Pass it via `$env:APRODA_SYNC_SCRIPTDIR when loading content-based."
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    # .github/tools/aproda-sync -> up 3 -> repo root
    $ProjectRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
}

$manifestPath = Join-Path $scriptDir 'aproda-sync.json'
if (-not (Test-Path $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}

# JSONC: strip // line comments before parsing (naive but sufficient — no // inside strings here).
$manifestRaw = (Get-Content -LiteralPath $manifestPath -Raw)
$manifestJson = ($manifestRaw -split "`n" | ForEach-Object {
        ($_ -replace '^\s*//.*$', '') -replace '(?<![:"])//.*$', ''
    }) -join "`n"
$manifest = $manifestJson | ConvertFrom-Json

# Layout profiles (asymmetric — distilled from the ALDC extension's root<->.github
# remap). Logical paths in the manifest are PROJECT-layout (relative to .github/).
$projectBase = '.github'
if ($manifest.layouts -and $manifest.layouts.project -and $manifest.layouts.project.base) {
    $projectBase = $manifest.layouts.project.base
}
$forkBase = '.'
$forkDotGithub = @()
if ($manifest.layouts -and $manifest.layouts.fork) {
    if ($manifest.layouts.fork.base) { $forkBase = $manifest.layouts.fork.base }
    if ($manifest.layouts.fork.dotGithub) { $forkDotGithub = @($manifest.layouts.fork.dotGithub) }
}

# Source/destination are whole repo roots (not a single toolkit root) because the
# fork splits the layer across root + .github/.
if ($Direction -eq 'pull') {
    $srcRepo = $ForkPath
    $dstRepo = $ProjectRoot
    $srcSide = 'fork'
    $dstSide = 'project'
}
else {
    $srcRepo = $ProjectRoot
    $dstRepo = $ForkPath
    $srcSide = 'project'
    $dstSide = 'fork'
}

if (-not (Test-Path $srcRepo)) { throw "Source repo root not found: $srcRepo" }
if (-not (Test-Path $dstRepo)) { throw "Destination repo root not found: $dstRepo" }

Write-Host "Aproda layer sync — $Direction" -ForegroundColor Cyan
Write-Host "  source : $srcRepo ($srcSide layout)"
Write-Host "  dest   : $dstRepo ($dstSide layout)"
Write-Host ""

# ── Helpers ──────────────────────────────────────────────────────────────────

# Convert a manifest glob (toolkit-relative) into a regex anchored to '/'-paths.
function Convert-GlobToRegex([string] $glob) {
    $g = $glob -replace '\\', '/'
    $re = [System.Text.RegularExpressions.Regex]::Escape($g)
    # Restore glob tokens. Order matters: '**' before '*'.
    $re = $re -replace '/\\\*\\\*', '(/.*)?'   # '/**' -> optional deep
    $re = $re -replace '\\\*\\\*', '.*'        # '**'  -> any
    $re = $re -replace '\\\*', '[^/]*'         # '*'   -> segment
    $re = $re -replace '\\\?', '[^/]'          # '?'   -> one char
    return ('^' + $re + '$')
}

function Test-AnyGlob([string] $relPath, [string[]] $globs) {
    foreach ($g in $globs) {
        if ([string]::IsNullOrWhiteSpace($g)) { continue }
        if ($relPath -match (Convert-GlobToRegex $g)) { return $true }
    }
    return $false
}

# Forward map: LOGICAL path (project-layout, relative to .github/) -> physical
# path relative to a side's repo root.
function Get-PhysicalPath([string] $logical, [string] $side) {
    if ($side -eq 'project') {
        return (($projectBase.TrimEnd('/') + '/' + $logical) -replace '^\./', '')
    }
    # fork side
    if (Test-AnyGlob $logical $forkDotGithub) {
        return ('.github/' + $logical)
    }
    if ($forkBase -eq '.' -or [string]::IsNullOrWhiteSpace($forkBase)) {
        return $logical
    }
    return ($forkBase.TrimEnd('/') + '/' + $logical)
}

# Reverse map: physical path (relative to a side's repo root) -> LOGICAL path,
# or $null if the physical file is not part of the layer's namespace on that side.
function Get-LogicalPath([string] $physical, [string] $side) {
    $p = $physical -replace '\\', '/'
    if ($side -eq 'project') {
        $prefix = $projectBase.TrimEnd('/') + '/'
        if ($p.StartsWith($prefix)) { return $p.Substring($prefix.Length) }
        return $null
    }
    # fork side
    if ($p.StartsWith('.github/')) {
        $rem = $p.Substring('.github/'.Length)
        if (Test-AnyGlob $rem $forkDotGithub) { return $rem }
        return $null   # fork's own .github content (e.g. plans/) — not our layer
    }
    return $p          # root-level toolkit file -> logical is itself
}

# ── Build the allowlist set (toolkit-relative paths) ─────────────────────────
$includeGlobs = @($manifest.includeGlobs)
$includeFiles = @($manifest.includeFiles)
$inPlaceEdits = @($manifest.inPlaceEdits)
$neverTouch = @($manifest.neverTouch)
$neverTouchExceptions = @($manifest.neverTouchExceptions)

$frameworkFiles = @()
if ($manifest.includeAldcFramework) {
    $aldcYamlPath = Join-Path $ProjectRoot ($manifest.aldcYaml)
    if (Test-Path $aldcYamlPath) {
        # Lightweight YAML scrape: collect quoted "path/like/this" list entries under
        # required:/optional:. We only need the file paths, not full YAML semantics.
        $yamlLines = Get-Content -LiteralPath $aldcYamlPath
        foreach ($line in $yamlLines) {
            $m = [regex]::Match($line, '^\s*-\s*"([^"]+\.(md|py|sh|js))"\s*$')
            if ($m.Success) { $frameworkFiles += $m.Groups[1].Value }
        }
        $frameworkFiles = $frameworkFiles | Sort-Object -Unique
    }
    else {
        Write-Warning "includeAldcFramework=true but aldc.yaml not found at $aldcYamlPath — skipping framework files."
    }
}

function Test-Allowed([string] $logical) {
    return (
        (Test-AnyGlob $logical $includeGlobs) -or
        ($includeFiles -contains $logical) -or
        ($inPlaceEdits -contains $logical) -or
        ($frameworkFiles -contains $logical)
    )
}

# Enumerate every file in the SOURCE repo, reverse-map to a LOGICAL path, then
# apply the allowlist on the logical path. This is layout-aware: the same logical
# file resolves to root on the fork side and to .github/ on the project side.
$allSrc = Get-ChildItem -LiteralPath $srcRepo -Recurse -File -Force -ErrorAction SilentlyContinue |
ForEach-Object { ($_.FullName.Substring($srcRepo.TrimEnd('\').Length + 1)) -replace '\\', '/' }

$selected = New-Object System.Collections.Generic.List[string]
foreach ($phys in $allSrc) {

    # Skip VCS / noise early.
    if ($phys -match '^(\.git/|node_modules/)') { continue }

    $logical = Get-LogicalPath $phys $srcSide
    if ([string]::IsNullOrWhiteSpace($logical)) { continue }

    if (-not (Test-Allowed $logical)) { continue }

    # Hard deny tripwire (logical-path based; unless an explicit exception).
    if ((Test-AnyGlob $logical $neverTouch) -and -not ($neverTouchExceptions -contains $logical)) {
        Write-Warning "SKIP (neverTouch): $logical"
        continue
    }

    $selected.Add($logical) | Out-Null
}

if ($selected.Count -eq 0) {
    Write-Warning "No files matched the allowlist. Nothing to do."
    return
}

Write-Host "Resolved $($selected.Count) layer file(s) [logical paths]:" -ForegroundColor Green
$selected | Sort-Object | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# ── Apply (OVERLAY: copy only; never delete anything at the destination) ─────
$copied = 0
foreach ($logical in $selected) {
    $srcRel = Get-PhysicalPath $logical $srcSide
    $dstRel = Get-PhysicalPath $logical $dstSide
    $srcFile = Join-Path $srcRepo ($srcRel -replace '/', '\')
    $dstFile = Join-Path $dstRepo ($dstRel -replace '/', '\')

    if (-not (Test-Path $srcFile)) { continue }

    $dstDir = Split-Path $dstFile -Parent
    if ($PSCmdlet.ShouldProcess($dstFile, "Copy from $srcFile")) {
        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Copy-Item -LiteralPath $srcFile -Destination $dstFile -Force
        $copied++
    }
}

# ── Dual-variant files (D-18 follow-up) ──────────────────────────────────────
# Files at the repo ROOT (not under .github/) that exist on BOTH sides but whose
# CONTENT must diverge on a few lines (currently only aldc.yaml's toolkitRoot).
# Copy verbatim, then rewrite the matched line(s) to the DESTINATION side's value.
# Encoding (UTF-8, no BOM) and the destination's native EOL are preserved to avoid
# spurious diffs.
$dualCount = 0
foreach ($dv in @($manifest.dualVariant)) {
    if ([string]::IsNullOrWhiteSpace($dv.path)) { continue }

    $relWin = $dv.path -replace '/', '\'
    $dvSrc = Join-Path $srcRepo $relWin
    $dvDst = Join-Path $dstRepo $relWin
    if (-not (Test-Path $dvSrc)) {
        Write-Warning "dualVariant source not found, skipping: $($dv.path)"
        continue
    }

    $raw = [System.IO.File]::ReadAllText($dvSrc)
    $srcLines = $raw -split "`r?`n"

    # Preserve the destination's native EOL (push: fork LF; pull: project CRLF),
    # falling back to the source's EOL when the destination does not exist yet.
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    if (Test-Path $dvDst) {
        $dstRaw = [System.IO.File]::ReadAllText($dvDst)
        $nl = if ($dstRaw -match "`r`n") { "`r`n" } else { "`n" }
    }

    $lines = $srcLines
    foreach ($rw in @($dv.rewrites)) {
        $target = $rw.$dstSide
        if ([string]::IsNullOrEmpty($target)) { continue }
        $re = [regex] $rw.match
        $hit = $false
        $out = New-Object System.Collections.Generic.List[string]
        foreach ($line in $lines) {
            if (-not $hit -and $re.IsMatch($line)) { $out.Add($target); $hit = $true }
            else { $out.Add($line) }
        }
        $lines = $out.ToArray()
        if (-not $hit) {
            Write-Warning "dualVariant: no line matched /$($rw.match)/ in $($dv.path) — destination keeps source value."
        }
    }

    Write-Host "Dual-variant: $($dv.path)  (toolkitRoot -> $dstSide value)" -ForegroundColor Green
    if ($PSCmdlet.ShouldProcess($dvDst, "Write dual-variant from $dvSrc")) {
        $dstDir = Split-Path $dvDst -Parent
        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($dvDst, ($lines -join $nl), $utf8NoBom)
        $dualCount++
    }
}

Write-Host ""
if ($WhatIfPreference) {
    Write-Host "DRY-RUN complete — $($selected.Count) file(s) + $(@($manifest.dualVariant).Count) dual-variant would sync. No changes made." -ForegroundColor Yellow
}
else {
    Write-Host "Done — $copied file(s) copied + $dualCount dual-variant ($Direction)." -ForegroundColor Green
    if ($Direction -eq 'push') {
        Write-Host "Next: in the fork clone, review 'git status', commit, open a PR. The change is only adopted once merged into the fork (D-16)." -ForegroundColor Cyan
    }
}
