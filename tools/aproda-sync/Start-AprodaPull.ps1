<#
.SYNOPSIS
    One-liner entry point: PULL the Aproda ALDC layer FROM the fork INTO this repo.

.DESCRIPTION
    Thin, SRP-safe wrapper around Sync-AprodaLayer.ps1 (-Direction pull). It loads
    the engine CONTENT-BASED (no path-based dot-sourcing, so it works under the
    Group-Policy SRP that blocks path-based execution) and passes through -WhatIf.

    The fork clone location is resolved (in order):
      1) -ForkPath argument
      2) $env:APRODA_FORK_PATH
    Nothing machine-specific is hard-coded in this layer file.

.PARAMETER ForkPath
    Local path to a clone of the aproda-aldc fork. Falls back to $env:APRODA_FORK_PATH.

.PARAMETER WhatIf
    Dry-run: print the resolved file set and planned copies, change nothing.

.EXAMPLE
    # Because SRP blocks path-based execution, start it content-based:
    Get-Content .\Start-AprodaPull.ps1 -Raw | Invoke-Expression

.EXAMPLE
    # Or, when path-based execution is allowed:
    .\Start-AprodaPull.ps1 -ForkPath C:\src\aproda-aldc -WhatIf

.NOTES
    Decision: D-18. Engine: Sync-AprodaLayer.ps1. Manifest: aproda-sync.json.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string] $ForkPath
)

$ErrorActionPreference = 'Stop'

# Resolve this script's directory (SRP content-loading may leave $PSScriptRoot empty).
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $env:APRODA_SYNC_SCRIPTDIR }
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Set `$env:APRODA_SYNC_SCRIPTDIR to the aproda-sync folder before loading content-based."
}
$env:APRODA_SYNC_SCRIPTDIR = $scriptDir

if ([string]::IsNullOrWhiteSpace($ForkPath)) { $ForkPath = $env:APRODA_FORK_PATH }
if ([string]::IsNullOrWhiteSpace($ForkPath)) {
    throw "ForkPath not given. Pass -ForkPath <clone> or set `$env:APRODA_FORK_PATH."
}

$engine = Join-Path $scriptDir 'Sync-AprodaLayer.ps1'
if (-not (Test-Path $engine)) { throw "Engine not found: $engine" }

# Load the engine content-based and invoke it (passes -WhatIf through via $WhatIfPreference).
& ([ScriptBlock]::Create((Get-Content $engine -Raw))) -Direction pull -ForkPath $ForkPath -WhatIf:$WhatIfPreference
