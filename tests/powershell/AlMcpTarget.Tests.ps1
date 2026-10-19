# E-010 phase 2: AL target library and starter (S-2.1 .. S-2.17).
# Self-contained harness, no Pester (only Pester 3.4 is installed). Run content-based (SRP-safe), pwsh 7:
#   $env:APRODA_TEST_REPOSITORY_ROOT = '<repo>'
#   Get-Content -LiteralPath tests\powershell\AlMcpTarget.Tests.ps1 -Raw | Invoke-Expression
# S-2.15: exit code 5 (pwsh < 7) is reviewed in code and not automated; Windows PowerShell 5.1 is not exercised here.

Set-StrictMode -Version Latest

$repositoryRoot = $env:APRODA_TEST_REPOSITORY_ROOT
if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$skillRoot = Join-Path $repositoryRoot 'skills\skill-aproda-al-mcp'
$libraryPath = Join-Path $skillRoot 'scripts\AprodaAlTarget.ps1'
$starterPath = Join-Path $skillRoot 'scripts\Start-AprodaAlMcp.ps1'
$credentialStorePath = Join-Path $repositoryRoot 'skills\skill-aproda-fkh\scripts\FkhCredentialStore.ps1'
$fixturesRoot = Join-Path $repositoryRoot 'tests\fixtures\al-target'
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP ('aproda-almcp-tests-' + [guid]::NewGuid().ToString('N'))))
$originalLocalAppData = $env:LOCALAPPDATA
$originalPath = $env:PATH
$pwshPath = (Get-Process -Id $PID).Path

$script:passed = 0
$script:failed = [System.Collections.Generic.List[string]]::new()

function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Test)
    try {
        & $Test
        $script:passed++
        Write-Host "PASS: $Name"
    }
    catch {
        $script:failed.Add($Name)
        Write-Host "FAIL: $Name"
        Write-Host "      $($_.Exception.Message)"
    }
}

function Assert-True {
    param($Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if (-not ($Actual -ceq $Expected)) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-Null {
    param($Actual, [string]$Message)
    if ($null -ne $Actual) { throw "$Message Expected `$null, got '$Actual'." }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$CodePrefix, [string]$Message)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught) { throw "$Message Expected an error starting with '$CodePrefix' but nothing was thrown." }
    if (-not $caught.StartsWith($CodePrefix, [System.StringComparison]::Ordinal)) { throw "$Message Expected an error starting with '$CodePrefix', got '$caught'." }
}

function Write-TestFile {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function New-TestFolder {
    param([string]$Prefix = 't')
    $path = Join-Path $tempRoot ($Prefix + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

$validLaunch = @'
{
  // JSONC: comments and a trailing comma are valid in launch.json
  "version": "0.2.0",
  "configurations": [
    { "name": "cfg-win", "type": "al", "request": "launch", "environmentType": "OnPrem", "server": "http://nst.example.com", "serverInstance": "BC", "port": 7049, "authentication": "Windows" },
    { "name": "cfg-up", "type": "al", "request": "launch", "environmentType": "OnPrem", "server": "https://dev.example.com", "serverInstance": "BC2", "port": 7050, "authentication": "UserPassword" },
    { "name": "cfg-noauth", "type": "al", "request": "launch", "server": "http://nst.example.com", "serverInstance": "BC" },
  ]
}
'@

function New-LocalJson {
    param([string]$Project, [string]$Config)
    return "{`n  `"version`": 1,`n  `"target`": {`n    `"launchProject`": `"$Project`",`n    `"launchConfig`": `"$Config`"`n  }`n}`n"
}

function New-TestRepo {
    # Toolkit: github = .github\aldc.yaml, root = aldc.yaml, both, none.
    param([string]$Toolkit = 'github', [string]$LocalJson, [string]$LaunchJson = $validLaunch, [string[]]$Projects = @('Base'))
    $repo = New-TestFolder 'repo'
    New-Item -ItemType Directory -Path (Join-Path $repo '.git') -Force | Out-Null
    if ($Toolkit -in @('github', 'both')) { Write-TestFile (Join-Path $repo '.github\aldc.yaml') "toolkitRoot: `".`"`n" }
    if ($Toolkit -in @('root', 'both')) { Write-TestFile (Join-Path $repo 'aldc.yaml') "toolkitRoot: `".`"`n" }
    foreach ($project in $Projects) {
        Write-TestFile (Join-Path $repo "$project\app.json") "{ `"name`": `"$project`", `"publisher`": `"Fixture`", `"version`": `"1.0.0.0`" }`n"
        if ($null -ne $LaunchJson) { Write-TestFile (Join-Path $repo "$project\.vscode\launch.json") $LaunchJson }
    }
    if ($LocalJson) {
        $localPath = if ($Toolkit -eq 'root') { Join-Path $repo 'aldc.local.json' } else { Join-Path $repo '.github\aldc.local.json' }
        Write-TestFile $localPath $LocalJson
    }
    return $repo
}

function New-FakeExtension {
    # Layout: bin = bin\altool.exe, win32 = bin\win32\altool.exe, none = no binary. The dummy file is never executed.
    param([string]$Root, [string]$Name, [string]$Layout = 'bin')
    $directory = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    if ($Layout -eq 'bin') { Write-TestFile (Join-Path $directory 'bin\altool.exe') '' }
    if ($Layout -eq 'win32') { Write-TestFile (Join-Path $directory 'bin\win32\altool.exe') '' }
    return $directory
}

function Get-TestSelection {
    param([hashtable]$Config)
    $launch = @{ configurations = @($Config) } | ConvertTo-Json -Depth 5
    $repo = New-TestRepo -LaunchJson $launch -LocalJson (New-LocalJson 'Base' 'cfg')
    return (Get-AprodaAlLocalSelection -RepositoryRoot $repo)
}

function Get-BaseConfig {
    return @{ name = 'cfg'; type = 'al'; request = 'launch'; environmentType = 'OnPrem'; server = 'https://dev.example.com'; serverInstance = 'BC'; port = 7049; authentication = 'Windows' }
}

function Invoke-StarterProcess {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [string]$AlExtensionPath,
        [string]$Skill = $skillRoot,
        [hashtable]$Environment = @{}
    )
    $starterLiteral = $starterPath.Replace("'", "''")
    $command = "& ([ScriptBlock]::Create((Get-Content -LiteralPath '$starterLiteral' -Raw))) -RepositoryRoot '$($Repo.Replace("'", "''"))' -SkillRoot '$($Skill.Replace("'", "''"))'"
    if ($AlExtensionPath) { $command += " -AlExtensionPath '$($AlExtensionPath.Replace("'", "''"))'" }
    $command += ' -DryRun'
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($pwshPath)
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', $command)) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    foreach ($key in $Environment.Keys) {
        if ($null -eq $Environment[$key]) { [void]$startInfo.Environment.Remove($key) } else { $startInfo.Environment[$key] = [string]$Environment[$key] }
    }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdoutTask.Result; Stderr = $stderrTask.Result }
}

function Get-StarterPlan {
    param([string]$Stderr)
    $line = @($Stderr -split "`r?`n" | Where-Object { $_.StartsWith('[al-mcp-starter] PLAN ', [System.StringComparison]::Ordinal) })
    if ($line.Count -ne 1) { throw "Expected exactly one PLAN line, found $($line.Count). stderr: $Stderr" }
    return ($line[0].Substring('[al-mcp-starter] PLAN '.Length) | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    . ([scriptblock]::Create((Get-Content -LiteralPath $libraryPath -Raw)))
    . ([scriptblock]::Create((Get-Content -LiteralPath $credentialStorePath -Raw)))

    Invoke-TestCase 'S-2.1 selection location and repository root' {
        $both = New-TestRepo -Toolkit both
        Assert-Equal (Get-AprodaAlLocalSelectionPath -RepositoryRoot $both) (Join-Path $both '.github\aldc.local.json') 'Both aldc.yaml present: .github wins.'
        $github = New-TestRepo -Toolkit github
        Assert-Equal (Get-AprodaAlLocalSelectionPath -RepositoryRoot $github) (Join-Path $github '.github\aldc.local.json') '.github\aldc.yaml.'
        $root = New-TestRepo -Toolkit root
        Assert-Equal (Get-AprodaAlLocalSelectionPath -RepositoryRoot $root) (Join-Path $root 'aldc.local.json') 'Only root aldc.yaml.'
        $none = New-TestRepo -Toolkit none
        Assert-Null (Get-AprodaAlLocalSelectionPath -RepositoryRoot $none) 'No aldc.yaml.'
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $none).State 'noToolkit' 'noToolkit state.'

        $nested = Join-Path $github 'Base\src\deep'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        Assert-Equal (Get-AprodaAlRepositoryRoot -StartPath $nested) $github 'Git root from a nested folder.'
        $worktree = New-TestFolder 'worktree'
        Write-TestFile (Join-Path $worktree '.git') 'gitdir: elsewhere'
        Assert-Equal (Get-AprodaAlRepositoryRoot -StartPath $worktree) $worktree 'A .git file counts as git root.'
        $noGit = New-TestFolder 'nogit'
        Assert-Throws { Get-AprodaAlRepositoryRoot -StartPath $noGit } 'REPO_ROOT_NOT_FOUND' 'No git root.'
    }

    Invoke-TestCase 'S-2.2 selection states' {
        $absent = New-TestRepo
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $absent).State 'absent' 'Missing file.'

        $invalidCases = [ordered]@{
            'file: not strict JSON'           = '{ not json'
            'file: not strict JSON (comment)' = "{`n // c`n `"version`": 1, `"target`": { `"launchProject`": `"Base`", `"launchConfig`": `"cfg-win`" } }"
            'file: not strict JSON (comma)'   = '{ "version": 1, "target": { "launchProject": "Base", "launchConfig": "cfg-win", } }'
            'root:'                           = '[1]'
            'version:'                        = '{ "version": 2, "target": { "launchProject": "Base", "launchConfig": "cfg-win" } }'
            'version: (decimal)'              = '{ "version": 1.0, "target": { "launchProject": "Base", "launchConfig": "cfg-win" } }'
            'target:'                         = '{ "version": 1, "target": "Base" }'
            'target.launchProject:'           = '{ "version": 1, "target": { "launchConfig": "cfg-win" } }'
            'target.launchProject: (empty)'   = '{ "version": 1, "target": { "launchProject": "", "launchConfig": "cfg-win" } }'
            'target.launchConfig:'            = '{ "version": 1, "target": { "launchProject": "Base" } }'
            'target.launchConfig: (empty)'    = '{ "version": 1, "target": { "launchProject": "Base", "launchConfig": " " } }'
            'rooted (drive)'                  = '{ "version": 1, "target": { "launchProject": "C:\\x", "launchConfig": "cfg-win" } }'
            'rooted (slash)'                  = '{ "version": 1, "target": { "launchProject": "/x", "launchConfig": "cfg-win" } }'
            '.. (leading)'                    = '{ "version": 1, "target": { "launchProject": "..\\Other", "launchConfig": "cfg-win" } }'
            '.. (inner)'                      = '{ "version": 1, "target": { "launchProject": "Base/../x", "launchConfig": "cfg-win" } }'
        }
        foreach ($case in $invalidCases.Keys) {
            $repo = New-TestRepo -LocalJson $invalidCases[$case]
            $selection = Get-AprodaAlLocalSelection -RepositoryRoot $repo
            Assert-Equal $selection.State 'invalid' "Case '$case' state."
            Assert-True (-not [string]::IsNullOrWhiteSpace($selection.Reason)) "Case '$case' has a reason."
            $rule = ($case -split ' ')[0]
            if ($rule.EndsWith(':')) {
                Assert-True $selection.Reason.StartsWith($rule.TrimEnd(':'), [System.StringComparison]::Ordinal) "Case '$case' reason '$($selection.Reason)' names the rule."
            }
            elseif ($case -like 'rooted*') { Assert-True $selection.Reason.Contains('relative') "Case '$case' reason '$($selection.Reason)'." }
            else { Assert-True $selection.Reason.Contains("'..'") "Case '$case' reason '$($selection.Reason)'." }
            Assert-Null $selection.ResolvedLaunch "Case '$case' resolvedLaunch."
        }

        $noLaunch = New-TestRepo -LaunchJson $null -LocalJson (New-LocalJson 'Base' 'cfg-win')
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $noLaunch).State 'stale' 'launch.json missing.'
        $badLaunch = New-TestRepo -LaunchJson '{ "configurations": [ ' -LocalJson (New-LocalJson 'Base' 'cfg-win')
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $badLaunch).State 'stale' 'launch.json unparseable.'
        $caseDiffers = New-TestRepo -LocalJson (New-LocalJson 'Base' 'CFG-WIN')
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $caseDiffers).State 'stale' 'Name differs only in case.'
        $noServer = New-TestRepo -LaunchJson '{ "configurations": [ { "name": "attach-only", "type": "al", "request": "attach" } ] }' -LocalJson (New-LocalJson 'Base' 'attach-only')
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $noServer).State 'stale' 'Configuration without server.'
        $otherProject = New-TestRepo -LocalJson (New-LocalJson 'Missing' 'cfg-win')
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $otherProject).State 'stale' 'Project folder without launch.json.'

        $valid = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-win')
        $selection = Get-AprodaAlLocalSelection -RepositoryRoot $valid
        Assert-Equal $selection.State 'configured' 'Valid selection.'
        Assert-Equal $selection.Target.LaunchProject 'Base' 'Target project.'
        Assert-Equal $selection.Target.LaunchConfig 'cfg-win' 'Target config.'
        Assert-Equal @($selection.Issues).Count 0 'No issues.'
        $viaRoot = New-TestRepo -Toolkit root -LocalJson (New-LocalJson 'Base' 'cfg-win')
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $viaRoot).State 'configured' 'Root aldc.yaml layout.'
    }

    Invoke-TestCase 'S-2.3 fixture parity' {
        $cases = @(Get-ChildItem -LiteralPath $fixturesRoot -Directory -Filter 'case-*')
        Assert-True ($cases.Count -ge 10) "Expected at least 10 fixture cases, found $($cases.Count)."
        foreach ($case in $cases) {
            $expected = Get-Content -LiteralPath (Join-Path $case.FullName 'expected.json') -Raw | ConvertFrom-Json
            $actual = Get-AprodaAlLocalSelection -RepositoryRoot $case.FullName
            Assert-Equal $actual.State $expected.state "$($case.Name): state."
            Assert-Equal ((@($actual.Issues | ForEach-Object { $_.code })) -join ',') ((@($expected.issues)) -join ',') "$($case.Name): issue codes."
            if ($null -eq $expected.resolvedLaunch) {
                Assert-Null $actual.ResolvedLaunch "$($case.Name): resolvedLaunch."
            }
            else {
                Assert-True ($null -ne $actual.ResolvedLaunch) "$($case.Name): resolvedLaunch expected."
                $expectedNames = (@($expected.resolvedLaunch.PSObject.Properties.Name) | Sort-Object) -join ','
                $actualNames = (@($actual.ResolvedLaunch.PSObject.Properties.Name) | Sort-Object) -join ','
                Assert-Equal $actualNames $expectedNames "$($case.Name): resolvedLaunch property names."
                foreach ($property in $expected.resolvedLaunch.PSObject.Properties) {
                    $actualValue = $actual.ResolvedLaunch.($property.Name)
                    Assert-True (($null -eq $actualValue) -eq ($null -eq $property.Value)) "$($case.Name): $($property.Name) null-ness."
                    Assert-Equal ([string]$actualValue) ([string]$property.Value) "$($case.Name): resolvedLaunch.$($property.Name)."
                }
            }
        }
    }

    Invoke-TestCase 'S-2.4 derivation' {
        $minimal = Get-BaseConfig
        $minimal.Remove('port'); $minimal.Remove('environmentType')
        $minimal['server'] = 'https://Host.Example.COM/'
        $resolved = (Get-TestSelection -Config $minimal).ResolvedLaunch
        Assert-Equal $resolved.port 7049 'Default port.'
        Assert-Equal $resolved.portSource 'default' 'Default port source.'
        Assert-Equal $resolved.tenant 'default' 'Default tenant.'
        Assert-Equal $resolved.environmentType 'OnPrem' 'Default environment type.'
        Assert-Equal $resolved.server 'https://Host.Example.COM' 'Trailing slash removed.'
        Assert-Equal $resolved.host 'Host.Example.COM' 'Host case kept.'
        Assert-Equal $resolved.scheme 'https' 'Scheme.'
        Assert-Equal $resolved.credentialKey 'Host.Example.COM' 'Credential key is the host.'
        Assert-Equal $resolved.dependencyPublishingOption 'Default' 'Default dependency option.'

        $explicit = Get-BaseConfig
        $explicit['port'] = 7100; $explicit['tenant'] = 't9'; $explicit['authentication'] = 'WINDOWS'
        $resolved = (Get-TestSelection -Config $explicit).ResolvedLaunch
        Assert-Equal $resolved.port 7100 'Explicit port.'
        Assert-Equal $resolved.portSource 'launch' 'Explicit port source.'
        Assert-Equal $resolved.tenant 't9' 'Explicit tenant.'
        Assert-Equal $resolved.authentication 'Windows' 'Authentication normalized.'

        $jsonc = New-TestRepo -LaunchJson "{ /* block */ `"configurations`": [ { `"name`": `"cfg`", // line`n `"server`": `"http://h`", `"serverInstance`": `"BC`", `"authentication`": `"Windows`", }, ], }" -LocalJson (New-LocalJson 'Base' 'cfg')
        Assert-Equal (Get-AprodaAlLocalSelection -RepositoryRoot $jsonc).State 'configured' 'launch.json with comments and trailing commas.'
    }

    Invoke-TestCase 'S-2.5 issue codes' {
        $cases = @(
            @{ Code = 'SERVER_INVALID'; Change = { param($c) $c['server'] = 'https://h.example.com/bc' } }
            @{ Code = 'SERVER_INVALID'; Change = { param($c) $c['server'] = 'https://h.example.com:7049' } }
            @{ Code = 'SERVER_INVALID'; Change = { param($c) $c['server'] = 'ftp://h.example.com' } }
            @{ Code = 'INSTANCE_MISSING'; Change = { param($c) $c.Remove('serverInstance') } }
            @{ Code = 'PORT_INVALID'; Change = { param($c) $c['port'] = 'x' } }
            @{ Code = 'PORT_INVALID'; Change = { param($c) $c['port'] = 70000 } }
            @{ Code = 'PORT_INVALID'; Change = { param($c) $c['port'] = 0 } }
            @{ Code = 'PORT_INVALID'; Change = { param($c) $c['port'] = 7049.5 } }
            @{ Code = 'NOT_ONPREM'; Change = { param($c) $c['environmentType'] = 'Sandbox' } }
            @{ Code = 'AUTH_MISSING'; Change = { param($c) $c.Remove('authentication') } }
            @{ Code = 'AUTH_UNSUPPORTED'; Change = { param($c) $c['authentication'] = 'AAD' } }
            @{ Code = 'AUTH_UNSUPPORTED'; Change = { param($c) $c['authentication'] = 'MicrosoftEntraID' } }
            @{ Code = 'AUTH_UNKNOWN'; Change = { param($c) $c['authentication'] = 'Foo' } }
            @{ Code = 'USERPASSWORD_OVER_HTTP'; Change = { param($c) $c['authentication'] = 'UserPassword'; $c['server'] = 'http://h.example.com' } }
            @{ Code = 'DEPENDENCY_OPTION_INVALID'; Change = { param($c) $c['dependencyPublishingOption'] = 'X' } }
        )
        foreach ($case in $cases) {
            $config = Get-BaseConfig
            & $case.Change $config
            $selection = Get-TestSelection -Config $config
            Assert-Equal $selection.State 'configured' "$($case.Code): state stays configured."
            $issues = @($selection.Issues)
            Assert-Equal $issues.Count 1 "$($case.Code): exactly one issue ($((@($issues | ForEach-Object { $_.code })) -join ','))."
            Assert-Equal $issues[0].code $case.Code 'Issue code.'
            Assert-True ($issues[0].message.Contains('launch.json') -and $issues[0].message.Contains("'cfg'")) "$($case.Code): message names file and configuration."
        }
        $valid = Get-BaseConfig
        $valid['dependencyPublishingOption'] = 'Ignore'
        Assert-Equal @((Get-TestSelection -Config $valid).Issues).Count 0 'Valid dependency option.'
    }

    Invoke-TestCase 'S-2.6 Set-AprodaAlLocalSelection' {
        $repo = New-TestRepo
        $path = Join-Path $repo '.github\aldc.local.json'
        $selection = Set-AprodaAlLocalSelection -RepositoryRoot $repo -LaunchProject 'Base' -LaunchConfig 'cfg-win'
        Assert-Equal $selection.State 'configured' 'Returned selection is configured.'
        Assert-Equal ([System.IO.File]::ReadAllText($path)) "{`n  `"version`": 1,`n  `"target`": {`n    `"launchProject`": `"Base`",`n    `"launchConfig`": `"cfg-win`"`n  }`n}`n" 'Exact fresh file content.'
        $bytes = [System.IO.File]::ReadAllBytes($path)
        Assert-True (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'No BOM.'
        Assert-True (-not (Test-Path -LiteralPath "$path.tmp")) 'Temporary file was renamed away.'

        $existing = "{`n  `"note`": { `"keep`": [1, 2] },`n  `"version`": 1,`n  `"target`": { `"launchProject`": `"Base`", `"launchConfig`": `"cfg-up`", `"extra`": true }`n}`n"
        Write-TestFile $path $existing
        $selection = Set-AprodaAlLocalSelection -RepositoryRoot $repo -LaunchProject 'Base' -LaunchConfig 'cfg-win'
        Assert-Equal $selection.Target.LaunchConfig 'cfg-win' 'Selection switched.'
        $written = [System.IO.File]::ReadAllText($path)
        [System.Text.Json.JsonDocument]::Parse($written).Dispose()
        Assert-True (-not $written.Contains("`r")) 'LF only.'
        Assert-True ($written.EndsWith("}`n")) 'Trailing newline.'
        $parsed = $written | ConvertFrom-Json
        Assert-Equal ($parsed.note.keep -join ',') '1,2' 'Unknown top-level key preserved.'
        Assert-Equal $parsed.target.extra $true 'Unknown target key preserved.'
        Assert-Equal $parsed.target.launchConfig 'cfg-win' 'Target replaced.'
        Assert-True ($written.Contains("`n  `"note`": {")) '2-space indentation.'

        $before = [System.IO.File]::ReadAllBytes($path)
        Assert-Throws { Set-AprodaAlLocalSelection -RepositoryRoot $repo -LaunchProject 'Base' -LaunchConfig 'does-not-exist' } 'SELECTION_WOULD_BE_STALE' 'Stale target refused.'
        Assert-Throws { Set-AprodaAlLocalSelection -RepositoryRoot $repo -LaunchProject '..\x' -LaunchConfig 'cfg-win' } 'SELECTION_WOULD_BE_INVALID' 'Invalid target refused.'
        $after = [System.IO.File]::ReadAllBytes($path)
        Assert-Equal ([Convert]::ToBase64String($after)) ([Convert]::ToBase64String($before)) 'File unchanged after refusals.'
        Assert-True (-not (Test-Path -LiteralPath "$path.tmp")) 'No temporary file after refusal.'

        $noToolkit = New-TestRepo -Toolkit none
        Assert-Throws { Set-AprodaAlLocalSelection -RepositoryRoot $noToolkit -LaunchProject 'Base' -LaunchConfig 'cfg-win' } 'SELECTION_WOULD_BE_NOTOOLKIT' 'No toolkit refused.'
    }

    Invoke-TestCase 'S-2.7 Get-AprodaAlLaunchConfigurations' {
        $baseLaunch = '{ "configurations": [ { "name": "attach-only", "type": "al", "request": "attach" }, { "name": "b1", "server": "http://b.example.com", "serverInstance": "BC", "authentication": "Windows" } ] }'
        $testLaunch = '{ "configurations": [ { "name": "t1", "server": "https://t.example.com", "serverInstance": "BC9" } ] }'
        $repo = New-TestRepo -LaunchJson $baseLaunch -Projects @('Base', 'Test')
        Write-TestFile (Join-Path $repo 'Test\.vscode\launch.json') $testLaunch
        $configurations = @(Get-AprodaAlLaunchConfigurations -RepositoryRoot $repo)
        Assert-Equal $configurations.Count 2 'Only server configurations.'
        Assert-Equal $configurations[0].LaunchProject 'Base' 'First project.'
        Assert-Equal $configurations[0].Name 'b1' 'First name.'
        Assert-Equal $configurations[0].Server 'http://b.example.com' 'First server.'
        Assert-Equal $configurations[0].ServerInstance 'BC' 'First instance.'
        Assert-Equal $configurations[0].Authentication 'Windows' 'First authentication.'
        Assert-Equal $configurations[1].LaunchProject 'Test' 'Second project.'
        Assert-Null $configurations[1].Authentication 'Missing authentication stays null.'
    }

    Invoke-TestCase 'S-2.8 Get-AprodaAlProjects' {
        $repo = New-TestRepo -Projects @('Base', 'Test') -LaunchJson $null
        Write-TestFile (Join-Path $repo 'x\y\app.json') '{}'
        New-Item -ItemType Directory -Path (Join-Path $repo 'Docs') -Force | Out-Null
        $projects = @(Get-AprodaAlProjects -RepositoryRoot $repo)
        Assert-Equal (($projects | ForEach-Object { $_.Name }) -join ',') 'Base,Test' 'Direct sub-folders with app.json only.'
        Assert-Equal $projects[0].Path (Join-Path $repo 'Base') 'Project path.'
        Write-TestFile (Join-Path $repo 'alpha\app.json') '{}'
        Write-TestFile (Join-Path $repo 'Zeta\app.json') '{}'
        $projects = @(Get-AprodaAlProjects -RepositoryRoot $repo)
        Assert-Equal (($projects | ForEach-Object { $_.Name }) -join ',') 'Base,Test,Zeta,alpha' 'Ordinal order.'
    }

    Invoke-TestCase 'S-2.9 Find-AprodaAlTool' {
        # Explicit active-extension path
        $explicitRoot = New-TestFolder 'explicit'
        $binExt = New-FakeExtension -Root $explicitRoot -Name 'ms-dynamics-smb.al-18.1.43' -Layout 'bin'
        $found = Find-AprodaAlTool -AlExtensionPath $binExt
        Assert-Equal $found.Path (Join-Path $binExt 'bin\altool.exe') 'bin layout.'
        Assert-Equal $found.Source 'parameter' 'Source parameter.'
        Assert-Equal $found.Version '18.1.43' 'Version from folder name.'
        Assert-Equal (Find-AprodaAlTool -AlExtensionPath $binExt -AlExtensionVersion '18.9.9').Version '18.9.9' 'Version from parameter.'
        $winExt = New-FakeExtension -Root $explicitRoot -Name 'ms-dynamics-smb.al-18.0.41' -Layout 'win32'
        Assert-Equal (Find-AprodaAlTool -AlExtensionPath $winExt).Path (Join-Path $winExt 'bin\win32\altool.exe') 'win32 layout.'
        $emptyExt = New-FakeExtension -Root $explicitRoot -Name 'ms-dynamics-smb.al-18.2.1' -Layout 'none'
        $validRoot = New-TestFolder 'valid-root'
        [void](New-FakeExtension -Root $validRoot -Name 'ms-dynamics-smb.al-19.0.1' -Layout 'bin')
        Assert-Throws { Find-AprodaAlTool -AlExtensionPath $emptyExt -ExtensionsRoot $validRoot } 'ALTOOL_NOT_IN_ACTIVE_EXTENSION' 'Active extension is authoritative, no search.'

        # Numeric ranking; LastWriteTime ignored
        $rankRoot = New-TestFolder 'rank'
        $d1 = New-FakeExtension -Root $rankRoot -Name 'ms-dynamics-smb.al-18.0.41' -Layout 'bin'
        [void](New-FakeExtension -Root $rankRoot -Name 'ms-dynamics-smb.al-18.1.43' -Layout 'bin')
        $d3 = New-FakeExtension -Root $rankRoot -Name 'ms-dynamics-smb.al-18.10.1' -Layout 'bin'
        (Get-Item -LiteralPath $d3).LastWriteTimeUtc = [datetime]'2020-01-01'
        (Get-Item -LiteralPath $d1).LastWriteTimeUtc = [datetime]'2026-10-01'
        $found = Find-AprodaAlTool -ExtensionsRoot $rankRoot
        Assert-Equal $found.Version '18.10.1' 'Numeric ranking, timestamp ignored.'
        Assert-Equal $found.Source 'extension' 'Source extension.'
        Assert-Equal $found.Path (Join-Path $d3 'bin\altool.exe') 'Winning path.'

        # .obsolete excludes the highest (only value true counts)
        Write-TestFile (Join-Path $rankRoot '.obsolete') '{ "ms-dynamics-smb.al-18.10.1": true, "ms-dynamics-smb.al-18.1.43": false }'
        Assert-Equal (Find-AprodaAlTool -ExtensionsRoot $rankRoot).Version '18.1.43' '.obsolete excludes the highest.'

        # Unparsable folder name
        $badRoot = New-TestFolder 'bad'
        [void](New-FakeExtension -Root $badRoot -Name 'ms-dynamics-smb.al-18.1.43' -Layout 'bin')
        [void](New-FakeExtension -Root $badRoot -Name 'ms-dynamics-smb.al-foo' -Layout 'bin')
        Assert-Throws { Find-AprodaAlTool -ExtensionsRoot $badRoot } 'ALTOOL_UNPARSABLE_VERSION' 'Unparsable version stops.'

        # Tie between plain and platform folder
        $tieRoot = New-TestFolder 'tie'
        [void](New-FakeExtension -Root $tieRoot -Name 'ms-dynamics-smb.al-18.1.43' -Layout 'bin')
        [void](New-FakeExtension -Root $tieRoot -Name 'ms-dynamics-smb.al-18.1.43-win32-x64' -Layout 'bin')
        Assert-Throws { Find-AprodaAlTool -ExtensionsRoot $tieRoot } 'ALTOOL_AMBIGUOUS' 'Same version twice.'
        $platformRoot = New-TestFolder 'platform'
        [void](New-FakeExtension -Root $platformRoot -Name 'ms-dynamics-smb.al-18.1.43-win32-x64' -Layout 'win32')
        Assert-Equal (Find-AprodaAlTool -ExtensionsRoot $platformRoot).Version '18.1.43' 'Platform suffix accepted.'

        # Folder without binary
        $missingRoot = New-TestFolder 'missing'
        [void](New-FakeExtension -Root $missingRoot -Name 'ms-dynamics-smb.al-18.1.43' -Layout 'none')
        Assert-Throws { Find-AprodaAlTool -ExtensionsRoot $missingRoot } 'ALTOOL_MISSING_IN_EXTENSION' 'Folder without altool.exe.'

        # dotnet tool fallback and nothing found (PATH restricted to temp folders)
        $emptyRoot = New-TestFolder 'empty'
        $toolBin = New-TestFolder 'toolbin'
        Write-TestFile (Join-Path $toolBin 'al.exe') ''
        $noToolBin = New-TestFolder 'notoolbin'
        try {
            $env:PATH = $toolBin
            $found = Find-AprodaAlTool -ExtensionsRoot $emptyRoot
            Assert-Equal $found.Source 'dotnetTool' 'dotnet tool source.'
            Assert-Null $found.Version 'dotnet tool has no version.'
            Assert-Equal @($found.Warnings).Count 1 'One warning.'
            Assert-Equal @($found.Warnings)[0].code 'ALTOOL_FALLBACK_DOTNET_TOOL' 'Warning code.'
            $env:PATH = $noToolBin
            Assert-Throws { Find-AprodaAlTool -ExtensionsRoot (Join-Path $emptyRoot 'does-not-exist') } 'ALTOOL_NOT_FOUND' 'Nothing found.'
        }
        finally { $env:PATH = $originalPath }
    }

    Invoke-TestCase 'S-2.10 Get-AprodaAlTargetBundle' {
        $good = Get-AprodaAlLocalSelection -RepositoryRoot (New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-up'))
        $bundle = Get-AprodaAlTargetBundle -Selection $good
        Assert-Equal (@($bundle.PSObject.Properties.Name) -join ',') 'ServerUrl,ServerInstance,Port,Authentication,Tenant' 'Five bundle fields.'
        Assert-Equal $bundle.ServerUrl 'https://dev.example.com' 'ServerUrl.'
        Assert-Equal $bundle.ServerInstance 'BC2' 'ServerInstance.'
        Assert-Equal $bundle.Port 7050 'Port.'
        Assert-Equal $bundle.Authentication 'UserPassword' 'Authentication.'
        Assert-Equal $bundle.Tenant 'default' 'Tenant.'

        $blocked = Get-AprodaAlLocalSelection -RepositoryRoot (New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-noauth'))
        Assert-Throws { Get-AprodaAlTargetBundle -Selection $blocked } 'TARGET_BLOCKED:' 'Blocked selection.'
        $blockedMessage = ''
        try { Get-AprodaAlTargetBundle -Selection $blocked | Out-Null } catch { $blockedMessage = $_.Exception.Message }
        Assert-True $blockedMessage.Contains('AUTH_MISSING') 'Blocked message lists the codes.'

        $stale = Get-AprodaAlLocalSelection -RepositoryRoot (New-TestRepo -LocalJson (New-LocalJson 'Base' 'nope'))
        Assert-Throws { Get-AprodaAlTargetBundle -Selection $stale } 'TARGET_NOT_CONFIGURED' 'Stale selection.'
        Assert-Throws { Get-AprodaAlTargetBundle -Selection $null } 'TARGET_NOT_CONFIGURED' 'No selection.'
    }

    Invoke-TestCase 'S-2.11 Test-AprodaAlFirstConfiguration' {
        $repo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-win')
        $first = Get-AprodaAlLocalSelection -RepositoryRoot $repo
        Assert-Equal @(Test-AprodaAlFirstConfiguration -RepositoryRoot $repo -Selection $first).Count 0 'Selection = first configuration: no warning.'

        $secondRepo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-up')
        $second = Get-AprodaAlLocalSelection -RepositoryRoot $secondRepo
        $warnings = @(Test-AprodaAlFirstConfiguration -RepositoryRoot $secondRepo -Selection $second)
        Assert-Equal $warnings.Count 1 'Selection = second configuration: one warning.'
        Assert-Equal $warnings[0].code 'FIRST_CONFIG_DIFFERS' 'Warning code.'
        Assert-Equal $warnings[0].project 'Base' 'Warning names the project.'
        Assert-True ($warnings[0].message.Contains('authentication') -and $warnings[0].message.Contains('server')) 'Warning lists differences.'

        $stale = Get-AprodaAlLocalSelection -RepositoryRoot (New-TestRepo -LocalJson (New-LocalJson 'Base' 'nope'))
        Assert-Equal @(Test-AprodaAlFirstConfiguration -RepositoryRoot $secondRepo -Selection $stale).Count 0 'Unconfigured selection: nothing to compare.'
    }

    Invoke-TestCase 'S-2.12 Update-AprodaAlPackageCache' {
        $repo = New-TestFolder 'cache'
        $source = Join-Path $repo 'Base\.output\Aproda_Base_25.0.0.158.app'
        Write-TestFile $source 'NEW'
        $packages = Join-Path $repo 'Test\.alpackages'
        Write-TestFile (Join-Path $packages 'Aproda_Base_25.0.0.150.app') 'OLD1'
        Write-TestFile (Join-Path $packages 'Aproda_Base_25.0.0.156.app') 'OLD2'
        Write-TestFile (Join-Path $packages 'Microsoft_System Application_28.0.0.0.app') 'SYSTEM'
        Write-TestFile (Join-Path $packages 'Aproda_Base_Plus_1.0.0.0.app') 'OTHER'
        $result = Update-AprodaAlPackageCache -SourceAppFile $source -TargetProjectDir (Join-Path $repo 'Test')
        $names = (@(Get-ChildItem -LiteralPath $packages -File | ForEach-Object { $_.Name }) | Sort-Object) -join ','
        Assert-Equal $names 'Aproda_Base_25.0.0.158.app,Aproda_Base_Plus_1.0.0.0.app,Microsoft_System Application_28.0.0.0.app' 'Only the Base files were replaced.'
        Assert-Equal ([System.IO.File]::ReadAllText((Join-Path $packages 'Aproda_Base_25.0.0.158.app'))) 'NEW' 'Fresh file copied.'
        Assert-Equal ([System.IO.File]::ReadAllText((Join-Path $packages 'Aproda_Base_Plus_1.0.0.0.app'))) 'OTHER' 'Similar-named app kept.'
        Assert-Equal @($result.Removed).Count 2 'Two old files removed.'

        Write-TestFile $source 'NEWER'
        Update-AprodaAlPackageCache -SourceAppFile $source -TargetProjectDir (Join-Path $repo 'Test') | Out-Null
        Assert-Equal ([System.IO.File]::ReadAllText((Join-Path $packages 'Aproda_Base_25.0.0.158.app'))) 'NEWER' 'Same version is overwritten.'
        New-Item -ItemType Directory -Path (Join-Path $repo 'NoPackages') -Force | Out-Null
        Update-AprodaAlPackageCache -SourceAppFile $source -TargetProjectDir (Join-Path $repo 'NoPackages') | Out-Null
        Assert-True (Test-Path -LiteralPath (Join-Path $repo 'NoPackages\.alpackages\Aproda_Base_25.0.0.158.app')) '.alpackages created when missing.'
        Assert-Throws { Update-AprodaAlPackageCache -SourceAppFile (Join-Path $repo 'missing.app') -TargetProjectDir (Join-Path $repo 'Test') } 'SOURCE_APP_NOT_FOUND' 'Missing source.'
    }

    # Starter tests: credentials live in temp LOCALAPPDATA folders, never in the real store.
    $credentialRoot = New-TestFolder 'cred-with'
    $noCredentialRoot = New-TestFolder 'cred-without'
    $passwordMarker = 'PWD-MARKER-7f3a9c'
    $userMarker = 'USR-MARKER-1c2d4e'
    try {
        $env:LOCALAPPDATA = $credentialRoot
        Save-FkhCredential -Key 'dev.example.com' -Credential ([pscredential]::new($userMarker, (ConvertTo-SecureString $passwordMarker -AsPlainText -Force)))
    }
    finally { $env:LOCALAPPDATA = $originalLocalAppData }
    $fakeExtensionRoot = New-TestFolder 'starter-ext'
    $starterExtension = New-FakeExtension -Root $fakeExtensionRoot -Name 'ms-dynamics-smb.al-18.1.43' -Layout 'bin'

    Invoke-TestCase 'S-2.13 starter dry run per mode' {
        $windowsRepo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-win')
        $run = Invoke-StarterProcess -Repo $windowsRepo -AlExtensionPath $starterExtension -Environment @{ LOCALAPPDATA = $noCredentialRoot }
        Assert-Equal $run.ExitCode 0 "Windows target exit code. stderr: $($run.Stderr)"
        Assert-Equal $run.Stdout '' 'Windows target: stdout is empty.'
        $plan = Get-StarterPlan $run.Stderr
        Assert-Equal $plan.mode 'target' 'Windows target mode.'
        Assert-Equal @($plan.reasons).Count 0 'Windows target has no reasons.'
        Assert-Equal ((@($plan.envNames)) -join ',') 'BC_SERVER_INSTANCE,BC_SERVER_PORT,BC_SERVER_URL' 'Windows target env names.'
        Assert-Equal $plan.altool.source 'parameter' 'altool source.'
        Assert-Equal $plan.altool.version '18.1.43' 'altool version.'
        Assert-Equal (@($plan.projects) -join ',') (Join-Path $windowsRepo 'Base') 'Projects.'

        $passwordRepo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-up')
        $run = Invoke-StarterProcess -Repo $passwordRepo -AlExtensionPath $starterExtension -Environment @{ LOCALAPPDATA = $credentialRoot }
        Assert-Equal $run.ExitCode 0 "UserPassword exit code. stderr: $($run.Stderr)"
        Assert-Equal $run.Stdout '' 'UserPassword: stdout is empty.'
        $plan = Get-StarterPlan $run.Stderr
        Assert-Equal $plan.mode 'target' 'UserPassword target mode.'
        Assert-Equal ((@($plan.envNames)) -join ',') 'BC_SERVER_INSTANCE,BC_SERVER_PASSWORD,BC_SERVER_PORT,BC_SERVER_URL,BC_SERVER_USERNAME' 'UserPassword env names.'
        Assert-True $run.Stderr.Contains('WARN FIRST_CONFIG_DIFFERS Base') 'First configuration warning logged.'

        $run = Invoke-StarterProcess -Repo $passwordRepo -AlExtensionPath $starterExtension -Environment @{ LOCALAPPDATA = $noCredentialRoot }
        Assert-Equal $run.ExitCode 0 'Credential missing exit code.'
        Assert-Equal $run.Stdout '' 'Credential missing: stdout is empty.'
        $plan = Get-StarterPlan $run.Stderr
        Assert-Equal $plan.mode 'buildOnly' 'Credential missing mode.'
        Assert-Equal (@($plan.reasons) -join ',') 'CREDENTIAL_MISSING' 'Credential missing reason.'
        Assert-Equal @($plan.envNames).Count 0 'Credential missing: no target environment.'
        Assert-True $run.Stderr.Contains('[al-mcp-starter] WARN CREDENTIAL_MISSING dev.example.com') 'Credential missing log line.'

        $absentRepo = New-TestRepo
        $run = Invoke-StarterProcess -Repo $absentRepo -AlExtensionPath $starterExtension
        Assert-Equal $run.Stdout '' 'Selection absent: stdout is empty.'
        $plan = Get-StarterPlan $run.Stderr
        Assert-Equal $plan.mode 'buildOnly' 'Selection absent mode.'
        Assert-Equal (@($plan.reasons) -join ',') 'SELECTION_ABSENT' 'Selection absent reason.'

        $noToolkitRepo = New-TestRepo -Toolkit none
        $plan = Get-StarterPlan (Invoke-StarterProcess -Repo $noToolkitRepo -AlExtensionPath $starterExtension).Stderr
        Assert-Equal (@($plan.reasons) -join ',') 'SELECTION_NOTOOLKIT' 'noToolkit reason.'

        $blockedRepo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-noauth')
        $run = Invoke-StarterProcess -Repo $blockedRepo -AlExtensionPath $starterExtension
        Assert-Equal $run.Stdout '' 'Blocked: stdout is empty.'
        $plan = Get-StarterPlan $run.Stderr
        Assert-Equal $plan.mode 'buildOnly' 'Blocked mode.'
        Assert-Equal (@($plan.reasons) -join ',') 'TARGET_BLOCKED' 'Blocked reason.'
        Assert-True $run.Stderr.Contains('WARN TARGET_BLOCKED AUTH_MISSING') 'Blocked log line.'
    }

    Invoke-TestCase 'S-2.14 inherited target environment is removed' {
        $inherited = @{
            LOCALAPPDATA       = $noCredentialRoot
            BC_SERVER_URL      = 'http://inherited.example.com'
            BC_SERVER_PASSWORD = 'inherited-secret-marker'
            BC_SERVER_USERNAME = 'inherited-user'
            BC_ACCESS_TOKEN    = 'inherited-token'
        }
        $buildOnlyRepo = New-TestRepo
        $run = Invoke-StarterProcess -Repo $buildOnlyRepo -AlExtensionPath $starterExtension -Environment $inherited
        Assert-Equal $run.Stdout '' 'buildOnly: stdout is empty.'
        $plan = Get-StarterPlan $run.Stderr
        Assert-Equal $plan.mode 'buildOnly' 'Mode.'
        Assert-Equal @($plan.envNames).Count 0 'Inherited values removed in buildOnly.'
        Assert-True (-not $run.Stderr.Contains('inherited-secret-marker')) 'Inherited secret not logged.'

        $windowsRepo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-win')
        $plan = Get-StarterPlan (Invoke-StarterProcess -Repo $windowsRepo -AlExtensionPath $starterExtension -Environment $inherited).Stderr
        Assert-Equal ((@($plan.envNames)) -join ',') 'BC_SERVER_INSTANCE,BC_SERVER_PORT,BC_SERVER_URL' 'Windows target does not keep inherited credentials or token.'
    }

    Invoke-TestCase 'S-2.15 starter exit codes (exit 5 not automated)' {
        $noProjectRepo = New-TestRepo -Projects @() -LaunchJson $null
        $run = Invoke-StarterProcess -Repo $noProjectRepo -AlExtensionPath $starterExtension
        Assert-Equal $run.ExitCode 4 'No AL project exit code.'
        Assert-Equal $run.Stdout '' 'No AL project: stdout is empty.'
        Assert-True $run.Stderr.Contains('[al-mcp-starter] ERROR NO_AL_PROJECT') 'No AL project log line.'

        $repo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-win')
        $emptyExtension = New-FakeExtension -Root (New-TestFolder 'noalt') -Name 'ms-dynamics-smb.al-18.1.43' -Layout 'none'
        $run = Invoke-StarterProcess -Repo $repo -AlExtensionPath $emptyExtension
        Assert-Equal $run.ExitCode 3 'No altool exit code.'
        Assert-Equal $run.Stdout '' 'No altool: stdout is empty.'
        Assert-True $run.Stderr.Contains('[al-mcp-starter] ERROR ALTOOL_NOT_IN_ACTIVE_EXTENSION') 'No altool log line.'

        $wrongSkill = Join-Path (New-TestFolder 'noskill') 'skill-aproda-al-mcp'
        New-Item -ItemType Directory -Path $wrongSkill -Force | Out-Null
        $run = Invoke-StarterProcess -Repo $repo -AlExtensionPath $starterExtension -Skill $wrongSkill
        Assert-Equal $run.ExitCode 6 'Library path wrong exit code.'
        Assert-Equal $run.Stdout '' 'Library path wrong: stdout is empty.'
        Assert-True $run.Stderr.Contains('[al-mcp-starter] ERROR LIBRARY_LOAD_FAILED') 'Library load log line.'
    }

    Invoke-TestCase 'S-2.16 no secret leaves the starter' {
        $repo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-up')
        $run = Invoke-StarterProcess -Repo $repo -AlExtensionPath $starterExtension -Environment @{ LOCALAPPDATA = $credentialRoot }
        $plan = Get-StarterPlan $run.Stderr
        Assert-Equal $plan.mode 'target' 'The credential was really loaded.'
        Assert-True ((@($plan.envNames)) -contains 'BC_SERVER_PASSWORD') 'Password variable was set.'
        foreach ($marker in @($passwordMarker, $userMarker)) {
            Assert-True (-not $run.Stdout.Contains($marker)) "Marker '$marker' in stdout."
            Assert-True (-not $run.Stderr.Contains($marker)) "Marker '$marker' in stderr."
        }
        Assert-Equal $run.Stdout '' 'stdout is empty.'
    }

    Invoke-TestCase 'S-2.17 library functions are silent' {
        $repo = New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-win') -Projects @('Base', 'Test')
        Write-TestFile (Join-Path $repo 'Test\.vscode\launch.json') $validLaunch
        $selection = Get-AprodaAlLocalSelection -RepositoryRoot $repo
        $app = Join-Path $repo 'Base\Aproda_Base_1.0.0.0.app'
        Write-TestFile $app 'APP'
        $extensionRoot = New-TestFolder 'silent-ext'
        [void](New-FakeExtension -Root $extensionRoot -Name 'ms-dynamics-smb.al-18.1.43' -Layout 'bin')
        $toolBin = New-TestFolder 'silent-bin'
        Write-TestFile (Join-Path $toolBin 'al.exe') ''
        $calls = [ordered]@{
            'Get-AprodaAlRepositoryRoot'         = { Get-AprodaAlRepositoryRoot -StartPath $repo }
            'Get-AprodaAlLocalSelectionPath'     = { Get-AprodaAlLocalSelectionPath -RepositoryRoot $repo }
            'Get-AprodaAlLocalSelection'         = { Get-AprodaAlLocalSelection -RepositoryRoot $repo }
            'Get-AprodaAlLocalSelection (stale)' = { Get-AprodaAlLocalSelection -RepositoryRoot (New-TestRepo -LocalJson (New-LocalJson 'Base' 'nope')) }
            'Set-AprodaAlLocalSelection'         = { Set-AprodaAlLocalSelection -RepositoryRoot $repo -LaunchProject 'Base' -LaunchConfig 'cfg-win' }
            'Get-AprodaAlLaunchConfigurations'   = { Get-AprodaAlLaunchConfigurations -RepositoryRoot $repo }
            'Get-AprodaAlProjects'               = { Get-AprodaAlProjects -RepositoryRoot $repo }
            'Get-AprodaAlTargetBundle'           = { Get-AprodaAlTargetBundle -Selection $selection }
            'Find-AprodaAlTool (extension)'      = { Find-AprodaAlTool -ExtensionsRoot $extensionRoot }
            'Find-AprodaAlTool (dotnet tool)'    = { $env:PATH = $toolBin; try { Find-AprodaAlTool -ExtensionsRoot (Join-Path $extensionRoot 'none') } finally { $env:PATH = $originalPath } }
            'Test-AprodaAlFirstConfiguration'    = { Test-AprodaAlFirstConfiguration -RepositoryRoot $repo -Selection (Get-AprodaAlLocalSelection -RepositoryRoot (New-TestRepo -LocalJson (New-LocalJson 'Base' 'cfg-up'))) }
            'Update-AprodaAlPackageCache'        = { Update-AprodaAlPackageCache -SourceAppFile $app -TargetProjectDir (Join-Path $repo 'Test') }
        }
        foreach ($name in $calls.Keys) {
            $captured = @(& $calls[$name] *>&1)
            foreach ($item in $captured) {
                $isStreamRecord = ($item -is [System.Management.Automation.ErrorRecord]) -or ($item -is [System.Management.Automation.WarningRecord]) -or
                ($item -is [System.Management.Automation.InformationRecord]) -or ($item -is [System.Management.Automation.VerboseRecord]) -or
                ($item -is [System.Management.Automation.DebugRecord])
                Assert-True (-not $isStreamRecord) "$name wrote to a stream: $item"
            }
        }
    }

    if ($script:failed.Count -gt 0) {
        throw "FAIL: $($script:failed.Count) of $($script:passed + $script:failed.Count) test case(s) failed: $($script:failed -join '; ')"
    }
    Write-Host "PASS: $script:passed AL MCP target test case(s), 0 failed."
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:PATH = $originalPath
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
