<#
.SYNOPSIS
  Thin entry point for the Aproda Deploy-Run-Verify Cycle. IMMUTABLE — do not edit per project.
.DESCRIPTION
  Imports the engine module and runs the full Build -> Deploy -> Run loop against
  the config. Designed to be invoked via:  Get-Content <this> -Raw | Invoke-Expression
.PARAMETER (env)
  APRODA_DEPLOY_RUN_VERIFY_CONFIG  Path to the project's deploy-run-verify.config.jsonc (required).
  APRODA_DEPLOY_RUN_VERIFY_MODULE  Path to AprodaDeployRunVerify.psm1 (required when dot-loaded via iex,
                          because $PSCommandPath is empty in that case).
  APRODA_DEPLOY_RUN_VERIFY_MODE    'full' (default) | 'buildonly' | 'skipbuild'
.EXAMPLE
  $env:APRODA_DEPLOY_RUN_VERIFY_CONFIG = 'C:\proj\Test\deploy-run-verify.config.jsonc'
  $env:APRODA_DEPLOY_RUN_VERIFY_MODULE = '<skill>\scripts\AprodaDeployRunVerify.psm1'
  Get-Content '<skill>\scripts\Invoke-AprodaDeployRunVerify.ps1' -Raw | Invoke-Expression
#>
$ErrorActionPreference = 'Stop'

$cfgPath = $env:APRODA_DEPLOY_RUN_VERIFY_CONFIG
if ([string]::IsNullOrWhiteSpace($cfgPath)) { throw "Set `$env:APRODA_DEPLOY_RUN_VERIFY_CONFIG to the deploy-run-verify.config.jsonc path before running." }

# Resolve the engine module path. When dot-loaded via iex, $PSCommandPath is empty,
# so the env hint takes precedence; otherwise derive it next to this script.
$modulePath = $env:APRODA_DEPLOY_RUN_VERIFY_MODULE
if ([string]::IsNullOrWhiteSpace($modulePath) -and $PSCommandPath) {
    $modulePath = Join-Path (Split-Path -Parent $PSCommandPath) 'AprodaDeployRunVerify.psm1'
}
if ([string]::IsNullOrWhiteSpace($modulePath) -or -not (Test-Path $modulePath)) {
    throw "Engine module not found. Set `$env:APRODA_DEPLOY_RUN_VERIFY_MODULE to the AprodaDeployRunVerify.psm1 path."
}

# Load the engine WITHOUT Import-Module: some machines block .psm1 import via Software
# Restriction Policy / Group Policy. Dot-sourcing the content (minus Export-ModuleMember)
# defines the functions in this scope and is SRP-safe.
$engineSrc = Get-Content $modulePath -Raw
$engineSrc = [regex]::Replace($engineSrc, '(?s)Export-ModuleMember.*$', '')
. ([ScriptBlock]::Create($engineSrc))

switch ($env:APRODA_DEPLOY_RUN_VERIFY_MODE) {
    'buildonly' { Invoke-AprodaDeployRunVerify -ConfigPath $cfgPath -BuildOnly }
    'skipbuild' { Invoke-AprodaDeployRunVerify -ConfigPath $cfgPath -SkipBuild }
    default     { Invoke-AprodaDeployRunVerify -ConfigPath $cfgPath }
}
