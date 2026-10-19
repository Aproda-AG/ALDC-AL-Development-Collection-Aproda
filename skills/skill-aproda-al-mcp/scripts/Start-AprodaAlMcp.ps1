<#
.SYNOPSIS
  Starter for the AL MCP server (altool launchmcpserver): resolves the AL target, injects the
  per-process environment, then hands over to altool. Spec: E-010.spec.md §3.3.
.NOTES
  Stdout is the JSON-RPC channel (C-4): nothing may reach stdout before altool takes over.
  Diagnostics go to stderr only, as "[al-mcp-starter] <LEVEL> <CODE> <text>".
  Load content-based (SRP-safe), pwsh 7:
    & ([ScriptBlock]::Create((Get-Content -LiteralPath <path> -Raw))) -RepositoryRoot <r> -SkillRoot <s>
  Exit: 0 ok/dry run, 3 altool problem, 4 no AL project, 5 pwsh < 7, 6 library load failed,
  1 unexpected error, else passed through from altool. No pwsh-7-only syntax here: pwsh 5.1 must reach exit 5.
#>
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$SkillRoot,
    [string]$AlExtensionPath,
    [string]$AlExtensionVersion,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function Write-AlMcpStarterLog {
    param([string]$Level, [string]$Code, [string]$Text)
    [Console]::Error.WriteLine("[al-mcp-starter] $Level $Code $Text")
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-AlMcpStarterLog 'ERROR' 'PWSH_TOO_OLD' "PowerShell 7 is required, found $($PSVersionTable.PSVersion)"
    exit 5
}

try {
    $RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $SkillRoot = [System.IO.Path]::GetFullPath($SkillRoot)

    # 2. Libraries (content-based, SRP-safe)
    try {
        $libraryPath = [System.IO.Path]::GetFullPath((Join-Path $SkillRoot 'scripts\AprodaAlTarget.ps1'))
        $storePath = [System.IO.Path]::GetFullPath((Join-Path $SkillRoot '..\skill-aproda-fkh\scripts\FkhCredentialStore.ps1'))
        . ([ScriptBlock]::Create((Get-Content -LiteralPath $libraryPath -Raw)))
        . ([ScriptBlock]::Create((Get-Content -LiteralPath $storePath -Raw)))
        foreach ($required in @('Get-AprodaAlProjects', 'Find-AprodaAlTool', 'Get-AprodaAlLocalSelection', 'Get-FkhStoredCredential')) {
            if (-not (Get-Command -Name $required -CommandType Function -ErrorAction SilentlyContinue)) { throw "function $required is missing" }
        }
    }
    catch {
        Write-AlMcpStarterLog 'ERROR' 'LIBRARY_LOAD_FAILED' $_.Exception.Message
        exit 6
    }

    # 3. Projects
    $projects = @(Get-AprodaAlProjects -RepositoryRoot $RepositoryRoot)
    if ($projects.Count -eq 0) {
        Write-AlMcpStarterLog 'ERROR' 'NO_AL_PROJECT' "No sub-folder with app.json under '$RepositoryRoot'"
        exit 4
    }

    $warnings = New-Object System.Collections.Generic.List[object]
    $addWarning = {
        param([string]$Code, [string]$Text)
        $warnings.Add([pscustomobject]@{ code = $Code; text = $Text })
        Write-AlMcpStarterLog 'WARN' $Code $Text
    }

    # 4. altool
    try {
        $toolArguments = @{}
        if (-not [string]::IsNullOrWhiteSpace($AlExtensionPath)) { $toolArguments['AlExtensionPath'] = $AlExtensionPath }
        if (-not [string]::IsNullOrWhiteSpace($AlExtensionVersion)) { $toolArguments['AlExtensionVersion'] = $AlExtensionVersion }
        $altool = Find-AprodaAlTool @toolArguments
    }
    catch {
        $parts = $_.Exception.Message -split ': ', 2
        $code = $parts[0]
        $text = $_.Exception.Message
        if ($parts.Count -eq 2) { $text = $parts[1] }
        Write-AlMcpStarterLog 'ERROR' $code $text
        exit 3
    }
    foreach ($warning in @($altool.Warnings)) { & $addWarning $warning.code $warning.message }

    # 5. Never inherit a partial target (C-1)
    $targetVariables = @('BC_SERVER_URL', 'BC_SERVER_INSTANCE', 'BC_SERVER_PORT', 'BC_SERVER_USERNAME', 'BC_SERVER_PASSWORD', 'BC_ACCESS_TOKEN')
    foreach ($variable in $targetVariables) { Remove-Item -LiteralPath "Env:\$variable" -ErrorAction SilentlyContinue }

    # 6. Mode
    $selection = Get-AprodaAlLocalSelection -RepositoryRoot $RepositoryRoot
    $mode = 'target'
    $reasons = New-Object System.Collections.Generic.List[string]
    $credential = $null
    if ($selection.State -ne 'configured') {
        $mode = 'buildOnly'
        $code = 'SELECTION_' + $selection.State.ToUpperInvariant()
        $reasons.Add($code)
        $detail = $selection.State
        if ($selection.Reason) { $detail = [string]$selection.Reason }
        & $addWarning $code $detail
    }
    elseif (@($selection.Issues).Count -gt 0) {
        $mode = 'buildOnly'
        $reasons.Add('TARGET_BLOCKED')
        & $addWarning 'TARGET_BLOCKED' ((@($selection.Issues) | ForEach-Object { $_.code }) -join ',')
    }
    elseif ($selection.ResolvedLaunch.authentication -ceq 'UserPassword') {
        $credentialKey = [string]$selection.ResolvedLaunch.credentialKey
        try { $credential = Get-FkhStoredCredential -Key $credentialKey 3>$null 5>$null 6>$null } catch { $credential = $null }
        if ($null -eq $credential) {
            $mode = 'buildOnly'
            $reasons.Add('CREDENTIAL_MISSING')
            & $addWarning 'CREDENTIAL_MISSING' $credentialKey
        }
    }

    # 7. Target environment, process scope only
    if ($mode -eq 'target') {
        $bundle = Get-AprodaAlTargetBundle -Selection $selection
        [Environment]::SetEnvironmentVariable('BC_SERVER_URL', $bundle.ServerUrl, 'Process')
        [Environment]::SetEnvironmentVariable('BC_SERVER_INSTANCE', $bundle.ServerInstance, 'Process')
        [Environment]::SetEnvironmentVariable('BC_SERVER_PORT', [string]$bundle.Port, 'Process')
        if ($bundle.Authentication -ceq 'UserPassword') {
            [Environment]::SetEnvironmentVariable('BC_SERVER_USERNAME', $credential.UserName, 'Process')
            [Environment]::SetEnvironmentVariable('BC_SERVER_PASSWORD', $credential.GetNetworkCredential().Password, 'Process')
        }
    }

    # 8. First-configuration check (informational)
    foreach ($difference in @(Test-AprodaAlFirstConfiguration -RepositoryRoot $RepositoryRoot -Selection $selection)) {
        & $addWarning $difference.code $difference.project
    }

    # 9. Dry run: environment variable NAMES only
    if ($DryRun) {
        $environmentNames = @($targetVariables | Where-Object { Test-Path -LiteralPath "Env:\$_" } | Sort-Object)
        $plan = [ordered]@{
            mode     = $mode
            reasons  = $reasons.ToArray()
            altool   = [ordered]@{ path = $altool.Path; version = $altool.Version; source = $altool.Source }
            projects = @($projects | ForEach-Object { $_.Path })
            envNames = $environmentNames
            warnings = $warnings.ToArray()
        }
        [Console]::Error.WriteLine('[al-mcp-starter] PLAN ' + ($plan | ConvertTo-Json -Compress -Depth 6))
        exit 0
    }

    # 10. Hand over to altool
    $projectPaths = @($projects | ForEach-Object { $_.Path })
    & $altool.Path launchmcpserver @projectPaths --transport stdio
    exit $LASTEXITCODE
}
catch {
    Write-AlMcpStarterLog 'ERROR' 'UNEXPECTED' $_.Exception.Message
    exit 1
}
