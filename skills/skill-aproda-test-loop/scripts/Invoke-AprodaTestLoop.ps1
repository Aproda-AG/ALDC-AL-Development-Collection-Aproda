<#
.SYNOPSIS
  Thin entry point for the Aproda Test-Loop. IMMUTABLE — do not edit per project.
.DESCRIPTION
  Imports the engine module and runs the full Build -> Deploy -> Run loop against
  the config. Designed to be invoked via:  Get-Content <this> -Raw | Invoke-Expression
.PARAMETER (env)
  APRODA_TESTLOOP_CONFIG  Path to the project's testloop.config.jsonc (required).
  APRODA_TESTLOOP_MODULE  Path to AprodaTestLoop.psm1 (required when dot-loaded via iex,
                          because $PSCommandPath is empty in that case).
  APRODA_TESTLOOP_MODE    'full' (default) | 'buildonly' | 'skipbuild'
.EXAMPLE
  $env:APRODA_TESTLOOP_CONFIG = 'C:\proj\Test\testloop.config.jsonc'
  $env:APRODA_TESTLOOP_MODULE = '<skill>\scripts\AprodaTestLoop.psm1'
  Get-Content '<skill>\scripts\Invoke-AprodaTestLoop.ps1' -Raw | Invoke-Expression
#>
$ErrorActionPreference = 'Stop'

$cfgPath = $env:APRODA_TESTLOOP_CONFIG
if ([string]::IsNullOrWhiteSpace($cfgPath)) { throw "Set `$env:APRODA_TESTLOOP_CONFIG to the testloop.config.jsonc path before running." }

# Resolve the engine module path. When dot-loaded via iex, $PSCommandPath is empty,
# so the env hint takes precedence; otherwise derive it next to this script.
$modulePath = $env:APRODA_TESTLOOP_MODULE
if ([string]::IsNullOrWhiteSpace($modulePath) -and $PSCommandPath) {
    $modulePath = Join-Path (Split-Path -Parent $PSCommandPath) 'AprodaTestLoop.psm1'
}
if ([string]::IsNullOrWhiteSpace($modulePath) -or -not (Test-Path $modulePath)) {
    throw "Engine module not found. Set `$env:APRODA_TESTLOOP_MODULE to the AprodaTestLoop.psm1 path."
}

# Load the engine WITHOUT Import-Module: some machines block .psm1 import via Software
# Restriction Policy / Group Policy. Dot-sourcing the content (minus Export-ModuleMember)
# defines the functions in this scope and is SRP-safe.
$engineSrc = Get-Content $modulePath -Raw
$engineSrc = [regex]::Replace($engineSrc, '(?s)Export-ModuleMember.*$', '')
. ([ScriptBlock]::Create($engineSrc))

switch ($env:APRODA_TESTLOOP_MODE) {
    'buildonly' { Invoke-AprodaTestLoop -ConfigPath $cfgPath -BuildOnly }
    'skipbuild' { Invoke-AprodaTestLoop -ConfigPath $cfgPath -SkipBuild }
    default     { Invoke-AprodaTestLoop -ConfigPath $cfgPath }
}
