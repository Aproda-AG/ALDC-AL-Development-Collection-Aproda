<#
.SYNOPSIS
    Aproda ALDC — one-shot bootstrap of a FRESH project repo from a fork clone.
    Zero-seed: nothing is copied by hand; the pull itself materializes the layer.

.DESCRIPTION
    Brings the Aproda ALDC layer into a repo that does NOT yet have it, in one run:

        1. PULL : borrow the engine FROM THE FORK (content-load) and run it with
                  -Direction pull against the target. This writes the whole layer
                  INTO the target's .github/, INCLUDING tools/aproda-sync/* — so the
                  engine never has to be seeded first (it can't pull itself before it
                  exists; we run the fork's copy instead).
        2. INIT : now the target carries Initialize-AprodaProject.ps1. Content-load
                  it FROM THE TARGET (so its .git-walk anchors on the target's root,
                  not the fork's) and run the one-time project bootstrap.

    The only required input is the TARGET repo root. The fork path is auto-derived
    from this script's own location (this script ships inside the fork). Override
    with -ForkPath if you keep the script elsewhere.

    SRP-safe: cmdlet-only, loaded content-based by the caller; it never path-executes
    or Import-Modules another script — it Get-Content's them and invokes a ScriptBlock.

.PARAMETER ProjectRoot
    Repo root of the TARGET project to initialize (the folder that will hold .github/).
    Must already be a git work tree (contain a .git) so the init step anchors cleanly
    — this script does NOT run `git init` for you (run it yourself first).

.PARAMETER ForkPath
    Local path to a clone of the aproda-aldc fork (the source). Optional: defaults to
    the git root walked up from this script's own location.

.PARAMETER WhatIf
    Dry-run the pull (prints the planned file set, changes nothing) and SKIP the init
    (there is nothing to initialize without a real pull).

.PARAMETER Force
    Overwrite an existing target Start-Pull.ps1 when materializing the recurring pull
    starter. Default: an existing (possibly customized) Start-Pull.ps1 is left untouched.

.EXAMPLE
    # SRP-safe invocation (content-load this script, then run):
    $env:APRODA_SYNC_SCRIPTDIR = 'C:\src\aproda-aldc\tools\aproda-sync'
    $src = Get-Content "$env:APRODA_SYNC_SCRIPTDIR\Bootstrap-AprodaProject.ps1" -Raw
    & ([ScriptBlock]::Create($src)) -ProjectRoot 'C:\src\MyNewRepo'

.EXAMPLE
    # Preview only — dry-run the pull, no writes, no init:
    & ([ScriptBlock]::Create($src)) -ProjectRoot 'C:\src\MyNewRepo' -WhatIf

.NOTES
    Decision: D-20 (decisions.aproda.md). Sibling of Sync-AprodaLayer.ps1 /
    Initialize-AprodaProject.ps1. Fork = source of truth; this is a fork-side tool.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ProjectRoot,

    [Parameter(Mandatory = $false)]
    [string] $ForkPath,

    [Parameter(Mandatory = $false)]
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

# ── Resolve this script's home (the fork's aproda-sync dir) ───────────────────
# Under SRP content-loading $PSScriptRoot is empty; fall back to the env var the
# caller sets when content-loading.
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $env:APRODA_SYNC_SCRIPTDIR
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Set `$env:APRODA_SYNC_SCRIPTDIR to the fork's tools/aproda-sync folder when loading content-based."
}

# ── Resolve the fork root (source) ───────────────────────────────────────────
# Default: walk up from this script until a .git entry is found — encoding-safe
# pure path ops (parsing `git rev-parse` stdout mangles non-ASCII paths under a
# non-UTF-8 console; see D-19).
if ([string]::IsNullOrWhiteSpace($ForkPath)) {
    $dir = Get-Item -LiteralPath $scriptDir
    while ($null -ne $dir) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName '.git')) { $ForkPath = $dir.FullName; break }
        $dir = $dir.Parent
    }
    if ([string]::IsNullOrWhiteSpace($ForkPath)) {
        throw "Could not auto-derive -ForkPath (no .git found above '$scriptDir'). Pass -ForkPath explicitly."
    }
}
$ForkPath = (Resolve-Path -LiteralPath $ForkPath).Path

# The engine lives at the fork ROOT (fork layout): <fork>/tools/aproda-sync/.
$forkSyncDir = Join-Path $ForkPath 'tools\aproda-sync'
$engineSource = Join-Path $forkSyncDir 'Sync-AprodaLayer.ps1'
$manifestSource = Join-Path $forkSyncDir 'aproda-sync.json'
if (-not (Test-Path $engineSource) -or -not (Test-Path $manifestSource)) {
    throw "Fork at '$ForkPath' does not look like an aproda-aldc fork (missing tools/aproda-sync/Sync-AprodaLayer.ps1 or aproda-sync.json)."
}

# ── Validate the target (no `git init` — warn + abort, per D-20) ──────────────
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "Target ProjectRoot does not exist: $ProjectRoot"
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
    throw "Target '$ProjectRoot' is not a git work tree (no .git at its root). Run 'git init' there first, then re-run — this bootstrap does not init git for you (clean anchor required for the init step)."
}

Write-Host "Bootstrap: fork    = $ForkPath"
Write-Host "Bootstrap: target  = $ProjectRoot"

# ── 1) PULL — run the fork's engine against the target ────────────────────────
# Point the engine at the FORK's manifest (its scriptDir) and pass the target as
# the explicit destination. The pull writes the full layer into the target,
# including tools/aproda-sync/* (Sync, Initialize, manifest, templates).
$env:APRODA_SYNC_SCRIPTDIR = $forkSyncDir
$engineSrc = Get-Content -LiteralPath $engineSource -Raw
$engineBlock = [ScriptBlock]::Create($engineSrc)
if ($WhatIfPreference) {
    & $engineBlock -Direction pull -ForkPath $ForkPath -ProjectRoot $ProjectRoot -WhatIf
    Write-Host "Bootstrap: -WhatIf set — pull was a dry-run, INIT skipped (nothing materialized)."
    return
}
& $engineBlock -Direction pull -ForkPath $ForkPath -ProjectRoot $ProjectRoot

# Framework settle pull. The engine reads the DESTINATION's aldc.yaml to know which
# ALDC framework files to bring, but aldc.yaml is itself written (dual-variant) at the
# END of the same pull. So on a FRESH repo the first pull cannot include the framework
# (no aldc.yaml existed when the file set was resolved) — only the self-identifying
# .aproda. layer + tools arrive. A single extra pull, now that aldc.yaml is present,
# settles the framework (skills/prompts/agents/docs templates incl. memory-template).
# Overlay is idempotent, so this is safe and one-time (onboarding only).
if (Test-Path -LiteralPath (Join-Path $ProjectRoot 'aldc.yaml')) {
    Write-Host "Bootstrap: settle pull (framework now resolvable via the freshly-written aldc.yaml)..."
    & $engineBlock -Direction pull -ForkPath $ForkPath -ProjectRoot $ProjectRoot
}

# ── 2) INIT — run the target's freshly-pulled init from the target ────────────
# Anchor must be the TARGET's .git, so load Initialize FROM THE TARGET copy and
# point the env var at the target's aproda-sync dir (the init has no -ProjectRoot;
# it resolves via .git-walk from APRODA_SYNC_SCRIPTDIR).
$targetSyncDir = Join-Path $ProjectRoot '.github\tools\aproda-sync'
$initTarget = Join-Path $targetSyncDir 'Initialize-AprodaProject.ps1'
if (-not (Test-Path $initTarget)) {
    throw "Pull completed but '$initTarget' is missing — cannot run init. Check the manifest includeFiles."
}
$env:APRODA_SYNC_SCRIPTDIR = $targetSyncDir
$initSrc = Get-Content -LiteralPath $initTarget -Raw
& ([ScriptBlock]::Create($initSrc))

# ── 3) Materialize the recurring Start-Pull.ps1 in the target (filled-in) ──────
# The pull brought in Start-Pull.ps1.template; inject ONLY the fork path (the one
# value that cannot be self-located — a separate repo). APRODA_SYNC_SCRIPTDIR is
# deliberately left empty so the generated starter self-locates it at run time
# (the file sits in the target's .github/tools/aproda-sync). Result: a zero-config
# Start-Pull (fork correct-by-construction, scriptdir self-located). Machine-local
# + git-ignored (the init step's .gitignore block covers it). Idempotent: an
# existing Start-Pull.ps1 is left untouched unless -Force (it may carry user edits).
$startPullTemplate = Join-Path $targetSyncDir 'Start-Pull.ps1.template'
$startPullFile = Join-Path $targetSyncDir 'Start-Pull.ps1'
if (-not (Test-Path $startPullTemplate)) {
    Write-Warning "Start-Pull.ps1.template missing in target — skipping starter generation."
}
elseif ((Test-Path $startPullFile) -and -not $Force) {
    Write-Host "Bootstrap: Start-Pull.ps1 already exists — left untouched (use -Force to regenerate)."
}
else {
    $fp = $ForkPath.Replace("'", "''")
    $filled = foreach ($line in (Get-Content -LiteralPath $startPullTemplate)) {
        if ($line -match '^\s*\$env:APRODA_FORK_PATH\s*=') { "`$env:APRODA_FORK_PATH = '$fp'" }
        else { $line }
    }
    Set-Content -LiteralPath $startPullFile -Value $filled -Encoding UTF8
    Write-Host "Bootstrap: Start-Pull.ps1 generated (fork path filled, scriptdir self-located) for future pulls."
}

Write-Host "Bootstrap: done. The repo is ready — initial pull + init performed, and Start-Pull.ps1 is in place for future pulls."
