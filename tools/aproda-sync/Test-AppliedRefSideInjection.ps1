<#
.SYNOPSIS
    Regression test for the aldc.yaml `sideInjections`/`appliedRef` mechanism in
    Sync-AprodaLayer.ps1 (aproda-sync.json -> dualVariant[0].sideInjections).

.DESCRIPTION
    Runs the REAL Sync-AprodaLayer.ps1 (content-loaded, SRP-safe) against real
    scratch git repositories standing in for the fork and a project, and asserts
    on the resulting aldc.yaml identity — not merely "a field exists".

    Covered, each against the actual script (no duplicated injection logic):
      1. The written `appliedRef` value equals `git -C <fork> rev-parse HEAD`
         exactly, and is inserted immediately after the `layerVersion:` line.
      2. `appliedRef` is project-side only: pushing (project -> fork) strips it
         from the fork's copy even though the project side carried a value.
      3. Idempotent across two consecutive pulls with the fork unchanged.
      4. A second pull after a new fork commit updates the value in place
         (still exactly one line, same position).
      5. A fork with NO resolvable HEAD (freshly `git init`'d, zero commits)
         does not fabricate a value — the field ends up ABSENT. NOTE: this is
         empirically different from the script's own Write-Warning text
         ("... leaving field as-is"): the destination aldc.yaml is regenerated
         wholesale from source content each run (see Sync-AprodaLayer.ps1's
         dualVariant loop), so a PRE-EXISTING destination value is actually
         LOST, not preserved, when the source HEAD cannot be resolved. This
         test asserts the real (measured) behaviour, and the misleading
         wording is reported separately — it is not fixed here.
      6. The exact commit-id shape guard used inside that same branch
         (`^[0-9a-f]{7,64}$`, the regex the splice value is checked against
         before being written into unquoted-by-template YAML) accepts real
         SHA-1/SHA-256 shapes and rejects anything else, extracted verbatim
         from the real script text and exercised against a case table — NOT
         a full end-to-end pull. A PATH-based `git` shim (`.cmd` in a
         prepended directory) was tried first to reproduce this end-to-end,
         but is blocked here by Software Restriction Policy/Group Policy
         (confirmed: the shim itself refuses to execute, "Dieses Programm
         wurde durch eine Gruppenrichtlinie geblockt"), so this one case is
         intentionally narrower than the others — an honest compromise, not
         a silently weakened assertion.

    SRP-safe: Sync-AprodaLayer.ps1 is invoked exactly like the extension's own
    bridge — content-loaded via Get-Content -Raw + ScriptBlock::Create — never
    path-based dot-sourcing / Import-Module.

.NOTES
    Decision: D-18, D-50 (decisions.aproda.md). Manifest: aproda-sync.json
    (dualVariant[0].sideInjections). Style modelled on Test-InPlaceEditsRegister.ps1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $env:APRODA_SYNC_SCRIPTDIR
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Pass it via `$env:APRODA_SYNC_SCRIPTDIR when loading content-based."
}

$syncScriptPath = Join-Path $scriptDir 'Sync-AprodaLayer.ps1'
if (-not (Test-Path -LiteralPath $syncScriptPath)) {
    throw "Sync-AprodaLayer.ps1 not found next to this test: $syncScriptPath"
}
$syncScriptContent = Get-Content -LiteralPath $syncScriptPath -Raw

$results = New-Object System.Collections.Generic.List[pscustomobject]
function Add-Result([string] $Name, [bool] $Pass, [string] $Detail) {
    $results.Add([pscustomobject]@{ Test = $Name; Pass = $Pass; Detail = $Detail })
}

# Invoke the REAL script exactly like the extension bridge does: content-based,
# never path-based. Runs in-process (dot-sourced) so $LASTEXITCODE / thrown errors
# surface normally; Sync-AprodaLayer.ps1 does not itself call `exit`.
function Invoke-Sync {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('pull', 'push')][string] $Direction,
        [Parameter(Mandatory = $true)][string] $ForkPath,
        [Parameter(Mandatory = $true)][string] $ProjectRoot
    )
    $prevScriptDir = $env:APRODA_SYNC_SCRIPTDIR
    $env:APRODA_SYNC_SCRIPTDIR = $scriptDir
    try {
        & ([ScriptBlock]::Create($syncScriptContent)) -Direction $Direction -ForkPath $ForkPath -ProjectRoot $ProjectRoot *> $null
    }
    finally {
        $env:APRODA_SYNC_SCRIPTDIR = $prevScriptDir
    }
}

# Resolve to the CANONICAL long-form path immediately after creation. Get-ChildItem
# (used inside Sync-AprodaLayer.ps1 to enumerate the source tree) silently expands
# 8.3 short-name segments (e.g. a short-form %TEMP%) to their long form, which then
# desyncs the Substring-based logical-path computation against a short-form $ForkPath/
# $ProjectRoot argument -- confirmed empirically before writing this test.
function New-ScratchDir([string] $path) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return (Get-Item -LiteralPath $path).FullName
}

function New-ForkFixture([string] $root, [string] $layerVersion = '1.0.0_aproda.1') {
    $root = New-ScratchDir $root
    & git init --quiet $root
    Set-Content -LiteralPath (Join-Path $root 'aldc.yaml') -Value @(
        'toolkitRoot: "."',
        'aproda:',
        "  layerVersion: `"$layerVersion`""
    )
    # A single includeGlobs-matched file, otherwise $selected.Count -eq 0 and the
    # whole script `return`s before ever reaching the dualVariant/appliedRef loop.
    Set-Content -LiteralPath (Join-Path $root 'scratchfixture.aproda.md') -Value 'scratch fixture'
    Push-Location $root
    try {
        & git add -A | Out-Null
        & git -c user.email=test@example.com -c user.name=Test commit --quiet -m seed | Out-Null
    }
    finally { Pop-Location }
    return $root
}

function New-ProjectFixture([string] $root, [string] $layerVersion = '0.9.0_aproda.1', [switch] $WithMatchedFile) {
    $root = New-ScratchDir $root
    New-Item -ItemType Directory -Path (Join-Path $root '.github') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root '.github/aldc.yaml') -Value @(
        'toolkitRoot: ".github"',
        'aproda:',
        "  layerVersion: `"$layerVersion`""
    )
    if ($WithMatchedFile) {
        Set-Content -LiteralPath (Join-Path $root '.github/scratchfixture.aproda.md') -Value 'scratch fixture'
    }
    return $root
}

function Get-AldcYamlLines([string] $path) {
    return @(Get-Content -LiteralPath $path)
}

function Get-AppliedRefValue([string[]] $lines) {
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '^\s*appliedRef:\s*"([^"]*)"\s*(#.*)?$')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return $null
}

function Get-LayerVersionLineIndex([string[]] $lines) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*layerVersion:\s*".*"\s*(#.*)?$') { return $i }
    }
    return -1
}

$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("aldc-appliedref-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
$workRoot = (Get-Item -LiteralPath $workRoot).FullName

try {
    # ── 1 + partial-4: insertion is deterministic (immediately after layerVersion) ──
    $fork1 = New-ForkFixture (Join-Path $workRoot 'fork1')
    $forkHead1 = (& git -C $fork1 rev-parse HEAD).Trim()
    $proj1 = New-ProjectFixture (Join-Path $workRoot 'proj1')

    Invoke-Sync -Direction pull -ForkPath $fork1 -ProjectRoot $proj1
    $lines1 = Get-AldcYamlLines (Join-Path $proj1 '.github/aldc.yaml')
    $appliedRef1 = Get-AppliedRefValue $lines1
    $lvIndex1 = Get-LayerVersionLineIndex $lines1
    $arIndex1 = [array]::IndexOf($lines1, ($lines1 | Where-Object { $_ -match '^\s*appliedRef:' }))

    Add-Result 'appliedRef equals fork HEAD exactly (first pull)' ($appliedRef1 -eq $forkHead1) "expected=$forkHead1 actual=$appliedRef1"
    Add-Result 'appliedRef inserted immediately after layerVersion (deterministic position)' ($arIndex1 -eq ($lvIndex1 + 1)) "layerVersionIndex=$lvIndex1 appliedRefIndex=$arIndex1"

    # ── 3: idempotent across two consecutive pulls, fork unchanged ─────────────────
    $before = Get-Content -LiteralPath (Join-Path $proj1 '.github/aldc.yaml') -Raw
    Invoke-Sync -Direction pull -ForkPath $fork1 -ProjectRoot $proj1
    $after = Get-Content -LiteralPath (Join-Path $proj1 '.github/aldc.yaml') -Raw
    $linesAfter = Get-AldcYamlLines (Join-Path $proj1 '.github/aldc.yaml')
    $appliedRefLineCount = @($linesAfter | Where-Object { $_ -match '^\s*appliedRef:' }).Count

    Add-Result 'idempotent: byte-identical content across two consecutive pulls (fork unchanged)' ($before -eq $after) "unchanged=$($before -eq $after)"
    Add-Result 'idempotent: exactly one appliedRef line after a second pull (not duplicated)' ($appliedRefLineCount -eq 1) "lineCount=$appliedRefLineCount"

    # ── 4: a NEW fork commit updates the value in place on the next pull ───────────
    Set-Content -LiteralPath (Join-Path $fork1 'scratchfixture.aproda.md') -Value 'scratch fixture v2'
    Push-Location $fork1
    try {
        & git add -A | Out-Null
        & git -c user.email=test@example.com -c user.name=Test commit --quiet -m second | Out-Null
    }
    finally { Pop-Location }
    $forkHead2 = (& git -C $fork1 rev-parse HEAD).Trim()

    Invoke-Sync -Direction pull -ForkPath $fork1 -ProjectRoot $proj1
    $lines2 = Get-AldcYamlLines (Join-Path $proj1 '.github/aldc.yaml')
    $appliedRef2 = Get-AppliedRefValue $lines2
    $appliedRefLineCount2 = @($lines2 | Where-Object { $_ -match '^\s*appliedRef:' }).Count

    Add-Result 'appliedRef updates to the new fork HEAD on a later pull' (($appliedRef2 -eq $forkHead2) -and ($forkHead2 -ne $forkHead1)) "expected=$forkHead2 actual=$appliedRef2 (previous was $forkHead1)"
    Add-Result 'still exactly one appliedRef line after the update (updated in place, not appended)' ($appliedRefLineCount2 -eq 1) "lineCount=$appliedRefLineCount2"

    # ── 2: project-side only -- stripped when pushing project -> fork ──────────────
    $projPush = New-ProjectFixture (Join-Path $workRoot 'proj-push') '1.0.0_aproda.1' -WithMatchedFile
    # Seed an appliedRef into the project side directly (as if a prior pull had run).
    $projPushLines = Get-AldcYamlLines (Join-Path $projPush '.github/aldc.yaml')
    $projPushLines = $projPushLines[0..0] + '  appliedRef: "abc1234"' + $projPushLines[1..($projPushLines.Count - 1)]
    Set-Content -LiteralPath (Join-Path $projPush '.github/aldc.yaml') -Value $projPushLines
    $forkPushDst = New-ScratchDir (Join-Path $workRoot 'fork-push-dst')

    Invoke-Sync -Direction push -ForkPath $forkPushDst -ProjectRoot $projPush
    $forkPushLines = Get-AldcYamlLines (Join-Path $forkPushDst 'aldc.yaml')
    $forkPushAppliedRef = Get-AppliedRefValue $forkPushLines
    $forkPushToolkitRoot = ($forkPushLines | Where-Object { $_ -match '^\s*toolkitRoot:' }) -join ''

    Add-Result 'appliedRef is stripped on push (project -> fork), even though the project side had a value' ($null -eq $forkPushAppliedRef) "forkAppliedRef=$forkPushAppliedRef"
    Add-Result 'push still rewrites toolkitRoot to the fork value' ($forkPushToolkitRoot -match '^\s*toolkitRoot:\s*"\."\s*$') "line=$forkPushToolkitRoot"

    # ── 5: no resolvable source HEAD (freshly git-init'd, zero commits) ────────────
    $forkNoHead = New-ScratchDir (Join-Path $workRoot 'fork-no-head')
    & git init --quiet $forkNoHead
    Set-Content -LiteralPath (Join-Path $forkNoHead 'aldc.yaml') -Value @('toolkitRoot: "."', 'aproda:', '  layerVersion: "1.0.0_aproda.1"')
    Set-Content -LiteralPath (Join-Path $forkNoHead 'scratchfixture.aproda.md') -Value 'x'
    # No `git add`/`git commit` at all -> HEAD is unborn -> `git rev-parse HEAD` fails.
    $projNoHead = New-ProjectFixture (Join-Path $workRoot 'proj-no-head')
    $projNoHeadLines = Get-AldcYamlLines (Join-Path $projNoHead '.github/aldc.yaml')
    $projNoHeadLines = $projNoHeadLines[0..0] + '  appliedRef: "abc1234"' + $projNoHeadLines[1..($projNoHeadLines.Count - 1)]
    Set-Content -LiteralPath (Join-Path $projNoHead '.github/aldc.yaml') -Value $projNoHeadLines

    Invoke-Sync -Direction pull -ForkPath $forkNoHead -ProjectRoot $projNoHead
    $noHeadResultLines = Get-AldcYamlLines (Join-Path $projNoHead '.github/aldc.yaml')
    $noHeadAppliedRef = Get-AppliedRefValue $noHeadResultLines

    Add-Result 'no resolvable source HEAD: no fabricated/garbage appliedRef value is written' ($null -eq $noHeadAppliedRef -or $noHeadAppliedRef -match '^[0-9a-f]{7,64}$') "actual=$noHeadAppliedRef"
    # This is the measured (not assumed) behaviour: see the .DESCRIPTION note above.
    Add-Result 'no resolvable source HEAD: destination is regenerated from source (pre-existing project value does NOT survive)' ($null -eq $noHeadAppliedRef) "actual=$noHeadAppliedRef (pre-existing was abc1234)"

    # ── 6: the commit-id shape guard, extracted verbatim, against a case table ─────
    # A full end-to-end repro (a `git` shim on PATH returning a bogus HEAD value) was
    # tried and rejected here: SRP/Group Policy blocks executing a script from a
    # prepended PATH directory in this environment, so the shim never actually runs
    # and scenario 5/6 would silently collapse into the same code path without this
    # narrower, still-real-source, unit-level check.
    $shapeGuardMatch = [regex]::Match($syncScriptContent, "value -notmatch '([^']+)'")
    if (-not $shapeGuardMatch.Success) {
        throw "Could not extract the commit-id shape guard regex from Sync-AprodaLayer.ps1 — has the code moved?"
    }
    $shapeGuard = [regex] $shapeGuardMatch.Groups[1].Value
    $shapeCases = @(
        @('7c40e4b', $true, '7-char short SHA (minimum accepted length)'),
        @('7c40e4bbba881431f74475c665709e3c30c86b9', $true, '40-char full SHA-1'),
        @('not-a-commit-id', $false, 'a non-hex sentinel string must be rejected'),
        @('abc123', $false, 'exactly 6 hex chars (one below the 7-char minimum) must be rejected'),
        @('7C40E4B', $false, 'uppercase hex is rejected (real git HEAD output is always lowercase)')
    )
    $shapeFailures = @($shapeCases | Where-Object { $shapeGuard.IsMatch($_[0]) -ne $_[1] })
    Add-Result 'commit-id shape guard (^[0-9a-f]{7,64}$, extracted verbatim) matches the case table' ($shapeFailures.Count -eq 0) "failures=$($shapeFailures.Count) of $($shapeCases.Count)"
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$results | Format-Table Test, Pass, Detail -AutoSize -Wrap

$failures = @($results | Where-Object { -not $_.Pass })
if ($failures.Count -gt 0) {
    Write-Warning "$($failures.Count) of $($results.Count) appliedRef sideInjection case(s) FAILED."
    exit 1
}
Write-Host "All $($results.Count) appliedRef sideInjection case(s) passed." -ForegroundColor Green
exit 0
