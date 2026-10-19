<#
.SYNOPSIS
  Shared AL target library: git-ignored target selection (aldc.local.json), launch.json resolution,
  target bundle, altool locator, package-cache refresh. IMMUTABLE TEMPLATE (E-010, D-53).
.NOTES
  Load content-based (SRP-safe), pwsh 7 only:
    . ([ScriptBlock]::Create((Get-Content -LiteralPath <path> -Raw)))
  Contract (spec E-010.spec.md §2):
  - Functions write NOTHING to any stream except their return value; warnings are returned as data.
  - Errors are thrown as "<CODE>: <text>"; callers match the code prefix.
  - Functions that return lists emit the items; callers wrap the call in @(...).
  - Get-AprodaAlJsonProperty returns its value wrapped (",$v") so assign it to a variable, do not wrap it.
  No secrets are read or returned here; the credential store is a separate script.
#>

Set-StrictMode -Version Latest

function Get-AprodaAlJsonProperty {
    # Ordinal, case-sensitive property read on a parsed JSON object; $null when absent or not an object.
    param($Object, [Parameter(Mandatory)][string]$Name)
    Set-StrictMode -Version Latest
    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Object.PSObject.Properties) {
            if ($property.Name -ceq $Name) { return , $property.Value }
        }
    }
    return , $null
}

function Read-AprodaAlLaunchFile {
    # launch.json is JSONC (pwsh 7 ConvertFrom-Json accepts comments and trailing commas, C-5).
    param([Parameter(Mandatory)][string]$Path)
    Set-StrictMode -Version Latest
    $result = [pscustomobject]@{ Ok = $false; Reason = $null; Configurations = @() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $result.Reason = "launch.json not found: $Path"
        return $result
    }
    try {
        $document = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $result.Reason = "launch.json could not be parsed: $Path ($($_.Exception.Message))"
        return $result
    }
    $configurations = Get-AprodaAlJsonProperty $document 'configurations'
    if ($configurations -isnot [array]) {
        $result.Reason = "launch.json has no 'configurations' array: $Path"
        return $result
    }
    $result.Configurations = @($configurations)
    $result.Ok = $true
    return $result
}

function Test-AprodaAlServerConfiguration {
    param($Configuration)
    Set-StrictMode -Version Latest
    $server = Get-AprodaAlJsonProperty $Configuration 'server'
    return (($server -is [string]) -and -not [string]::IsNullOrWhiteSpace($server))
}

function ConvertTo-AprodaAlResolvedLaunch {
    # Spec §2.3: derive the resolved launch configuration and its issue codes from one configuration.
    param([Parameter(Mandatory)]$Configuration, [Parameter(Mandatory)][string]$LaunchFilePath)
    Set-StrictMode -Version Latest

    $nameValue = Get-AprodaAlJsonProperty $Configuration 'name'
    $name = [string]$nameValue
    $issues = [System.Collections.Generic.List[object]]::new()
    $addIssue = {
        param([string]$Code, [string]$Text)
        $issues.Add([pscustomobject]@{ code = $Code; message = "$Text (configuration '$name' in '$LaunchFilePath')" })
    }

    # server
    $server = [string](Get-AprodaAlJsonProperty $Configuration 'server')
    if ($server.EndsWith('/')) { $server = $server.Substring(0, $server.Length - 1) }
    $scheme = $null
    $serverHost = $null
    if ($server -match '^(?<scheme>https?)://(?<host>[^/:?#@\s]+)$') {
        $scheme = $Matches['scheme'].ToLowerInvariant()
        $serverHost = $Matches['host']
    }
    else {
        & $addIssue 'SERVER_INVALID' "server '$server' must be an absolute http/https URL without path, query or port"
    }

    # serverInstance
    $instanceValue = Get-AprodaAlJsonProperty $Configuration 'serverInstance'
    $serverInstance = $null
    if (($instanceValue -is [string]) -and -not [string]::IsNullOrWhiteSpace($instanceValue)) { $serverInstance = $instanceValue }
    else { & $addIssue 'INSTANCE_MISSING' 'serverInstance is missing or empty' }

    # port
    $portValue = Get-AprodaAlJsonProperty $Configuration 'port'
    $port = $null
    $portSource = 'launch'
    if ($null -eq $portValue) { $port = 7049; $portSource = 'default' }
    elseif ((($portValue -is [int]) -or ($portValue -is [long])) -and $portValue -ge 1 -and $portValue -le 65535) { $port = [int]$portValue }
    else { & $addIssue 'PORT_INVALID' "port '$portValue' must be an integer from 1 to 65535" }

    # tenant
    $tenantValue = Get-AprodaAlJsonProperty $Configuration 'tenant'
    $tenant = 'default'
    if (($tenantValue -is [string]) -and -not [string]::IsNullOrWhiteSpace($tenantValue)) { $tenant = $tenantValue }

    # environmentType
    $environmentValue = Get-AprodaAlJsonProperty $Configuration 'environmentType'
    $environmentType = 'OnPrem'
    if ($null -ne $environmentValue) {
        $environmentType = [string]$environmentValue
        if ($environmentType -cne 'OnPrem') { & $addIssue 'NOT_ONPREM' "environmentType '$environmentType' is not OnPrem" }
    }

    # authentication
    $authenticationValue = Get-AprodaAlJsonProperty $Configuration 'authentication'
    $authentication = $null
    if ($null -eq $authenticationValue -or (($authenticationValue -is [string]) -and [string]::IsNullOrWhiteSpace($authenticationValue))) {
        & $addIssue 'AUTH_MISSING' 'authentication is not set; set it explicitly (Windows or UserPassword)'
    }
    else {
        $authenticationText = [string]$authenticationValue
        if ($authenticationValue -isnot [string]) {
            $authentication = $authenticationText
            & $addIssue 'AUTH_UNKNOWN' "authentication '$authenticationText' is not a known value"
        }
        elseif ([string]::Equals($authenticationText, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { $authentication = 'Windows' }
        elseif ([string]::Equals($authenticationText, 'UserPassword', [System.StringComparison]::OrdinalIgnoreCase)) { $authentication = 'UserPassword' }
        elseif ([string]::Equals($authenticationText, 'AAD', [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($authenticationText, 'MicrosoftEntraID', [System.StringComparison]::OrdinalIgnoreCase)) {
            $authentication = $authenticationText
            & $addIssue 'AUTH_UNSUPPORTED' "authentication '$authenticationText' is not supported yet (supported: Windows, UserPassword)"
        }
        else {
            $authentication = $authenticationText
            & $addIssue 'AUTH_UNKNOWN' "authentication '$authenticationText' is not a known value (supported: Windows, UserPassword)"
        }
    }
    if ($authentication -ceq 'UserPassword' -and $scheme -ceq 'http') {
        & $addIssue 'USERPASSWORD_OVER_HTTP' 'UserPassword is only allowed over https'
    }

    # dependencyPublishingOption
    $dependencyValue = Get-AprodaAlJsonProperty $Configuration 'dependencyPublishingOption'
    $dependencyOption = 'Default'
    if ($null -ne $dependencyValue) {
        $dependencyOption = [string]$dependencyValue
        if ($dependencyOption -cnotin @('Default', 'Ignore', 'Strict')) {
            & $addIssue 'DEPENDENCY_OPTION_INVALID' "dependencyPublishingOption '$dependencyOption' must be Default, Ignore or Strict"
        }
    }

    $resolved = [pscustomobject][ordered]@{
        name                       = $name
        server                     = $server
        scheme                     = $scheme
        host                       = $serverHost
        serverInstance             = $serverInstance
        port                       = $port
        portSource                 = $portSource
        tenant                     = $tenant
        environmentType            = $environmentType
        authentication             = $authentication
        dependencyPublishingOption = $dependencyOption
        credentialKey              = $serverHost
    }
    return [pscustomobject]@{ ResolvedLaunch = $resolved; Issues = $issues.ToArray() }
}

function Resolve-AprodaAlLaunchTarget {
    # Validates a (launchProject, launchConfig) pair against the repository: invalid | stale | configured.
    param([Parameter(Mandatory)][string]$RepositoryRoot, $LaunchProject, $LaunchConfig)
    Set-StrictMode -Version Latest
    $result = [pscustomobject]@{ State = 'configured'; Reason = $null; ResolvedLaunch = $null; Issues = @() }

    if (($LaunchProject -isnot [string]) -or [string]::IsNullOrWhiteSpace($LaunchProject)) {
        $result.State = 'invalid'; $result.Reason = 'target.launchProject: must be a non-empty string'; return $result
    }
    if (($LaunchConfig -isnot [string]) -or [string]::IsNullOrWhiteSpace($LaunchConfig)) {
        $result.State = 'invalid'; $result.Reason = 'target.launchConfig: must be a non-empty string'; return $result
    }
    if ($LaunchProject -match '^[\\/]' -or $LaunchProject -match '^[A-Za-z]:' -or [System.IO.Path]::IsPathRooted($LaunchProject)) {
        $result.State = 'invalid'; $result.Reason = 'target.launchProject: must be relative to the repository (rooted path not allowed)'; return $result
    }
    if (($LaunchProject -split '[\\/]') -contains '..') {
        $result.State = 'invalid'; $result.Reason = "target.launchProject: '..' segment not allowed"; return $result
    }

    $projectDirectory = Join-Path $RepositoryRoot ($LaunchProject -replace '[\\/]', [string][System.IO.Path]::DirectorySeparatorChar)
    $launchFilePath = Join-Path (Join-Path $projectDirectory '.vscode') 'launch.json'
    $launchFile = Read-AprodaAlLaunchFile -Path $launchFilePath
    if (-not $launchFile.Ok) {
        $result.State = 'stale'; $result.Reason = $launchFile.Reason; return $result
    }
    $match = $null
    foreach ($configuration in $launchFile.Configurations) {
        $candidateName = Get-AprodaAlJsonProperty $configuration 'name'
        if (($candidateName -is [string]) -and ($candidateName -ceq $LaunchConfig)) { $match = $configuration; break }
    }
    if ($null -eq $match) {
        $result.State = 'stale'; $result.Reason = "launch.json has no configuration named '$LaunchConfig': $launchFilePath"; return $result
    }
    if (-not (Test-AprodaAlServerConfiguration -Configuration $match)) {
        $result.State = 'stale'; $result.Reason = "configuration '$LaunchConfig' has no server: $launchFilePath"; return $result
    }
    $derived = ConvertTo-AprodaAlResolvedLaunch -Configuration $match -LaunchFilePath $launchFilePath
    $result.ResolvedLaunch = $derived.ResolvedLaunch
    $result.Issues = @($derived.Issues)
    return $result
}

function New-AprodaAlSelectionObject {
    param([string]$State, $Path, $Reason, $Target, $ResolvedLaunch, $Issues)
    Set-StrictMode -Version Latest
    return [pscustomobject]@{
        State          = $State
        Path           = $Path
        Reason         = $Reason
        Target         = $Target
        ResolvedLaunch = $ResolvedLaunch
        Issues         = $(if ($null -eq $Issues) { @() } else { @($Issues) })
        Warnings       = @()
    }
}

function Get-AprodaAlRepositoryRoot {
    param([Parameter(Mandatory)][string]$StartPath)
    Set-StrictMode -Version Latest
    $current = [System.IO.Path]::GetFullPath($StartPath)
    if (Test-Path -LiteralPath $current -PathType Leaf) { $current = [System.IO.Path]::GetDirectoryName($current) }
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath (Join-Path $current '.git')) { return $current }
        $current = [System.IO.Path]::GetDirectoryName($current)
    }
    throw "REPO_ROOT_NOT_FOUND: no .git found at or above '$StartPath'"
}

function Get-AprodaAlLocalSelectionPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Set-StrictMode -Version Latest
    if (Test-Path -LiteralPath (Join-Path (Join-Path $RepositoryRoot '.github') 'aldc.yaml') -PathType Leaf) {
        return (Join-Path (Join-Path $RepositoryRoot '.github') 'aldc.local.json')
    }
    if (Test-Path -LiteralPath (Join-Path $RepositoryRoot 'aldc.yaml') -PathType Leaf) {
        return (Join-Path $RepositoryRoot 'aldc.local.json')
    }
    return $null
}

function Get-AprodaAlLocalSelection {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Set-StrictMode -Version Latest

    $path = Get-AprodaAlLocalSelectionPath -RepositoryRoot $RepositoryRoot
    if ($null -eq $path) { return (New-AprodaAlSelectionObject -State 'noToolkit' -Path $null -Reason 'no aldc.yaml found under the repository root') }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-AprodaAlSelectionObject -State 'absent' -Path $path) }

    # Strict JSON (no comments, no trailing commas): System.Text.Json default options reject both.
    $text = [System.IO.File]::ReadAllText($path)
    try { [System.Text.Json.JsonDocument]::Parse($text).Dispose() }
    catch { return (New-AprodaAlSelectionObject -State 'invalid' -Path $path -Reason "file: not strict JSON ($($_.Exception.Message))") }
    $document = $text | ConvertFrom-Json -ErrorAction Stop
    if ($document -isnot [System.Management.Automation.PSCustomObject]) {
        return (New-AprodaAlSelectionObject -State 'invalid' -Path $path -Reason 'root: must be a JSON object')
    }
    $version = Get-AprodaAlJsonProperty $document 'version'
    if (-not ((($version -is [int]) -or ($version -is [long])) -and $version -eq 1)) {
        return (New-AprodaAlSelectionObject -State 'invalid' -Path $path -Reason 'version: must be the integer 1')
    }
    $target = Get-AprodaAlJsonProperty $document 'target'
    if ($target -isnot [System.Management.Automation.PSCustomObject]) {
        return (New-AprodaAlSelectionObject -State 'invalid' -Path $path -Reason 'target: must be an object')
    }
    $launchProject = Get-AprodaAlJsonProperty $target 'launchProject'
    $launchConfig = Get-AprodaAlJsonProperty $target 'launchConfig'

    $resolution = Resolve-AprodaAlLaunchTarget -RepositoryRoot $RepositoryRoot -LaunchProject $launchProject -LaunchConfig $launchConfig
    if ($resolution.State -eq 'invalid') {
        return (New-AprodaAlSelectionObject -State 'invalid' -Path $path -Reason $resolution.Reason)
    }
    $targetInfo = [pscustomobject]@{ LaunchProject = $launchProject; LaunchConfig = $launchConfig }
    return (New-AprodaAlSelectionObject -State $resolution.State -Path $path -Reason $resolution.Reason -Target $targetInfo `
            -ResolvedLaunch $resolution.ResolvedLaunch -Issues $resolution.Issues)
}

function Save-AprodaAlLocalSelectionFile {
    # Atomic write (temp file + rename), UTF-8 without BOM, 2-space indent, trailing newline; unknown keys preserved.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$LaunchProject, [Parameter(Mandatory)][string]$LaunchConfig)
    Set-StrictMode -Version Latest

    $existing = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $existing = [System.Text.Json.JsonDocument]::Parse([System.IO.File]::ReadAllText($Path))
            if ($existing.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { $existing.Dispose(); $existing = $null }
        }
        catch { $existing = $null }
    }
    try {
        $options = [System.Text.Json.JsonWriterOptions]::new()
        $options.Indented = $true
        $options.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
        $stream = [System.IO.MemoryStream]::new()
        $writer = [System.Text.Json.Utf8JsonWriter]::new($stream, $options)
        $writer.WriteStartObject()
        $writer.WriteNumber('version', [int]1)
        $writer.WriteStartObject('target')
        $writer.WriteString('launchProject', $LaunchProject)
        $writer.WriteString('launchConfig', $LaunchConfig)
        if ($null -ne $existing) {
            foreach ($property in $existing.RootElement.EnumerateObject()) {
                if ($property.Name -ceq 'target' -and $property.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
                    foreach ($targetProperty in $property.Value.EnumerateObject()) {
                        if ($targetProperty.Name -cnotin @('launchProject', 'launchConfig')) { $targetProperty.WriteTo($writer) }
                    }
                }
            }
        }
        $writer.WriteEndObject()
        if ($null -ne $existing) {
            foreach ($property in $existing.RootElement.EnumerateObject()) {
                if ($property.Name -cnotin @('version', 'target')) { $property.WriteTo($writer) }
            }
        }
        $writer.WriteEndObject()
        $writer.Flush()
        $json = [System.Text.Encoding]::UTF8.GetString($stream.ToArray()).Replace("`r`n", "`n") + "`n"
    }
    finally {
        if ($null -ne $existing) { $existing.Dispose() }
    }

    $temporaryPath = "$Path.tmp"
    try {
        [System.IO.File]::WriteAllBytes($temporaryPath, [System.Text.UTF8Encoding]::new($false).GetBytes($json))
        [System.IO.File]::Move($temporaryPath, $Path, $true)
    }
    catch {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Set-AprodaAlLocalSelection {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$LaunchProject,
        [Parameter(Mandatory)][string]$LaunchConfig
    )
    Set-StrictMode -Version Latest

    $path = Get-AprodaAlLocalSelectionPath -RepositoryRoot $RepositoryRoot
    if ($null -eq $path) { throw 'SELECTION_WOULD_BE_NOTOOLKIT: no aldc.yaml found under the repository root' }
    $resolution = Resolve-AprodaAlLaunchTarget -RepositoryRoot $RepositoryRoot -LaunchProject $LaunchProject -LaunchConfig $LaunchConfig
    if ($resolution.State -ne 'configured') {
        throw "SELECTION_WOULD_BE_$($resolution.State.ToUpperInvariant()): $($resolution.Reason)"
    }
    Save-AprodaAlLocalSelectionFile -Path $path -LaunchProject $LaunchProject -LaunchConfig $LaunchConfig
    return (Get-AprodaAlLocalSelection -RepositoryRoot $RepositoryRoot)
}

function Get-AprodaAlProjects {
    # Direct sub-folders of the repository root that contain app.json, ordinal-sorted (C-8).
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Set-StrictMode -Version Latest
    if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) { return }
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($directory in @(Get-ChildItem -LiteralPath $RepositoryRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $directory.FullName 'app.json') -PathType Leaf) { $names.Add($directory.Name) }
    }
    $sorted = $names.ToArray()
    [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    foreach ($name in $sorted) {
        [pscustomobject]@{ Name = $name; Path = (Join-Path $RepositoryRoot $name) }
    }
}

function Get-AprodaAlLaunchConfigurations {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Set-StrictMode -Version Latest
    foreach ($project in @(Get-AprodaAlProjects -RepositoryRoot $RepositoryRoot)) {
        $launchFile = Read-AprodaAlLaunchFile -Path (Join-Path (Join-Path $project.Path '.vscode') 'launch.json')
        if (-not $launchFile.Ok) { continue }
        foreach ($configuration in $launchFile.Configurations) {
            if (-not (Test-AprodaAlServerConfiguration -Configuration $configuration)) { continue }
            $authentication = Get-AprodaAlJsonProperty $configuration 'authentication'
            $serverInstance = Get-AprodaAlJsonProperty $configuration 'serverInstance'
            [pscustomobject]@{
                LaunchProject  = $project.Name
                Name           = [string](Get-AprodaAlJsonProperty $configuration 'name')
                Server         = [string](Get-AprodaAlJsonProperty $configuration 'server')
                ServerInstance = $(if ($null -eq $serverInstance) { $null } else { [string]$serverInstance })
                Authentication = $(if ($null -eq $authentication) { $null } else { [string]$authentication })
            }
        }
    }
}

function Get-AprodaAlTargetBundle {
    param([Parameter(Mandatory)][AllowNull()]$Selection)
    Set-StrictMode -Version Latest
    if ($null -eq $Selection -or $Selection.State -ne 'configured') {
        $state = if ($null -eq $Selection) { 'none' } else { [string]$Selection.State }
        throw "TARGET_NOT_CONFIGURED: the AL target selection is '$state'"
    }
    $issues = @($Selection.Issues)
    if ($issues.Count -gt 0) {
        throw "TARGET_BLOCKED: $((@($issues | ForEach-Object { $_.code }) -join ','))"
    }
    $resolved = $Selection.ResolvedLaunch
    return [pscustomobject]@{
        ServerUrl      = "$($resolved.scheme)://$($resolved.host)"
        ServerInstance = $resolved.serverInstance
        Port           = $resolved.port
        Authentication = $resolved.authentication
        Tenant         = $resolved.tenant
    }
}

function Get-AprodaAlToolBinary {
    # Extension layouts: bin\altool.exe, else bin\win32\altool.exe. $null when neither exists.
    param([Parameter(Mandatory)][string]$ExtensionPath)
    Set-StrictMode -Version Latest
    foreach ($relative in @('bin\altool.exe', 'bin\win32\altool.exe')) {
        $candidate = Join-Path $ExtensionPath $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Find-AprodaAlTool {
    param([string]$AlExtensionPath, [string]$AlExtensionVersion, [string]$ExtensionsRoot)
    Set-StrictMode -Version Latest
    $warnings = [System.Collections.Generic.List[object]]::new()
    $namePattern = '^ms-dynamics-smb\.al-(?<v>\d+\.\d+\.\d+)(?:-(?<platform>[a-z0-9-]+))?$'

    # 1. Explicit path of the active extension is authoritative: no search.
    if (-not [string]::IsNullOrWhiteSpace($AlExtensionPath)) {
        $binary = Get-AprodaAlToolBinary -ExtensionPath $AlExtensionPath
        if ($null -eq $binary) {
            throw "ALTOOL_NOT_IN_ACTIVE_EXTENSION: no bin\altool.exe or bin\win32\altool.exe under '$AlExtensionPath'"
        }
        $version = $null
        if (-not [string]::IsNullOrWhiteSpace($AlExtensionVersion)) { $version = $AlExtensionVersion }
        else {
            $leaf = Split-Path -Leaf ($AlExtensionPath.TrimEnd('\', '/'))
            if ($leaf -match $namePattern) { $version = $Matches['v'] }
        }
        return [pscustomobject]@{ Path = $binary; Version = $version; Source = 'parameter'; Warnings = $warnings.ToArray() }
    }

    # 2. Installed extensions: parsed semver ranking, never LastWriteTime.
    if ([string]::IsNullOrWhiteSpace($ExtensionsRoot)) { $ExtensionsRoot = Join-Path $env:USERPROFILE '.vscode\extensions' }
    if (Test-Path -LiteralPath $ExtensionsRoot -PathType Container) {
        $obsolete = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $obsoletePath = Join-Path $ExtensionsRoot '.obsolete'
        if (Test-Path -LiteralPath $obsoletePath -PathType Leaf) {
            try {
                $obsoleteDocument = Get-Content -LiteralPath $obsoletePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($obsoleteDocument -is [System.Management.Automation.PSCustomObject]) {
                    foreach ($entry in $obsoleteDocument.PSObject.Properties) {
                        if (($entry.Value -is [bool]) -and $entry.Value) { [void]$obsolete.Add($entry.Name) }
                    }
                }
            }
            catch {
                $warnings.Add([pscustomobject]@{ code = 'ALTOOL_OBSOLETE_LIST_UNREADABLE'; message = "Could not read '$obsoletePath'; pending-deletion extensions are not excluded." })
            }
        }
        $candidates = [System.Collections.Generic.List[object]]::new()
        foreach ($directory in @(Get-ChildItem -LiteralPath $ExtensionsRoot -Directory -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue)) {
            if ($obsolete.Contains($directory.Name)) { continue }
            if ($directory.Name -notmatch $namePattern) {
                throw "ALTOOL_UNPARSABLE_VERSION: cannot parse the version of extension folder '$($directory.Name)'"
            }
            $candidates.Add([pscustomobject]@{ Directory = $directory; Version = [version]$Matches['v']; VersionText = $Matches['v'] })
        }
        if ($candidates.Count -gt 0) {
            $ranked = @($candidates | Sort-Object -Property Version -Descending)
            $best = $ranked[0]
            $tied = @($ranked | Where-Object { $_.Version -eq $best.Version })
            if ($tied.Count -gt 1) {
                throw "ALTOOL_AMBIGUOUS: several extension folders share the highest version $($best.VersionText): $((@($tied | ForEach-Object { $_.Directory.Name }) -join '; '))"
            }
            $binary = Get-AprodaAlToolBinary -ExtensionPath $best.Directory.FullName
            if ($null -eq $binary) {
                throw "ALTOOL_MISSING_IN_EXTENSION: no altool.exe in '$($best.Directory.FullName)'"
            }
            return [pscustomobject]@{ Path = $binary; Version = $best.VersionText; Source = 'extension'; Warnings = $warnings.ToArray() }
        }
    }

    # 3. dotnet tool `al` on PATH (D-34): fallback only.
    $command = Get-Command -Name 'al' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        $warnings.Add([pscustomobject]@{ code = 'ALTOOL_FALLBACK_DOTNET_TOOL'; message = "Using the dotnet tool 'al' from PATH ($($command.Source)); its version may differ from the editor's compiler." })
        return [pscustomobject]@{ Path = $command.Source; Version = $null; Source = 'dotnetTool'; Warnings = $warnings.ToArray() }
    }

    throw 'ALTOOL_NOT_FOUND: no altool in an installed ms-dynamics-smb.al extension and no dotnet tool al on PATH'
}

function Test-AprodaAlFirstConfiguration {
    # C-1: altool merges unset values from the FIRST server configuration of a project's launch.json.
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][AllowNull()]$Selection)
    Set-StrictMode -Version Latest
    if ($null -eq $Selection -or $Selection.State -ne 'configured') { return }
    $selected = $Selection.ResolvedLaunch
    foreach ($project in @(Get-AprodaAlProjects -RepositoryRoot $RepositoryRoot)) {
        $launchFilePath = Join-Path (Join-Path $project.Path '.vscode') 'launch.json'
        $launchFile = Read-AprodaAlLaunchFile -Path $launchFilePath
        if (-not $launchFile.Ok) { continue }
        $first = $null
        foreach ($configuration in $launchFile.Configurations) {
            if (Test-AprodaAlServerConfiguration -Configuration $configuration) { $first = $configuration; break }
        }
        if ($null -eq $first) { continue }
        $firstResolved = (ConvertTo-AprodaAlResolvedLaunch -Configuration $first -LaunchFilePath $launchFilePath).ResolvedLaunch
        $differences = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::Equals([string]$firstResolved.server, [string]$selected.server, [System.StringComparison]::OrdinalIgnoreCase)) { $differences.Add('server') }
        if ([string]$firstResolved.serverInstance -cne [string]$selected.serverInstance) { $differences.Add('serverInstance') }
        if ([string]$firstResolved.port -cne [string]$selected.port) { $differences.Add('port') }
        if (-not [string]::Equals([string]$firstResolved.authentication, [string]$selected.authentication, [System.StringComparison]::OrdinalIgnoreCase)) { $differences.Add('authentication') }
        if ($differences.Count -gt 0) {
            [pscustomobject]@{
                code    = 'FIRST_CONFIG_DIFFERS'
                project = $project.Name
                message = "First server configuration '$($firstResolved.name)' in '$launchFilePath' differs from the selected target in: $($differences -join ', '). altool merges unset values from it."
            }
        }
    }
}

function Update-AprodaAlPackageCache {
    # Q-2: neither MCP al_build nor alc.exe refreshes a dependency package; copy the fresh Base app into the Test project.
    param([Parameter(Mandatory)][string]$SourceAppFile, [Parameter(Mandatory)][string]$TargetProjectDir)
    Set-StrictMode -Version Latest
    if (-not (Test-Path -LiteralPath $SourceAppFile -PathType Leaf)) { throw "SOURCE_APP_NOT_FOUND: '$SourceAppFile'" }
    if (-not (Test-Path -LiteralPath $TargetProjectDir -PathType Container)) { throw "TARGET_PROJECT_NOT_FOUND: '$TargetProjectDir'" }
    $sourceName = Split-Path -Leaf $SourceAppFile
    if ($sourceName -notmatch '^(?<prefix>.+)_\d+(\.\d+){3}\.app$') {
        throw "APP_FILE_NAME_UNPARSABLE: '$sourceName' does not match <publisher>_<name>_<version>.app"
    }
    $prefixPattern = '^' + [regex]::Escape($Matches['prefix']) + '_\d+(\.\d+){3}\.app$'
    $packagesDirectory = Join-Path $TargetProjectDir '.alpackages'
    if (-not (Test-Path -LiteralPath $packagesDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $packagesDirectory -Force | Out-Null
    }
    $destination = Join-Path $packagesDirectory $sourceName
    $sourceFull = [System.IO.Path]::GetFullPath($SourceAppFile)
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $packagesDirectory -File -Filter '*.app' -ErrorAction SilentlyContinue)) {
        if ($file.Name -cmatch $prefixPattern -and $file.FullName -ne $sourceFull) {
            Remove-Item -LiteralPath $file.FullName -Force
            $removed.Add($file.Name)
        }
    }
    if ([System.IO.Path]::GetFullPath($destination) -ne $sourceFull) {
        Copy-Item -LiteralPath $SourceAppFile -Destination $destination -Force
    }
    return [pscustomobject]@{ Removed = $removed.ToArray(); Copied = $destination }
}
