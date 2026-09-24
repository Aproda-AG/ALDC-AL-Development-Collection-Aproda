#Requires -Version 5.1
<#
.SYNOPSIS
    Preflight check for the az-CLI fallback path: is `az` on PATH, is the `azure-devops` extension
    installed, and is the login session usable?
.DESCRIPTION
    Consolidates the preflight block that used to be duplicated verbatim across 4 separate scripts.
    Returns $true if the az-CLI fallback is usable, otherwise writes a specific error and returns $false --
    callers (agent or Invoke-AdoAzCli) decide what to do next (e.g. fall back further, or ask the user to
    run the "Set up Azure CLI for ADO integration" walkthrough step).
#>
[CmdletBinding()]
param()

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI ('az') was not found on PATH. Install it from https://learn.microsoft.com/cli/azure/install-azure-cli, then re-run."
    return $false
}

$extensionsRaw = az extension list --output json --only-show-errors 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "az itself failed while listing extensions (exit $LASTEXITCODE): $extensionsRaw. az may need a fresh login -- try 'az logout' then 'az login --tenant 8ad57af3-4ca5-4c66-bc7d-a52dd71dc7c9 --subscription bdcf3613-1ee6-4c3c-9caf-962112b8a6aa'."
    return $false
}

$extensions = $extensionsRaw | ConvertFrom-Json
if (-not ($extensions | Where-Object { $_.name -eq 'azure-devops' })) {
    Write-Error "Azure CLI extension 'azure-devops' is not installed. Run: az extension add --name azure-devops"
    return $false
}

$true
