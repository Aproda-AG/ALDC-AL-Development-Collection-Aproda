#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a pull request in Azure DevOps after explicit human approval (single allowed mutation).
.DESCRIPTION
    Preconditions (outside this script): al-pr-prepare or the Conductor has cleared all
    delivery gates and shown the user title, description, source/target branch, and the
    work item link; the user has explicitly approved creating this PR.

    Allowlist: exactly two Azure CLI commands -- `az repos pr list` (read-only duplicate
    check, always runs first) and `az repos pr create` (the one allowed mutation, gated by
    -WhatIf/ShouldProcess). No other Azure CLI command is used.

    Multi-line description: passed as `--description @<DescriptionFile>`. az CLI's generic
    "@file" syntax reads the value straight from disk, so embedded newlines and quotes
    survive intact -- unlike a raw command-line string, which az.cmd re-parses through
    cmd.exe on Windows and can truncate or corrupt.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Organization,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Project,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Repository,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceBranch,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetBranch,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DescriptionFile,

    [Parameter(Mandatory)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$WorkItemId
)

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI ('az') was not found on PATH. Install it from https://learn.microsoft.com/cli/azure/install-azure-cli, then re-run."
    return
}

$extensions = az extension list --output json --only-show-errors 2>$null | ConvertFrom-Json
if (-not ($extensions | Where-Object { $_.name -eq 'azure-devops' })) {
    Write-Error "Azure CLI extension 'azure-devops' is not installed. Run: az extension add --name azure-devops"
    return
}

if (-not (Test-Path -LiteralPath $DescriptionFile -PathType Leaf)) {
    Write-Error "DescriptionFile '$DescriptionFile' was not found."
    return
}

$descriptionContent = Get-Content -LiteralPath $DescriptionFile -Raw
if ([string]::IsNullOrWhiteSpace($descriptionContent)) {
    Write-Error "DescriptionFile '$DescriptionFile' is empty."
    return
}
# az CLI's generic "@file" syntax reads the value straight from disk, so embedded newlines
# and " survive intact -- az.cmd's Windows command-line re-parsing never sees them.
$descriptionArg = "@$DescriptionFile"

if ($SourceBranch -eq $TargetBranch) {
    Write-Error "SourceBranch and TargetBranch must differ ('$SourceBranch')."
    return
}

$orgUrl = $Organization.TrimEnd('/')
$projectSegment = $Project -replace ' ', '%20'
$repositorySegment = $Repository -replace ' ', '%20'

# Duplicate check (read-only, always runs before the mutation).
$existingRaw = az repos pr list --repository $Repository --source-branch $SourceBranch --target-branch $TargetBranch --status active --organization $Organization --project $Project --output json --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to query existing pull requests for '$Repository' ($SourceBranch -> $TargetBranch); repository may be unreachable. No mutation performed."
    return
}

$existing = @()
if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
    $existing = @($existingRaw | ConvertFrom-Json)
}

if ($existing.Count -gt 0) {
    $first = $existing[0]
    [ordered]@{
        created = $false
        reason  = 'existing-open-pull-request'
        id      = $first.pullRequestId
        url     = "$orgUrl/$projectSegment/_git/$repositorySegment/pullrequest/$($first.pullRequestId)"
    } | ConvertTo-Json -Depth 5
    return
}

if ($PSCmdlet.ShouldProcess("$Repository ($SourceBranch -> $TargetBranch)", "Create pull request '$Title'")) {
    $titleSafe = $Title -replace '"', "'"
    $createdRaw = az repos pr create --repository $Repository --source-branch $SourceBranch --target-branch $TargetBranch --title $titleSafe --description $descriptionArg --work-items $WorkItemId --organization $Organization --project $Project --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($createdRaw)) {
        Write-Error "Failed to create the pull request. No fallback performed."
        return
    }

    $created = $createdRaw | ConvertFrom-Json
    [ordered]@{
        created = $true
        id      = $created.pullRequestId
        url     = "$orgUrl/$projectSegment/_git/$repositorySegment/pullrequest/$($created.pullRequestId)"
        status  = $created.status
    } | ConvertTo-Json -Depth 5
}
