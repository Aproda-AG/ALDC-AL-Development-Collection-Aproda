<#
.SYNOPSIS
    Case-table regression test for Sync-AprodaLayer.ps1's Convert-GlobToRegex.

.DESCRIPTION
    Extracts the ACTUAL `Convert-GlobToRegex` function body from Sync-AprodaLayer.ps1
    at run time (via a regex slice of the real script text, then a content-based
    `ScriptBlock::Create`) and exercises it against a case table shared in spirit
    with tools/aldc-validate/test/globToRegex.case-table.test.js (same cases, two
    runtimes — PowerShell has no require(), so the case table is re-listed here
    rather than shared as a single data file; the FUNCTION UNDER TEST is not
    duplicated, only the cases are).

    This guards the historical glob bug (B-36/B-37/B-12): a leading '**/' must
    match root-level paths (no directory segment at all), and a bare '*' must
    never cross a '/'.

    SRP-safe: no path-based dot-sourcing / Import-Module of Sync-AprodaLayer.ps1 —
    only Get-Content (reading is always allowed) followed by a content-based
    ScriptBlock, exactly like the extension's own bridge invocation.

.NOTES
    Decision: D-18 (decisions.aproda.md). E-006 (test coverage for the "**/'-bug").
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

function Get-ConvertGlobToRegexSource([string] $path) {
    $raw = Get-Content -LiteralPath $path -Raw
    # Single-level function body (no nested '{'), so a non-greedy match up to the
    # first line that is just '}' at column 0 is exact and does not require
    # brace-balancing.
    $m = [regex]::Match($raw, '(?ms)^function Convert-GlobToRegex\(\[string\] \$glob\) \{.*?^\}')
    if (-not $m.Success) {
        throw "Could not extract Convert-GlobToRegex from $path — has the function's shape changed?"
    }
    return $m.Value
}

# Case table: [glob, path, expectedMatch, description]
$cases = @(
    @('**/*.aproda.*', 'readme.aproda.md', $true, 'root-level file matches a leading **/ glob (B-36/B-37/B-12)'),
    @('**/*.aproda.*', 'a/b/readme.aproda.md', $true, 'nested file matches a leading **/ glob'),
    @('**/*.aproda.*', 'readme.md', $false, 'file without the .aproda. infix must not match'),
    @('*.md', 'readme.md', $true, 'bare * matches a root-level filename'),
    @('*.md', 'a/readme.md', $false, 'bare * must not cross a / into a parent directory'),
    @('skills/skill-aproda-*/**', 'skills/skill-aproda-foo', $true, 'trailing /** matches the folder itself (zero-deep)'),
    @('skills/skill-aproda-*/**', 'skills/skill-aproda-foo/bar/baz.md', $true, 'trailing /** matches nested content'),
    @('skills/skill-aproda-*/**', 'skills/skill-other/bar.md', $false, 'a differently named skill folder must not match'),
    @('tools/aproda-ps-xliffsync/**', 'tools/aproda-ps-xliffsync/README.md', $true, 'named tool folder, nested file'),
    @('tools/aproda-ps-xliffsync/**', 'tools/aproda-ps-xliffsync', $true, 'named tool folder, the folder itself')
)

function Invoke-CaseTable([scriptblock] $convertGlobToRegexDefinition) {
    . $convertGlobToRegexDefinition
    $results = New-Object System.Collections.Generic.List[pscustomobject]
    foreach ($case in $cases) {
        $glob, $path, $expected, $description = $case
        $regex = Convert-GlobToRegex $glob
        $actual = [bool]([regex]::IsMatch($path, $regex))
        $results.Add([pscustomobject]@{
                Glob        = $glob
                Path        = $path
                Expected    = $expected
                Actual      = $actual
                Pass        = ($actual -eq $expected)
                Description = $description
            })
    }
    return $results
}

$source = Get-ConvertGlobToRegexSource $syncScriptPath
$results = Invoke-CaseTable ([ScriptBlock]::Create($source))

$results | Format-Table Glob, Path, Expected, Actual, Pass, Description -AutoSize -Wrap

$failures = @($results | Where-Object { -not $_.Pass })
if ($failures.Count -gt 0) {
    Write-Warning "$($failures.Count) of $($results.Count) Convert-GlobToRegex case(s) FAILED."
    exit 1
}
Write-Host "All $($results.Count) Convert-GlobToRegex case(s) passed." -ForegroundColor Green
exit 0
