$repositoryRoot = $env:APRODA_TEST_REPOSITORY_ROOT
if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$credentialStorePath = Join-Path $repositoryRoot 'skills\skill-aproda-fkh\scripts\FkhCredentialStore.ps1'
$enginePath = Join-Path $repositoryRoot 'skills\skill-aproda-deploy-run-verify\scripts\AprodaDeployRunVerify.psm1'
$templatePath = Join-Path $repositoryRoot 'skills\skill-aproda-deploy-run-verify\scripts\deploy-run-verify.config.template.jsonc'
$fixturesRoot = Join-Path $repositoryRoot 'tests\fixtures\al-target'
$testStoreRoot = Join-Path $env:TEMP ('aproda-fkh-tests-' + [guid]::NewGuid().ToString('N'))
$drvTempRoot = Join-Path $env:TEMP ('aproda-drv-tests-' + [guid]::NewGuid().ToString('N'))
$originalLocalAppData = $env:LOCALAPPDATA
$originalEngineModule = $env:APRODA_DEPLOY_RUN_VERIFY_MODULE

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-Null {
    param($Actual, [string]$Message)
    if ($null -ne $Actual) { throw "$Message Expected `$null, got '$Actual'." }
}

function Assert-Contains {
    param($Collection, $Expected, [string]$Message)
    if ($Collection -notcontains $Expected) { throw "$Message Expected collection to contain '$Expected'." }
}

function Assert-True {
    param($Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    # Returns the message so callers can add content assertions; the code prefix is matched ordinal.
    param([scriptblock]$Action, [string]$CodePrefix, [string]$Message)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught) { throw "$Message Expected an error starting with '$CodePrefix' but nothing was thrown." }
    if (-not $caught.StartsWith($CodePrefix, [System.StringComparison]::Ordinal)) { throw "$Message Expected an error starting with '$CodePrefix', got '$caught'." }
    return $caught
}

function Invoke-Captured {
    # Runs the action with the Information (Write-Host) and Warning streams collected.
    param([scriptblock]$Action)
    $all = @(& $Action *>&1)
    [pscustomobject]@{
        Result   = @($all | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
        Info     = @($all | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" })
        Warnings = @($all | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
    }
}

function New-DrvTestRepo {
    # Copies a phase-2 fixture into a temp git repo and writes a DRV config next to its Base project.
    param([Parameter(Mandatory)][string]$Fixture, [System.Collections.IDictionary]$ConfigExtra = @{}, [string]$LaunchJson)
    $repo = Join-Path $drvTempRoot ($Fixture + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Copy-Item -LiteralPath (Join-Path $fixturesRoot $Fixture) -Destination $repo -Recurse
    New-Item -ItemType Directory -Path (Join-Path $repo '.git') -Force | Out-Null
    $appJson = '{ "id": "11111111-1111-1111-1111-111111111111", "name": "Base", "publisher": "Fixture", "version": "1.0.0.0", "idRanges": [ { "from": 59000, "to": 59003 } ] }'
    [System.IO.File]::WriteAllText((Join-Path $repo 'Base\app.json'), $appJson)
    if ($LaunchJson) { [System.IO.File]::WriteAllText((Join-Path $repo 'Base\.vscode\launch.json'), $LaunchJson) }
    $config = [ordered]@{
        appsInOrder = @('.'); runnerDir = '.\_runner'; alcPath = 'C:\fake\alc.exe'; companyName = ''
        testCodeunitRange = '59000..59003'; testSuite = 'DEFAULT'; runTimeoutMs = 1000
    }
    foreach ($key in $ConfigExtra.Keys) { $config[$key] = $ConfigExtra[$key] }
    $configPath = Join-Path $repo 'Base\deploy-run-verify.config.jsonc'
    [System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5))
    return $configPath
}

function Resolve-DrvTarget {
    param([string]$Fixture, [System.Collections.IDictionary]$ConfigExtra = @{}, [switch]$BuildOnly, [string]$LaunchJson)
    $configPath = New-DrvTestRepo -Fixture $Fixture -ConfigExtra $ConfigExtra -LaunchJson $LaunchJson
    return (Invoke-Captured { Resolve-DeployRunVerifyConfig -ConfigPath $configPath -BuildOnly:$BuildOnly })
}

$script:passed = 0
function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Test)
    & $Test
    $script:passed++
    Write-Host "PASS: $Name"
}

try {
    $env:LOCALAPPDATA = $testStoreRoot
    . ([scriptblock]::Create((Get-Content -LiteralPath $credentialStorePath -Raw)))

    Invoke-TestCase 'credential store isolates host keys' {
        $firstCredential = [pscredential]::new('first-user', (ConvertTo-SecureString 'test-password-one' -AsPlainText -Force))
        $secondCredential = [pscredential]::new('second-user', (ConvertTo-SecureString 'test-password-two' -AsPlainText -Force))

        Save-FkhCredential -Key 'first.cloudapp.azure.com' -Credential $firstCredential
        Save-FkhCredential -Key 'second.cloudapp.azure.com' -Credential $secondCredential

        Assert-Equal (Get-FkhStoredCredential -Key 'first.cloudapp.azure.com').UserName 'first-user' 'First host credential mismatch.'
        Assert-Equal (Get-FkhStoredCredential -Key 'second.cloudapp.azure.com').UserName 'second-user' 'Second host credential mismatch.'
    }

    Invoke-TestCase 'credential store ignores unreadable content' {
        $key = 'invalid.cloudapp.azure.com'
        $path = Join-Path (Get-FkhCredentialStoreDir) (ConvertTo-FkhCredentialStoreFileName -Key $key)
        Set-Content -LiteralPath $path -Value 'not clixml' -Encoding UTF8

        Assert-Null (Get-FkhStoredCredential -Key $key) 'Unreadable credential content was returned.'
    }

    Invoke-TestCase 'credential store removes a credential' {
        $key = 'remove.cloudapp.azure.com'
        $credential = [pscredential]::new('remove-user', (ConvertTo-SecureString 'test-password-three' -AsPlainText -Force))
        Save-FkhCredential -Key $key -Credential $credential

        Remove-FkhStoredCredential -Key $key

        Assert-Null (Get-FkhStoredCredential -Key $key) 'Removed credential was returned.'
    }

    $engineContent = Get-Content -LiteralPath $enginePath -Raw
    $engineContent = [regex]::Replace($engineContent, '(?s)\r?\nExport-ModuleMember\s+-Function.*\z', '')
    # The engine locates its sibling skills and runner-glue through this hint (empty $PSScriptRoot under iex).
    $env:APRODA_DEPLOY_RUN_VERIFY_MODULE = $enginePath
    . ([scriptblock]::Create($engineContent))

    Invoke-TestCase 'adapter selection requires HTTPS cloudapp target for Fkh' {
        Assert-Equal (Get-DeployRunVerifyAdapter -Cfg ([pscustomobject]@{ scheme = 'https'; server = 'sample.cloudapp.azure.com' })) 'Fkh' 'HTTPS cloudapp target did not select Fkh.'
        Assert-Equal (Get-DeployRunVerifyAdapter -Cfg ([pscustomobject]@{ scheme = 'http'; server = 'sample.cloudapp.azure.com' })) 'Asinst' 'HTTP cloudapp target selected Fkh.'
        Assert-Equal (Get-DeployRunVerifyAdapter -Cfg ([pscustomobject]@{ scheme = 'https'; server = 'sample.example.com' })) 'Asinst' 'Non-cloudapp target selected Fkh.'
    }

    Invoke-TestCase 'XUnit summary counts passed and failed tests' {
        $result = [pscustomobject]@{
            stage = 'ran'
            ok    = $true
            error = ''
            xml   = '<tests><test name="passes" result="Pass"/><test name="fails" result="Fail"/></tests>'
        }

        $summary = Get-DeployRunVerifySummary -ResultObject $result

        Assert-Equal $summary.Stage 'ran' 'Summary stage mismatch.'
        Assert-Equal $summary.Total 2 'Summary total mismatch.'
        Assert-Equal $summary.Passed 1 'Summary passed count mismatch.'
        Assert-Equal $summary.Failed 1 'Summary failed count mismatch.'
        Assert-Contains $summary.Failures 'fails' 'Summary failures mismatch.'
    }

    Invoke-TestCase 'S-4a.1 non-empty migration keys stop with CONFIG_MIGRATION_REQUIRED, fkhSyncMode is accepted' {
        $values = [ordered]@{ launchConfig = 'dev-windows'; server = 'nst-test.example.com'; serverInstance = 'BC'; tenant = 'default'; scheme = 'http'; authentication = 'Windows' }
        foreach ($key in $values.Keys) {
            $configPath = New-DrvTestRepo -Fixture 'case-configured-windows' -ConfigExtra @{ $key = $values[$key] }
            $message = Assert-Throws { Resolve-DeployRunVerifyConfig -ConfigPath $configPath } "CONFIG_MIGRATION_REQUIRED: $key" "Key '$key'."
            Assert-True ($message -like '*deploy-run-verify.config.jsonc*') "Key '$key': message must name the config file."
            Assert-True ($message -like '*aldc.local.json*') "Key '$key': message must name aldc.local.json."
            Assert-True ($message -notmatch "(?m)^CONFIG_MIGRATION_REQUIRED: .*,") "Key '$key': only that key must be listed."
        }
        $configPath = New-DrvTestRepo -Fixture 'case-configured-windows' -ConfigExtra $values
        $message = Assert-Throws { Resolve-DeployRunVerifyConfig -ConfigPath $configPath } 'CONFIG_MIGRATION_REQUIRED: launchConfig,server,serverInstance,tenant,scheme,authentication' 'All keys.'
        Assert-True ($message -like '*delete these lines from*') 'Message must tell what to delete.'

        $fkh = Resolve-DrvTarget -Fixture 'case-configured-windows' -ConfigExtra @{ fkhSyncMode = 'ForceSync' }
        Assert-Equal $fkh.Result[0].fkhSyncMode 'ForceSync' 'fkhSyncMode must stay a normal config key.'
        Assert-Equal @($fkh.Warnings | Where-Object { $_ -like 'CONFIG_OBSOLETE_KEY*' }).Count 0 'fkhSyncMode must not raise CONFIG_OBSOLETE_KEY.'
    }

    Invoke-TestCase 'S-4a.2 empty migration keys only warn with CONFIG_OBSOLETE_KEY' {
        $run = Resolve-DrvTarget -Fixture 'case-configured-windows' -ConfigExtra @{ launchConfig = ''; server = ''; serverInstance = ''; tenant = ''; scheme = ''; authentication = $false }
        $warning = @($run.Warnings | Where-Object { $_ -like 'CONFIG_OBSOLETE_KEY*' })
        Assert-Equal $warning.Count 1 'Expected exactly one CONFIG_OBSOLETE_KEY warning.'
        Assert-True ($warning[0] -like 'CONFIG_OBSOLETE_KEY: launchConfig,server,serverInstance,tenant,scheme,authentication*') 'Warning must list the keys.'
        Assert-Equal $run.Result[0].adapter 'Asinst' 'Resolution must continue.'
        Assert-Equal $run.Result[0].server 'nst-test.example.com' 'The empty key must not win over the selection.'
    }

    Invoke-TestCase 'S-4a.3 absent / invalid / stale / noToolkit selection stops with TARGET_SELECTION_<STATE> and the configuration list' {
        foreach ($case in @(@('case-absent', 'ABSENT'), @('case-invalid-version', 'INVALID'), @('case-stale-missing-config', 'STALE'), @('case-no-toolkit', 'NOTOOLKIT'))) {
            $configPath = New-DrvTestRepo -Fixture $case[0]
            $message = Assert-Throws { Resolve-DeployRunVerifyConfig -ConfigPath $configPath } "TARGET_SELECTION_$($case[1]):" $case[0]
            Assert-True ($message -like '*Available configurations*') "$($case[0]): list header."
            Assert-True ($message -like '*Base | dev-windows | http://nst-test.example.com | BC | Windows*') "$($case[0]): the configuration list must show project, name, server, instance, authentication."
        }
        $configPath = New-DrvTestRepo -Fixture 'case-absent'
        $message = Assert-Throws { Resolve-DeployRunVerifyConfig -ConfigPath $configPath } 'TARGET_SELECTION_ABSENT:' 'Absent.'
        Assert-True ($message -like '*Set-AprodaAlLocalSelection*') 'Absent: message must point at Set-AprodaAlLocalSelection.'
    }

    Invoke-TestCase 'S-4a.4 blocking launch issues stop with TARGET_BLOCKED before any connection (B-2 regression)' {
        $cases = @(@('case-auth-missing', 'AUTH_MISSING'), @('case-userpassword-over-http', 'USERPASSWORD_OVER_HTTP'), @('case-auth-aad', 'AUTH_UNSUPPORTED'))
        foreach ($case in $cases) {
            $configPath = New-DrvTestRepo -Fixture $case[0]
            $message = Assert-Throws { Resolve-DeployRunVerifyConfig -ConfigPath $configPath } "TARGET_BLOCKED: $($case[1])" $case[0]
            Assert-True ($message -like "*$($case[1]): *") "$($case[0]): the issue message must follow the code line."
        }
        $configPath = New-DrvTestRepo -Fixture 'case-auth-missing'
        $message = Assert-Throws { Resolve-DeployRunVerifyConfig -ConfigPath $configPath } 'TARGET_BLOCKED: AUTH_MISSING' 'AUTH_MISSING.'
        Assert-True ($message -like '*authentication is not set*') 'AUTH_MISSING message text.'

        # The orchestrator must stop before the preflight (the only network call) and before the build.
        function Test-DeployRunVerifyPreflight { throw 'PREFLIGHT_WAS_CALLED' }
        function Invoke-DeployRunVerifyBuild { throw 'BUILD_WAS_CALLED' }
        $configPath = New-DrvTestRepo -Fixture 'case-userpassword-over-http'
        Assert-Throws { Invoke-AprodaDeployRunVerify -ConfigPath $configPath } 'TARGET_BLOCKED: USERPASSWORD_OVER_HTTP' 'Orchestrator.' | Out-Null
    }

    Invoke-TestCase 'S-4a.5 configured selection fills the target fields' {
        $windows = (Resolve-DrvTarget -Fixture 'case-configured-windows').Result[0]
        Assert-Equal $windows.server 'nst-test.example.com' 'server must be the host only.'
        Assert-Equal $windows.scheme 'http' 'scheme.'
        Assert-Equal $windows.serverInstance 'BC' 'serverInstance.'
        Assert-Equal $windows.tenant 'default' 'tenant.'
        Assert-Equal $windows.authentication 'Windows' 'authentication.'
        Assert-Equal $windows.port 7049 'port.'
        Assert-Equal $windows.dependencyPublishingOption 'Default' 'dependencyPublishingOption.'
        Assert-Equal $windows.launchProject 'Base' 'launchProject.'
        Assert-Equal $windows.launchConfig 'dev-windows' 'launchConfig.'
        Assert-Equal $windows.adapter 'Asinst' 'adapter.'
        Assert-Equal $windows.serviceUrl 'http://nst-test.example.com/BC/cs/' 'serviceUrl.'
        Assert-Equal $windows.targetBundle.ServerUrl 'http://nst-test.example.com' 'bundle ServerUrl.'

        $userPassword = (Resolve-DrvTarget -Fixture 'case-configured-userpassword-https').Result[0]
        Assert-Equal $userPassword.server 'Dev.Example.COM' 'host case kept.'
        Assert-Equal $userPassword.scheme 'https' 'scheme https.'
        Assert-Equal $userPassword.authentication 'UserPassword' 'authentication normalized.'
        Assert-Equal $userPassword.port 7050 'explicit port.'
        Assert-Equal $userPassword.tenant 't1' 'explicit tenant.'
        Assert-Equal $userPassword.dependencyPublishingOption 'Strict' 'dependency option.'
        Assert-Equal $userPassword.adapter 'Asinst' 'non-cloudapp https host stays Asinst.'

        $fkhLaunch = '{ "configurations": [ { "name": "dev-windows", "type": "al", "request": "launch", "environmentType": "OnPrem", "server": "https://x.cloudapp.azure.com", "serverInstance": "BC", "authentication": "UserPassword" } ] }'
        $fkh = (Resolve-DrvTarget -Fixture 'case-configured-windows' -LaunchJson $fkhLaunch).Result[0]
        Assert-Equal $fkh.adapter 'Fkh' 'https cloudapp host selects Fkh.'
        Assert-Equal $fkh.server 'x.cloudapp.azure.com' 'Fkh host.'
    }

    Invoke-TestCase 'S-4a.6 build-only without a usable target continues with adapter none' {
        foreach ($fixture in 'case-absent', 'case-invalid-version', 'case-stale-missing-config', 'case-no-toolkit') {
            $run = Resolve-DrvTarget -Fixture $fixture -BuildOnly
            Assert-Equal $run.Result[0].adapter 'none' "$fixture adapter."
            Assert-Null $run.Result[0].server "$fixture server."
            Assert-Null $run.Result[0].serviceUrl "$fixture serviceUrl."
            Assert-Contains $run.Info 'TARGET: none (build-only)' "$fixture info line."
            Assert-Equal @($run.Result[0].apps).Count 1 "$fixture apps must still resolve."
        }
        $blocked = Resolve-DrvTarget -Fixture 'case-auth-missing' -BuildOnly
        Assert-Equal $blocked.Result[0].adapter 'none' 'Blocked selection in build-only.'
        Assert-True (@($blocked.Warnings | Where-Object { $_ -like 'TARGET_BLOCKED: AUTH_MISSING*' }).Count -eq 1) 'Blocked selection in build-only must warn.'
        $configured = Resolve-DrvTarget -Fixture 'case-configured-windows' -BuildOnly
        Assert-Equal $configured.Result[0].adapter 'Asinst' 'A configured target stays resolved in build-only.'

        # Orchestrator: no target access, no preflight, build runs, deploy/run skipped.
        function Test-DeployRunVerifyPreflight { throw 'PREFLIGHT_WAS_CALLED' }
        function Invoke-DeployRunVerifyBuild { return $true }
        function Test-DeployRunVerifyTargetDependencies { throw 'DEPENDENCIES_WERE_CHECKED' }
        $configPath = New-DrvTestRepo -Fixture 'case-absent'
        $orchestrated = Invoke-Captured { Invoke-AprodaDeployRunVerify -ConfigPath $configPath -BuildOnly }
        Assert-True ($orchestrated.Result[0].BuildOnly -eq $true) 'Orchestrator must return a BuildOnly result.'
        Assert-Contains $orchestrated.Info 'TARGET: none (build-only)' 'Orchestrator info line.'
        Assert-True (@($orchestrated.Info | Where-Object { $_ -like 'Server *' }).Count -eq 0) 'Orchestrator must not print a Server line without a target.'
        Assert-Throws { Invoke-AprodaDeployRunVerify -ConfigPath $configPath } 'TARGET_SELECTION_ABSENT:' 'Full run without a selection must stop.' | Out-Null
        Assert-Throws { Invoke-AprodaDeployRunVerify -ConfigPath $configPath -SkipBuild } 'TARGET_SELECTION_ABSENT:' 'Skip-build run without a selection must stop.' | Out-Null
    }

    Invoke-TestCase 'S-4a.7 runner version rule is unchanged (B-1 regression)' {
        $runnerBase = Join-Path $drvTempRoot ('runner-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $runnerBase -Force | Out-Null
        function Get-DeployRunVerifyRunnerVersion { param([string]$Dir) if ($Dir -eq $runnerBase) { return '28.0.50938.0' } return $null }
        foreach ($bcVersion in '28.3', '28.3.51234.0', '28.0') {
            $accepted = Invoke-Captured { Resolve-DeployRunVerifyRunner -Cfg ([pscustomobject]@{ runnerDirFull = $runnerBase; bcVersion = $bcVersion; adapter = 'Fkh'; mgmtDllPath = '' }) }
            Assert-Equal $accepted.Result[0] $runnerBase "bcVersion $bcVersion must accept a 28.0.x client DLL."
        }
        $message = Assert-Throws { Resolve-DeployRunVerifyRunner -Cfg ([pscustomobject]@{ runnerDirFull = $runnerBase; bcVersion = '29.0'; adapter = 'Fkh'; mgmtDllPath = '' }) } 'Runner version mismatch' 'bcVersion 29.0.'
        Assert-True ($message -like '*major must match*') 'Mismatch message.'
    }

    Invoke-TestCase 'S-4a.8 missing skill-aproda-al-mcp stops with AL_MCP_SKILL_MISSING' {
        # Engine copy in a tree without the sibling skill, run in a child process so the parent's library functions cannot leak in.
        $isolatedScripts = Join-Path $drvTempRoot 'isolated\skills\skill-aproda-deploy-run-verify\scripts'
        New-Item -ItemType Directory -Path $isolatedScripts -Force | Out-Null
        Copy-Item -LiteralPath $enginePath -Destination $isolatedScripts
        $configPath = New-DrvTestRepo -Fixture 'case-configured-windows'
        $childScript = @'
$ErrorActionPreference = 'Stop'
$src = [regex]::Replace((Get-Content -LiteralPath $env:APRODA_DEPLOY_RUN_VERIFY_MODULE -Raw), '(?s)\r?\nExport-ModuleMember\s+-Function.*\z', '')
. ([scriptblock]::Create($src))
try { Resolve-DeployRunVerifyConfig -ConfigPath $env:DRV_TEST_CONFIG | Out-Null; 'NO-ERROR' } catch { $_.Exception.Message }
'@
        $previousModule = $env:APRODA_DEPLOY_RUN_VERIFY_MODULE
        try {
            $env:APRODA_DEPLOY_RUN_VERIFY_MODULE = Join-Path $isolatedScripts 'AprodaDeployRunVerify.psm1'
            $env:DRV_TEST_CONFIG = $configPath
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($childScript))
            $childOutput = (& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String).Trim()
        }
        finally {
            $env:APRODA_DEPLOY_RUN_VERIFY_MODULE = $previousModule
            Remove-Item Env:\DRV_TEST_CONFIG -ErrorAction SilentlyContinue
        }
        Assert-True ($childOutput.StartsWith('AL_MCP_SKILL_MISSING:')) "Expected AL_MCP_SKILL_MISSING, got '$childOutput'."
        Assert-True ($childOutput -like '*skill-aproda-al-mcp*') 'Message must name the missing skill.'
    }

    Invoke-TestCase 'S-4a.9 template carries no target key' {
        $templateText = [regex]::Replace((Get-Content -LiteralPath $templatePath -Raw), '(?m)(?<!:)//.*?$', '')
        $template = $templateText | ConvertFrom-Json
        foreach ($key in 'launchConfig', 'server', 'serverInstance', 'tenant', 'scheme', 'authentication') {
            Assert-True ($null -eq $template.PSObject.Properties[$key]) "Template must not contain '$key'."
        }
        Assert-True ($null -ne $template.PSObject.Properties['fkhSyncMode']) 'Template keeps fkhSyncMode.'
    }

    # ---------------------------------------------------------------------------------------------
    # Phase 4b - routes, classification, publish, test route, cleanup (E-010 spec 6)
    # ---------------------------------------------------------------------------------------------
    $altoolFixtures = Join-Path $repositoryRoot 'tests\fixtures\altool'
    $pwshPath = (Get-Process -Id $PID).Path
    $middleDot = [string][char]0x00B7
    $rightArrow = [string][char]0x2192

    function Get-AlToolFixture { param([string]$Name) return (Get-Content -LiteralPath (Join-Path $altoolFixtures $Name) -Raw) }

    function New-DrvPublishCfg {
        param([string]$Authentication = 'Windows', [string]$Adapter = 'Asinst', [string]$SyncMode = 'Add', [string]$DeployRoute = 'auto', [string]$Scheme = 'http')
        [pscustomobject]@{
            adapter = $Adapter; authentication = $Authentication; server = 'nst-test.example.com'; fkhSyncMode = $SyncMode; deployRoute = $DeployRoute
            dependencyPublishingOption = 'Default'
            targetBundle = [pscustomobject]@{ ServerUrl = "${Scheme}://nst-test.example.com"; ServerInstance = 'BC'; Port = 7049; Authentication = $Authentication; Tenant = 'default' }
        }
    }

    # Dot-sourced into a test case: mocks for the publish chain (route a, route b, state read, credential).
    $publishMocks = {
        $script:alToolCalls = 0; $script:postCalls = 0; $script:alOutcome = 'Published'; $script:postOutcome = 'Published'
        $script:credentialCalls = 0; $script:resetCalls = 0; $script:stateInstalled = $true
        Reset-DeployRunVerifyRunState
        function Get-DeployRunVerifyAlTool { [pscustomobject]@{ Path = 'C:\fake\altool.exe'; Version = '18.1.43'; Source = 'extension'; Error = $null } }
        function Get-DeployRunVerifyAlToolCapabilities { [pscustomobject]@{ Compile = $true; PublishApp = $true; RunTests = $true; TestGroups = $true } }
        function Invoke-DeployRunVerifyAlToolPublish { $script:alToolCalls++; [pscustomobject]@{ Outcome = $script:alOutcome; Reason = "altool says $($script:alOutcome)" } }
        function Publish-DeployRunVerifyDevEndpoint { $script:postCalls++; [pscustomobject]@{ Outcome = $script:postOutcome; Reason = "post says $($script:postOutcome)"; HttpStatus = 200; Body = '' } }
        function Get-DeployRunVerifyAppState { [pscustomobject]@{ Found = $true; IsInstalled = $script:stateInstalled; SyncState = 'Synced' } }
        function Get-DeployRunVerifyCredential { $script:credentialCalls++; [pscredential]::new('test-user', (ConvertTo-SecureString 'test-pw' -AsPlainText -Force)) }
        function Reset-DeployRunVerifyCredential { $script:resetCalls++ }
    }

    function Start-DrvTestServer {
        # One-request HttpListener on a free loopback port, served from a background runspace (the caller blocks in the POST).
        param([int]$StatusCode = 200, [string]$ResponseBody = 'ok', [int]$WaitMs = 15000)
        $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $tcp.Start(); $port = $tcp.LocalEndpoint.Port; $tcp.Stop()
        $state = [hashtable]::Synchronized(@{ Ready = $false; Request = $null })
        $ps = [powershell]::Create()
        [void]$ps.AddScript({
                param($port, $status, $body, $state, $waitMs)
                $listener = [System.Net.HttpListener]::new()
                $listener.Prefixes.Add("http://127.0.0.1:$port/")
                $listener.Start()
                $state.Ready = $true
                try {
                    $task = $listener.GetContextAsync()
                    if (-not $task.Wait($waitMs)) { return }
                    $context = $task.Result
                    $request = $context.Request
                    $stream = [System.IO.MemoryStream]::new()
                    $request.InputStream.CopyTo($stream)
                    $headers = @{}
                    foreach ($key in $request.Headers.AllKeys) { $headers[$key] = $request.Headers[$key] }
                    $state.Request = @{ Method = $request.HttpMethod; RawUrl = $request.RawUrl; Headers = $headers; Body = [System.Text.Encoding]::Latin1.GetString($stream.ToArray()) }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                    $context.Response.StatusCode = $status
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $context.Response.Close()
                    Start-Sleep -Milliseconds 500
                }
                finally { $listener.Stop(); $listener.Close() }
            }).AddArgument($port).AddArgument($StatusCode).AddArgument($ResponseBody).AddArgument($state).AddArgument($WaitMs)
        $handle = $ps.BeginInvoke()
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not $state.Ready -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
        if (-not $state.Ready) { throw 'Test HTTP listener did not start.' }
        [pscustomobject]@{ Port = $port; State = $state; Ps = $ps; Handle = $handle }
    }

    function Stop-DrvTestServer {
        param($Server)
        [void]$Server.Handle.AsyncWaitHandle.WaitOne(20000)
        try { $Server.Ps.EndInvoke($Server.Handle) | Out-Null } catch { Write-Host "TEST-SERVER-EXCEPTION: $($_.Exception.Message)" }
        foreach ($serverError in @($Server.Ps.Streams.Error)) { Write-Host "TEST-SERVER-ERROR: $serverError" }
        $Server.Ps.Dispose()
    }

    Invoke-TestCase 'S-4b.1 capability parse is localization-proof and reports missing commands' {
        foreach ($language in 'en', 'de') {
            $caps = ConvertFrom-DeployRunVerifyAlToolHelp -MainHelp (Get-AlToolFixture "help-main-$language.txt") -RunTestsHelp (Get-AlToolFixture "help-runtests-$language.txt")
            Assert-True ($caps.Compile -and $caps.PublishApp -and $caps.RunTests -and $caps.TestGroups) "$language help: all four capabilities."
        }
        $noRunTests = ConvertFrom-DeployRunVerifyAlToolHelp -MainHelp (Get-AlToolFixture 'help-main-no-runtests.txt') -RunTestsHelp (Get-AlToolFixture 'help-runtests-en.txt')
        Assert-True ($noRunTests.Compile -and $noRunTests.PublishApp) 'Help without runtests keeps compile/publishapp.'
        Assert-True (-not $noRunTests.RunTests) 'RunTests must be false.'
        Assert-True (-not $noRunTests.TestGroups) 'TestGroups cannot be true without runtests.'
        $noGroups = ConvertFrom-DeployRunVerifyAlToolHelp -MainHelp (Get-AlToolFixture 'help-main-en.txt') -RunTestsHelp (Get-AlToolFixture 'help-runtests-no-testgroups.txt')
        Assert-True ($noGroups.RunTests -and -not $noGroups.TestGroups) 'runtests without --testgroups.'

        # Caching: one --help and one runtests --help per run.
        $script:helpCalls = @()
        $script:helpMain = 'help-main-de.txt'
        function Invoke-DeployRunVerifyAlTool {
            param($AlTool, $Arguments, $Credential, $TimeoutMs)
            $script:helpCalls += , (@($Arguments) -join ' ')
            $text = if ($Arguments[0] -eq '--help') { Get-AlToolFixture $script:helpMain } else { Get-AlToolFixture 'help-runtests-de.txt' }
            [pscustomobject]@{ ExitCode = 0; StdOut = $text; StdErr = ''; DurationMs = 1; TimedOut = $false; LaunchError = $null }
        }
        Reset-DeployRunVerifyRunState
        $tool = [pscustomobject]@{ Path = 'C:\fake\altool.exe' }
        $first = Get-DeployRunVerifyAlToolCapabilities -AlTool $tool
        $second = Get-DeployRunVerifyAlToolCapabilities -AlTool $tool
        Assert-Equal $script:helpCalls.Count 2 'Capability detection must run --help and runtests --help once per run.'
        Assert-True ($first.TestGroups -and $second.TestGroups) 'Cached capabilities.'
        Reset-DeployRunVerifyRunState
        $script:helpCalls = @(); $script:helpMain = 'help-main-no-runtests.txt'
        $limited = Get-DeployRunVerifyAlToolCapabilities -AlTool $tool
        Assert-Equal $script:helpCalls.Count 1 'No runtests command: runtests --help is not called.'
        Assert-True (-not $limited.RunTests) 'RunTests false.'
        # A launch failure yields no capability at all.
        function Invoke-DeployRunVerifyAlTool { param($AlTool, $Arguments, $Credential, $TimeoutMs) [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = ''; DurationMs = 1; TimedOut = $false; LaunchError = 'boom' } }
        Reset-DeployRunVerifyRunState
        $none = Get-DeployRunVerifyAlToolCapabilities -AlTool $tool
        Assert-True (-not ($none.Compile -or $none.PublishApp -or $none.RunTests -or $none.TestGroups)) 'Launch failure: no capability.'
    }

    Invoke-TestCase 'S-4b.2 altool child process receives credentials only through its environment' {
        $tool = [pscustomobject]@{ Path = $pwshPath }
        $probe = '-NoProfile', '-NonInteractive', '-Command', 'Get-ChildItem Env: | Where-Object { $_.Name -like ''BC_SERVER_*'' -or $_.Name -eq ''BC_ACCESS_TOKEN'' } | ForEach-Object { $_.Name }; "USER=$env:BC_SERVER_USERNAME"'
        $previous = @{ Url = $env:BC_SERVER_URL; Token = $env:BC_ACCESS_TOKEN; User = $env:BC_SERVER_USERNAME; Password = $env:BC_SERVER_PASSWORD }
        try {
            $env:BC_SERVER_URL = 'http://inherited.example.com'
            $env:BC_ACCESS_TOKEN = 'inherited-token'
            $without = Invoke-Captured { Invoke-DeployRunVerifyAlTool -AlTool $tool -Arguments $probe -TimeoutMs 60000 }
            $call = $without.Result[0]
            Assert-Equal $call.ExitCode 0 'Probe exit code.'
            Assert-True (-not $call.TimedOut) 'Probe must not time out.'
            $lines = @($call.StdOut -split '\r?\n' | Where-Object { $_ })
            Assert-Equal @($lines | Where-Object { $_ -like 'BC_*' }).Count 0 'Without a credential the child must see no BC_* variable (inherited BC_SERVER_URL and BC_ACCESS_TOKEN removed).'

            $credential = [pscredential]::new('test-user', (ConvertTo-SecureString 'test-secret-pw' -AsPlainText -Force))
            $with = Invoke-Captured { Invoke-DeployRunVerifyAlTool -AlTool $tool -Arguments $probe -Credential $credential -TimeoutMs 60000 }
            $withLines = @($with.Result[0].StdOut -split '\r?\n' | Where-Object { $_ })
            Assert-Contains $withLines 'BC_SERVER_USERNAME' 'Credential: user name variable.'
            Assert-Contains $withLines 'BC_SERVER_PASSWORD' 'Credential: password variable.'
            Assert-Contains $withLines 'USER=test-user' 'The child reads the user name.'
            Assert-Equal @($withLines | Where-Object { $_ -in @('BC_SERVER_URL', 'BC_ACCESS_TOKEN') }).Count 0 'Inherited variables stay removed with a credential.'
            Assert-Equal $env:BC_SERVER_URL 'http://inherited.example.com' 'Parent BC_SERVER_URL must be unchanged.'
            Assert-Equal $env:BC_ACCESS_TOKEN 'inherited-token' 'Parent BC_ACCESS_TOKEN must be unchanged.'
            Assert-Equal $env:BC_SERVER_USERNAME $previous.User 'Parent must not receive the user name.'
            Assert-Equal $env:BC_SERVER_PASSWORD $previous.Password 'Parent must not receive the password.'
            Assert-True (($with.Info -join "`n") -notlike '*test-secret-pw*') 'The password must not be logged.'
            Assert-True ($with.Result[0].StdOut -notlike '*test-secret-pw*') 'The probe must not echo the password.'
        }
        finally {
            $env:BC_SERVER_URL = $previous.Url; $env:BC_ACCESS_TOKEN = $previous.Token
            $env:BC_SERVER_USERNAME = $previous.User; $env:BC_SERVER_PASSWORD = $previous.Password
        }
        $missing = Invoke-DeployRunVerifyAlTool -AlTool ([pscustomobject]@{ Path = (Join-Path $drvTempRoot 'no-such-tool.exe') }) -Arguments @('x') 6>$null
        Assert-True ([bool]$missing.LaunchError) 'A tool that cannot be started reports LaunchError.'
    }

    Invoke-TestCase 'S-4b.3 altool timeout kills the whole process tree' {
        $tool = [pscustomobject]@{ Path = $pwshPath }
        $command = '$g = [System.Diagnostics.Process]::Start((Get-Process -Id $PID).Path, @("-NoProfile","-Command","Start-Sleep -Seconds 60")); [Console]::Out.WriteLine("$PID $($g.Id)"); [Console]::Out.Flush(); Start-Sleep -Seconds 60'
        $call = Invoke-DeployRunVerifyAlTool -AlTool $tool -Arguments @('-NoProfile', '-NonInteractive', '-Command', $command) -TimeoutMs 8000 6>$null
        Assert-True $call.TimedOut 'TimedOut must be true.'
        $pids = @($call.StdOut.Trim() -split '\s+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        Assert-Equal $pids.Count 2 "The probe must report child and grandchild PIDs (got '$($call.StdOut)')."
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while ([DateTime]::UtcNow -lt $deadline -and @($pids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count -gt 0) { Start-Sleep -Milliseconds 100 }
        Assert-Equal @($pids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count 0 'Child and grandchild must be gone.'
    }

    Invoke-TestCase 'S-4b.4 publish outcome classification' {
        $cases = @(
            @('publish-success.txt', 0, 'Published'), @('publish-duplicate.txt', 1, 'Duplicate'), @('publish-auth.txt', 1, 'AuthFailure'),
            @('publish-rejected-sync.txt', 1, 'Rejected'), @('publish-connection-refused.txt', 1, 'InvocationFailure'))
        foreach ($case in $cases) {
            $outcome = Get-DeployRunVerifyPublishOutcome -ExitCode $case[1] -Output (Get-AlToolFixture $case[0])
            Assert-Equal $outcome.Outcome $case[2] "Fixture $($case[0])."
        }
        foreach ($http in @(@(200, 'Published'), @(204, 'Published'), @(401, 'AuthFailure'), @(415, 'ProtocolError'), @(422, 'Duplicate'), @(500, 'Rejected'), @(400, 'Rejected'))) {
            Assert-Equal (Get-DeployRunVerifyPublishOutcome -HttpStatus $http[0] -Output 'body').Outcome $http[1] "HTTP $($http[0])."
        }
        Assert-Equal (Get-DeployRunVerifyPublishOutcome -HttpStatus $null -Output 'connection refused').Outcome 'InvocationFailure' 'No HTTP response.'
        Assert-Equal (Get-DeployRunVerifyPublishOutcome -ExitCode 1 -Output 'x' -TimedOut).Outcome 'InvocationFailure' 'Timeout.'
        Assert-Equal (Get-DeployRunVerifyPublishOutcome -ExitCode -1 -LaunchError 'cannot start').Outcome 'InvocationFailure' 'Launch error.'
        Assert-Equal (Get-DeployRunVerifyPublishOutcome -ExitCode 1 -Output 'something completely unexpected').Outcome 'Rejected' 'An unrecognized failure stops (no fallback).'
        $redacted = Get-DeployRunVerifyPublishOutcome -ExitCode 1 -Output 'Error HTTP 500 at https://h.example.com:7049/BC/dev/apps?tenant=t&secret=1 password=abc123 Authorization: Basic QWxhZGRpbjpvcGVu'
        Assert-True ($redacted.Reason -notmatch 'abc123|QWxhZGRpbjpvcGVu|secret=1') 'The reason must be redacted.'
    }

    Invoke-TestCase 'S-4b.5 direct Dev Endpoint POST has the exact protocol shape' {
        $appFile = Join-Path $drvTempRoot 'Fixture_App_1.0.0.0.app'
        [System.IO.File]::WriteAllBytes($appFile, [byte[]](1..64))
        $server = Start-DrvTestServer -StatusCode 200
        try {
            $cfg = New-DrvPublishCfg
            $cfg.targetBundle.ServerUrl = 'http://127.0.0.1'; $cfg.targetBundle.Port = $server.Port
            $result = Publish-DeployRunVerifyDevEndpoint -Cfg $cfg -AppFile $appFile -SchemaUpdateMode synchronize
        }
        finally { Stop-DrvTestServer -Server $server }
        Assert-Equal $result.Outcome 'Published' "Outcome (reason: $($result.Reason))."
        Assert-Equal $result.HttpStatus 200 'Status.'
        $request = $server.State.Request
        Assert-Equal $request.Method 'POST' 'Method.'
        Assert-Equal $request.RawUrl '/BC/dev/apps?SchemaUpdateMode=synchronize&DependencyPublishingOption=Default&tenant=default' 'Request line and query.'
        Assert-True ($request.Headers['Content-Type'] -like 'multipart/form-data; boundary=*') 'Content-Type must be multipart/form-data.'
        Assert-True (-not $request.Headers.ContainsKey('Expect')) 'No Expect: 100-continue.'
        Assert-True (-not $request.Headers.ContainsKey('Authorization')) 'Windows authentication sends no manual Authorization header.'
        Assert-True ($request.Body -match '(?i)Content-Disposition: form-data; name="?Fixture_App_1\.0\.0\.0\.app"?; filename="?Fixture_App_1\.0\.0\.0\.app"?; filename\*=utf-8''''Fixture_App_1\.0\.0\.0\.app') 'Part: form-data with name, filename and filename* = file name.'
        $unnamed = $request.Body -split "`r`n" | Where-Object { $_ -match '^Content-Disposition:' }
        Assert-Equal @($unnamed).Count 1 'Exactly one part.'

        # Other schema mode / dependency option / tenant, and a non-2xx answer.
        $server = Start-DrvTestServer -StatusCode 422 -ResponseBody 'duplicate package ID'
        try {
            $cfg = New-DrvPublishCfg
            $cfg.targetBundle.ServerUrl = 'http://127.0.0.1'; $cfg.targetBundle.Port = $server.Port; $cfg.targetBundle.Tenant = 't 1'
            $cfg | Add-Member dependencyPublishingOption 'Strict' -Force
            $duplicate = Publish-DeployRunVerifyDevEndpoint -Cfg $cfg -AppFile $appFile -SchemaUpdateMode forcesync
        }
        finally { Stop-DrvTestServer -Server $server }
        Assert-Equal $duplicate.Outcome 'Duplicate' '422 is Duplicate.'
        Assert-Equal $server.State.Request.RawUrl '/BC/dev/apps?SchemaUpdateMode=forcesync&DependencyPublishingOption=Strict&tenant=t%201' 'forcesync, Strict, escaped tenant.'

        # UserPassword over http stops before any request.
        $server = Start-DrvTestServer -WaitMs 1500
        try {
            $cfg = New-DrvPublishCfg -Authentication UserPassword
            $cfg.targetBundle.ServerUrl = 'http://127.0.0.1'; $cfg.targetBundle.Port = $server.Port
            $credential = [pscredential]::new('test-user', (ConvertTo-SecureString 'test-pw' -AsPlainText -Force))
            Assert-Throws { Publish-DeployRunVerifyDevEndpoint -Cfg $cfg -AppFile $appFile -Credential $credential } 'USERPASSWORD_OVER_HTTP' 'UserPassword over http.' | Out-Null
        }
        finally { Stop-DrvTestServer -Server $server }
        Assert-Null $server.State.Request 'No request may reach the server.'

        # No server listening: transport failure, no exception.
        $closed = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $closed.Start(); $closedPort = $closed.LocalEndpoint.Port; $closed.Stop()
        $cfg = New-DrvPublishCfg
        $cfg.targetBundle.ServerUrl = 'http://127.0.0.1'; $cfg.targetBundle.Port = $closedPort
        $unreachable = Publish-DeployRunVerifyDevEndpoint -Cfg $cfg -AppFile $appFile
        Assert-Equal $unreachable.Outcome 'InvocationFailure' 'Connection refused is an InvocationFailure.'
        Assert-Null $unreachable.HttpStatus 'No HTTP status.'
    }

    Invoke-TestCase 'S-4b.6 Basic authorization is built in memory and ASCII only' {
        $credential = [pscredential]::new('test-user', (ConvertTo-SecureString 'test-pw-1' -AsPlainText -Force))
        $header = New-DeployRunVerifyBasicAuthorization -Credential $credential
        Assert-Equal $header.Scheme 'Basic' 'Scheme.'
        Assert-Equal $header.Parameter ([Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('test-user:test-pw-1'))) 'Base64(user:password).'
        $umlautPassword = [pscredential]::new('test-user', (ConvertTo-SecureString ('pw' + [char]0x00FC) -AsPlainText -Force))
        $message = Assert-Throws { New-DeployRunVerifyBasicAuthorization -Credential $umlautPassword } 'CREDENTIAL_NON_ASCII' 'Non-ASCII password.'
        Assert-True ($message -notlike "*$([char]0x00FC)*") 'The message must not echo the credential.'
        $umlautUser = [pscredential]::new(('us' + [char]0x00FC + 'r'), (ConvertTo-SecureString 'pw' -AsPlainText -Force))
        Assert-Throws { New-DeployRunVerifyBasicAuthorization -Credential $umlautUser } 'CREDENTIAL_NON_ASCII' 'Non-ASCII user.' | Out-Null
    }

    Invoke-TestCase 'S-4b.7 publish route chain: fallback only on InvocationFailure, stop on duplicate, one re-prompt on auth failure' {
        . $publishMocks
        $cfg = New-DrvPublishCfg
        # altool InvocationFailure -> direct POST once; the route is pinned for the next app.
        $script:alOutcome = 'InvocationFailure'
        Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0'
        Assert-Equal $script:alToolCalls 1 'altool tried once.'
        Assert-Equal $script:postCalls 1 'direct POST called once.'
        Assert-Equal $Script:DeployRunVerifyRoutes['Deploy'].Route 'devEndpoint' 'Route recorded.'
        Assert-Equal @($Script:DeployRunVerifyFallbacks).Count 1 'One fallback recorded.'
        Assert-True ($Script:DeployRunVerifyFallbacks[0] -like "ROUTE-FALLBACK: deploy $rightArrow devEndpoint (altool says InvocationFailure)") "Fallback line: $($Script:DeployRunVerifyFallbacks[0])"
        Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'y.app' -Name 'AppB' -Version '1.0.0.0'
        Assert-Equal $script:alToolCalls 1 'Pinned: altool is not tried again in the run.'
        Assert-Equal $script:postCalls 2 'Second app goes directly to the POST.'
        Assert-Equal @($Script:DeployRunVerifyFallbacks).Count 1 'Still one fallback line.'

        # Duplicate / Rejected / ProtocolError: stop, no other route.
        foreach ($case in @(@('Duplicate', 'PUBLISH_DUPLICATE'), @('Rejected', 'PUBLISH_REJECTED'), @('ProtocolError', 'PUBLISH_PROTOCOL_ERROR'))) {
            . $publishMocks
            $script:alOutcome = $case[0]
            $message = Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' } $case[1] "altool $($case[0])."
            Assert-Equal $script:postCalls 0 "$($case[0]): no direct POST."
            Assert-Equal $script:alToolCalls 1 "$($case[0]): no repeat."
            if ($case[0] -eq 'Duplicate') { Assert-True ($message -like '*Do not repeat the publish*') 'Duplicate guidance.' }
        }

        # AuthFailure twice with UserPassword: one re-prompt (store skipped), then a blocker; no route change.
        . $publishMocks
        $script:alOutcome = 'AuthFailure'
        $userCfg = New-DrvPublishCfg -Authentication UserPassword -Scheme https
        Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg $userCfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' } 'PUBLISH_AUTH_FAILED' 'AuthFailure twice.' | Out-Null
        Assert-Equal $script:credentialCalls 2 'Credential read twice (second time store skipped).'
        Assert-Equal $script:resetCalls 1 'One reset / re-prompt.'
        Assert-Equal $script:alToolCalls 2 'altool tried twice.'
        Assert-Equal $script:postCalls 0 'No direct POST after an auth failure.'

        # AuthFailure with Windows: blocker immediately, no re-prompt.
        . $publishMocks
        $script:alOutcome = 'AuthFailure'
        Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' } 'PUBLISH_AUTH_FAILED' 'Windows auth failure.' | Out-Null
        Assert-Equal $script:resetCalls 0 'No re-prompt for Windows.'

        # Direct POST outcomes after a fallback.
        foreach ($case in @(@('Duplicate', 'PUBLISH_DUPLICATE'), @('InvocationFailure', 'PUBLISH_FAILED'), @('ProtocolError', 'PUBLISH_PROTOCOL_ERROR'))) {
            . $publishMocks
            $script:alOutcome = 'InvocationFailure'; $script:postOutcome = $case[0]
            Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' } $case[1] "direct POST $($case[0])." | Out-Null
            Assert-Equal $script:postCalls 1 'The POST is never repeated.'
        }

        # State verification: published but not installed -> DEPLOY INCOMPLETE.
        . $publishMocks
        $script:stateInstalled = $false
        Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' } 'DEPLOY INCOMPLETE (Asinst)' 'Not installed.' | Out-Null

        # altool unavailable: direct POST with the reason recorded.
        . $publishMocks
        function Get-DeployRunVerifyAlTool { [pscustomobject]@{ Path = $null; Version = $null; Source = 'none'; Error = 'ALTOOL_NOT_FOUND: nothing' } }
        Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0'
        Assert-Equal $script:alToolCalls 0 'No altool call without a tool.'
        Assert-True ($Script:DeployRunVerifyFallbacks[0] -like '*altool unavailable (ALTOOL_NOT_FOUND*') 'Reason of the fallback.'
        $Script:DeployRunVerifyCredentialFromStore = $false
    }

    Invoke-TestCase 'S-4b.8 schema mode follows fkhSyncMode for both adapters and both routes' {
        $absent = Get-DeployRunVerifySchemaMode -Cfg ([pscustomobject]@{})
        Assert-Equal $absent.AlTool 'Synchronize' 'Absent: Synchronize.'
        Assert-Equal $absent.Endpoint 'synchronize' 'Absent: synchronize.'
        Assert-Equal (Get-DeployRunVerifySchemaMode -Cfg ([pscustomobject]@{ fkhSyncMode = 'Add' })).AlTool 'Synchronize' 'Add.'
        $force = Get-DeployRunVerifySchemaMode -Cfg ([pscustomobject]@{ fkhSyncMode = 'ForceSync' })
        Assert-Equal $force.AlTool 'ForceSync' 'ForceSync altool.'
        Assert-Equal $force.Endpoint 'forcesync' 'ForceSync endpoint.'
        Assert-Throws { Get-DeployRunVerifySchemaMode -Cfg ([pscustomobject]@{ fkhSyncMode = 'Foo' }) } "fkhSyncMode must be 'Add' or 'ForceSync'" 'Foo.' | Out-Null
        Assert-Throws { Publish-DeployRunVerifyDevEndpoint -Cfg (New-DrvPublishCfg) -AppFile 'x.app' -ForceUpgrade } 'FORCEUPGRADE_REQUIRES_ALTOOL' 'Direct POST with ForceUpgrade.' | Out-Null
        foreach ($launch in @($null, '{ "configurations": [ { "name": "dev-windows", "type": "al", "request": "launch", "environmentType": "OnPrem", "server": "https://x.cloudapp.azure.com", "serverInstance": "BC", "authentication": "UserPassword" } ] }')) {
            $configPath = New-DrvTestRepo -Fixture 'case-configured-windows' -ConfigExtra @{ fkhSyncMode = 'Foo' } -LaunchJson $launch
            Assert-Throws { Resolve-DeployRunVerifyConfig -ConfigPath $configPath } "fkhSyncMode must be 'Add' or 'ForceSync'" 'Foo is rejected at resolution on each adapter.' | Out-Null
        }

        # Arguments of the altool route per adapter and mode; --forceupgrade only on request; no --project.
        Reset-DeployRunVerifyRunState
        $script:capturedArguments = $null
        function Invoke-DeployRunVerifyAlTool {
            param($AlTool, $Arguments, $Credential, $TimeoutMs)
            $script:capturedArguments = @($Arguments)
            [pscustomobject]@{ ExitCode = 0; StdOut = 'Published successfully.'; StdErr = ''; DurationMs = 1; TimedOut = $false; LaunchError = $null }
        }
        foreach ($adapter in 'Asinst', 'Fkh') {
            foreach ($mode in @(@('Add', 'Synchronize'), @('ForceSync', 'ForceSync'))) {
                $cfg = New-DrvPublishCfg -Adapter $adapter -SyncMode $mode[0]
                $schema = Get-DeployRunVerifySchemaMode -Cfg $cfg
                $outcome = Invoke-DeployRunVerifyAlToolPublish -Cfg $cfg -AlTool ([pscustomobject]@{ Path = 'C:\fake\altool.exe' }) -AppFile 'C:\x\App.app' -Schema $schema 6>$null
                Assert-Equal $outcome.Outcome 'Published' "$adapter/$($mode[0]) outcome."
                $a = $script:capturedArguments
                Assert-Equal ($a -join ' ') "publishapp C:\x\App.app --server http://nst-test.example.com --serverinstance BC --port 7049 --authentication Windows --tenant default --environmenttype OnPrem --schemaupdatemode $($mode[1])" "$adapter/$($mode[0]) arguments (complete bundle, no --project)."
            }
        }
        $cfg = New-DrvPublishCfg
        Invoke-DeployRunVerifyAlToolPublish -Cfg $cfg -AlTool ([pscustomobject]@{ Path = 'C:\fake\altool.exe' }) -AppFile 'C:\x\App.app' -Schema (Get-DeployRunVerifySchemaMode -Cfg $cfg) -ForceUpgrade 6>$null | Out-Null
        Assert-Equal $script:capturedArguments[-1] '--forceupgrade' '--forceupgrade appended on request.'

        # ForceSync prints the mode line once per run; Add does not.
        . $publishMocks
        function Get-DeployRunVerifyPublishContext { param($Cfg) $null }
        foreach ($mode in 'Add', 'ForceSync') {
            $cfg = New-DrvPublishCfg -SyncMode $mode
            $cfg | Add-Member apps @([pscustomobject]@{ AppFile = 'x.app'; Name = 'AppA'; Version = '1.0.0.0' }) -Force
            $run = Invoke-Captured { Invoke-DeployRunVerifyPublish -Cfg $cfg }
            $hasLine = $run.Info -contains 'SCHEMA MODE: ForceSync (fkhSyncMode)'
            Assert-Equal $hasLine ($mode -eq 'ForceSync') "$mode mode line."
        }

        # forceUpgrade is not available on the direct POST, directly or after a fallback.
        . $publishMocks
        $cfg = New-DrvPublishCfg
        function Publish-DeployRunVerifyDevEndpoint { param($Cfg, $AppFile, $Credential, $SchemaUpdateMode, [switch]$ForceUpgrade) if ($ForceUpgrade) { throw 'FORCEUPGRADE_REQUIRES_ALTOOL: mock' }; [pscustomobject]@{ Outcome = 'Published'; Reason = ''; HttpStatus = 200; Body = '' } }
        $script:alOutcome = 'InvocationFailure'
        Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' -ForceUpgrade } 'FORCEUPGRADE_REQUIRES_ALTOOL' 'Chain: altool failed, forceUpgrade requested.' | Out-Null
    }

    Invoke-TestCase 'S-4b.9 build route: compiler errors never fall back; launch failures do and are recorded' {
        $buildRoot = Join-Path $drvTempRoot ('build-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $apps = foreach ($name in 'AppA', 'AppB') {
            $dir = Join-Path $buildRoot $name
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [pscustomobject]@{ ProjectDir = $dir; Name = $name; Version = '1.0.0.0'; Publisher = 'Fix'; AppFile = (Join-Path $dir "Fix_${name}_1.0.0.0.app") }
        }
        $cfg = [pscustomobject]@{ apps = @($apps); alcPath = 'C:\fake\alc.exe' }
        $mocks = {
            Reset-DeployRunVerifyRunState
            $script:altoolCompileCalls = 0; $script:alcCalls = 0; $script:compileResult = 'ok'; $script:compileCaps = $true
            function Get-DeployRunVerifyAlTool { [pscustomobject]@{ Path = 'C:\fake\altool.exe'; Version = '18.1.43'; Source = 'extension'; Error = $null } }
            function Get-DeployRunVerifyAlToolCapabilities { [pscustomobject]@{ Compile = $script:compileCaps; PublishApp = $true; RunTests = $true; TestGroups = $true } }
            function Invoke-DeployRunVerifyAlc { param($Cfg, $App, $PackageDir) $script:alcCalls++; Set-Content -LiteralPath $App.AppFile -Value 'alc' }
            function Invoke-DeployRunVerifyAlTool {
                param($AlTool, $Arguments, $Credential, $TimeoutMs)
                $script:altoolCompileCalls++
                $out = ($Arguments | Where-Object { $_ -like '/out:*' }) -replace '^/out:', ''
                switch ($script:compileResult) {
                    'ok' { Set-Content -LiteralPath $out -Value 'altool'; [pscustomobject]@{ ExitCode = 0; StdOut = 'Compiled.'; StdErr = ''; DurationMs = 1; TimedOut = $false; LaunchError = $null } }
                    'error' { [pscustomobject]@{ ExitCode = 1; StdOut = 'Page.al(3,1): error AL0118: The name ''Foo'' does not exist.'; StdErr = ''; DurationMs = 1; TimedOut = $false; LaunchError = $null } }
                    'launch' { [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = ''; DurationMs = 1; TimedOut = $false; LaunchError = 'cannot start' } }
                    'silent' { [pscustomobject]@{ ExitCode = 3; StdOut = 'Unhandled exception: boom'; StdErr = ''; DurationMs = 1; TimedOut = $false; LaunchError = $null } }
                }
            }
        }
        . $mocks
        $script:compileResult = 'error'
        Assert-Throws { Invoke-Captured { Invoke-DeployRunVerifyBuild -Cfg $cfg } | Out-Null } 'BUILD FAILED: AppA' 'AL0118 compiler error.' | Out-Null
        Assert-Equal $script:alcCalls 0 'A compiler error must not trigger the alc fallback.'
        Assert-Equal @($Script:DeployRunVerifyFallbacks).Count 0 'No fallback recorded.'

        foreach ($case in 'launch', 'silent') {
            . $mocks
            $script:compileResult = $case
            $run = Invoke-Captured { Invoke-DeployRunVerifyBuild -Cfg $cfg }
            Assert-Equal $script:alcCalls 2 "$case : alc builds both apps."
            Assert-Equal $script:altoolCompileCalls 1 "$case : the failed route is pinned after the first app."
            Assert-Equal $Script:DeployRunVerifyRoutes['Build'].Route 'alc' "$case : route recorded."
            Assert-Equal @($Script:DeployRunVerifyFallbacks).Count 1 "$case : one fallback line."
            Assert-True ($Script:DeployRunVerifyRoutes['Build'].Reason -like ($(if ($case -eq 'launch') { '*could not be started*' } else { '*without a compiler diagnostic*' }))) "$case : reason recorded."
        }

        . $mocks
        $run = Invoke-Captured { Invoke-DeployRunVerifyBuild -Cfg $cfg }
        Assert-Equal $script:altoolCompileCalls 2 'altool builds both apps.'
        Assert-Equal $script:alcCalls 0 'No alc call.'
        Assert-Equal $Script:DeployRunVerifyRoutes['Build'].Route 'altool' 'Route altool.'
        Assert-True (Test-Path (Join-Path $apps[1].ProjectDir '.alpackages\Fix_AppA_1.0.0.0.app')) 'Upstream .app copied into the downstream .alpackages.'

        . $mocks
        $script:compileCaps = $false
        $run = Invoke-Captured { Invoke-DeployRunVerifyBuild -Cfg $cfg }
        Assert-Equal $script:altoolCompileCalls 0 'No compile capability: altool not used.'
        Assert-True ($Script:DeployRunVerifyFallbacks[0] -like '*no compile command*') 'Reason: no compile command.'
    }

    Invoke-TestCase 'S-4b.10 test codeunit discovery from range and source' {
        $projectDir = Join-Path $drvTempRoot ('tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path (Join-Path $projectDir 'src'), (Join-Path $projectDir '.alpackages'), (Join-Path $projectDir '.snapshots') -Force | Out-Null
        $write = { param($Path, $Text) [System.IO.File]::WriteAllText((Join-Path $projectDir $Path), $Text) }
        & $write 'src\A.Codeunit.al' "codeunit 59010 ""Test A""`n{`n    Subtype = Test;`n}"
        & $write 'src\B.Codeunit.al' "codeunit 59011 ""Setup B""`n{`n    Subtype = Normal;`n}"
        & $write 'src\C.Codeunit.al' "codeunit 59012 ""Events C""`n{`n}"
        & $write 'src\D.Codeunit.al' "codeunit 59013 ""Test D""`n{`n    Subtype=Test;`n}"
        & $write '.alpackages\E.Codeunit.al' "codeunit 59012 ""Copy""`n{`n    Subtype = Test;`n}"
        & $write '.snapshots\F.Codeunit.al' "codeunit 59011 ""Snapshot""`n{`n    Subtype = Test;`n}"
        $expect = @(
            @('59010..59013', '59010, 59013'), @('59010|59013', '59010, 59013'), @('59010', '59010'), @('59010..59011|59013', '59010, 59013'),
            @(' 59010..59013 ', '59010, 59013'), @('59020..59030', ''))
        foreach ($case in $expect) {
            $found = Get-DeployRunVerifyTestCodeunits -ProjectDir $projectDir -Range $case[0]
            Assert-Null $found.Reason "Range '$($case[0])': no reason."
            Assert-Equal (@($found.Codeunits) -join ', ') $case[1] "Range '$($case[0])'."
        }
        foreach ($bad in 'x..y', '59013..59010', '', '59010,59013', '59010..', '59010|') {
            Assert-Equal (Get-DeployRunVerifyTestCodeunits -ProjectDir $projectDir -Range $bad).Reason 'RANGE_UNSUPPORTED' "Range '$bad'."
        }
        & $write 'src\G.Codeunit.al' "codeunit 59090 ""One""`n{`n}`ncodeunit 59091 ""Two""`n{`n    Subtype = Test;`n}"
        Assert-Equal (Get-DeployRunVerifyTestCodeunits -ProjectDir $projectDir -Range '59010..59013').Reason 'MULTI_OBJECT_FILE' 'Two codeunits in one file.'
    }

    Invoke-TestCase 'S-4b.11 JSON extraction ignores diagnostic noise' {
        foreach ($name in 'runtests-green-complete.txt', 'runtests-noise-chunklength.txt', 'runtests-truncated-first-group.txt', 'runtests-red-testrunfailed.txt') {
            $json = ConvertFrom-DeployRunVerifyAlToolJson -Text (Get-AlToolFixture $name)
            Assert-True ($null -ne $json -and $null -ne $json.PSObject.Properties['succeeded']) "$name : the result object must be parsed."
        }
        Assert-Equal @((ConvertFrom-DeployRunVerifyAlToolJson -Text (Get-AlToolFixture 'runtests-green-complete.txt')).data.results).Count 25 'Green fixture records.'
        Assert-Null (ConvertFrom-DeployRunVerifyAlToolJson -Text "A task was canceled.`nno json here") 'No JSON.'
        Assert-Null (ConvertFrom-DeployRunVerifyAlToolJson -Text '') 'Empty.'
        $withBraces = "{ not json }`n{ ""succeeded"": true, ""data"": { ""results"": [ { ""methodName"": ""a}b{"", ""codeunitId"": 1, ""status"": ""Passed"" } ] } }"
        Assert-True ((ConvertFrom-DeployRunVerifyAlToolJson -Text $withBraces).succeeded) 'A non-JSON line starting with { is skipped; braces inside strings are handled.'
    }

    Invoke-TestCase 'S-4b.12 test outcome classification (fallback only on InvocationFailure / Incomplete)' {
        $requested = @(59010, 59013)
        $cases = @(
            @('runtests-green-complete.txt', 0, $requested, 'Green'),
            @('runtests-noise-chunklength.txt', 0, $requested, 'Green'),
            @('runtests-truncated-first-group.txt', 0, $requested, 'Incomplete'),
            @('runtests-nontest-only.txt', 0, @(59011), 'Incomplete'),
            @('runtests-red-testrunfailed.txt', 1, @(59020), 'Red'),
            @('runtests-auth-failure.txt', 1, @(59010), 'AuthFailure'),
            @('runtests-wrong-port.txt', 1, @(59010), 'InvocationFailure'))
        foreach ($case in $cases) {
            $outcome = Get-DeployRunVerifyTestOutcome -Output (Get-AlToolFixture $case[0]) -ExitCode $case[1] -RequestedCodeunits $case[2]
            Assert-Equal $outcome.Outcome $case[3] "Fixture $($case[0])."
        }
        $truncated = Get-DeployRunVerifyTestOutcome -Output (Get-AlToolFixture 'runtests-truncated-first-group.txt') -RequestedCodeunits $requested
        Assert-True ($truncated.Reason -like '*59013*') 'The missing codeunit is named.'
        Assert-Equal (Get-DeployRunVerifyTestOutcome -Output 'garbage' -ExitCode 1).Outcome 'InvocationFailure' 'No JSON.'
        Assert-Equal (Get-DeployRunVerifyTestOutcome -Output 'Unhandled: UserNotAuthenticated' -ExitCode 1).Outcome 'AuthFailure' 'No JSON but UserNotAuthenticated.'
        Assert-Equal (Get-DeployRunVerifyTestOutcome -Output (Get-AlToolFixture 'runtests-green-complete.txt') -TimedOut).Outcome 'InvocationFailure' 'Timeout.'
        Assert-Equal (Get-DeployRunVerifyTestOutcome -Output '' -LaunchError 'cannot start').Outcome 'InvocationFailure' 'Launch error.'
        $mixed = '{ "succeeded": true, "data": { "results": [ { "codeunitId": 59010, "methodName": "T1", "status": "Passed", "output": "" }, { "codeunitId": 59010, "methodName": "T2", "status": "Failed", "output": "x" } ] } }'
        Assert-Equal (Get-DeployRunVerifyTestOutcome -Output $mixed -RequestedCodeunits @(59010)).Outcome 'Red' 'succeeded=true with a failed record is Red.'
    }

    Invoke-TestCase 'S-4b.13 runtests result normalization' {
        $green = ConvertTo-DeployRunVerifyTestSummary -Json (ConvertFrom-DeployRunVerifyAlToolJson -Text (Get-AlToolFixture 'runtests-green-complete.txt'))
        Assert-Equal $green.Total 23 'Green: 25 records, 23 counted.'
        Assert-Equal $green.Passed 23 'Green passed.'
        Assert-Equal $green.Failed 0 'Green failed.'
        Assert-Equal $green.Skipped 0 'Green skipped.'
        Assert-Equal @($green.Failures).Count 0 'Green failures.'
        Assert-Equal $green.Stage 'ran' 'Stage.'
        $red = ConvertTo-DeployRunVerifyTestSummary -Json (ConvertFrom-DeployRunVerifyAlToolJson -Text (Get-AlToolFixture 'runtests-red-testrunfailed.txt'))
        Assert-Equal $red.Total 12 'Red: the blank completion record is not counted.'
        Assert-Equal $red.Passed 11 'Red passed.'
        Assert-Equal $red.Failed 1 'Red failed (blank record de-duplicated).'
        Assert-Equal (@($red.Failures) -join ',') '59020:TestCaseB01' 'Failures are codeunit:method.'
        Assert-True ($red.FailureDetails[0].Output -like '*AL call stack*') 'The call stack is kept.'
        Assert-Equal $red.FailureDetails[0].Test '59020:TestCaseB01' 'Detail name.'
        $skipped = '{ "succeeded": true, "data": { "results": [ { "codeunitId": 1, "methodName": "A", "status": "Skipped" }, { "codeunitId": 1, "methodName": "B", "status": "PASSED" }, { "codeunitId": 1, "methodName": "C", "status": "weird" } ] } }'
        $mixed = ConvertTo-DeployRunVerifyTestSummary -Json (ConvertFrom-DeployRunVerifyAlToolJson -Text $skipped)
        Assert-True ($mixed.Skipped -eq 1 -and $mixed.Passed -eq 1 -and $mixed.Failed -eq 1) 'Status matching is case-insensitive; an unknown status counts as failed.'
    }

    Invoke-TestCase 'S-4b.12b test step: red is a result, auth retried once, invocation failure and incomplete fall back' {
        $json = ConvertFrom-DeployRunVerifyAlToolJson -Text (Get-AlToolFixture 'runtests-green-complete.txt')
        $redJson = ConvertFrom-DeployRunVerifyAlToolJson -Text (Get-AlToolFixture 'runtests-red-testrunfailed.txt')
        $mocks = {
            Reset-DeployRunVerifyRunState
            $script:runs = 0; $script:legacyRuns = 0; $script:credentialCalls = 0; $script:resetCalls = 0
            $script:next = [pscustomobject]@{ Outcome = 'Green'; Reason = ''; Json = $json }
            function Select-DeployRunVerifyTestRoute { [pscustomobject]@{ Route = 'altool'; Reason = ''; Codeunits = [int[]]@(59010, 59013); AlTool = [pscustomobject]@{ Path = 'C:\fake\altool.exe' } } }
            function Invoke-DeployRunVerifyAlToolTestRun { $script:runs++; $script:next }
            function Invoke-DeployRunVerifyRun { $script:legacyRuns++; [pscustomobject]@{ Stage = 'ran'; Ok = $true; Total = 1; Passed = 1; Failed = 0; Skipped = 0; Failures = @() } }
            function Get-DeployRunVerifyCredential { $script:credentialCalls++; [pscredential]::new('test-user', (ConvertTo-SecureString 'test-pw' -AsPlainText -Force)) }
            function Reset-DeployRunVerifyCredential { $script:resetCalls++ }
        }
        $cfg = [pscustomobject]@{ authentication = 'Windows'; server = 'nst-test.example.com'; testRoute = 'auto' }

        . $mocks
        $summary = Invoke-DeployRunVerifyTests -Cfg $cfg
        Assert-Equal $summary.Total 23 'Green summary normalized.'
        Assert-Equal $Script:DeployRunVerifyRoutes['Tests'].Route 'altool' 'Route altool.'
        Assert-Equal $script:legacyRuns 0 'No legacy run.'

        . $mocks
        $script:next = [pscustomobject]@{ Outcome = 'Red'; Reason = 'TestRunFailed'; Json = $redJson }
        $summary = Invoke-DeployRunVerifyTests -Cfg $cfg
        Assert-Equal $summary.Failed 1 'Red result as is.'
        Assert-Equal $script:legacyRuns 0 'Red must never trigger the web-client runner.'
        Assert-Equal @($Script:DeployRunVerifyFallbacks).Count 0 'No fallback on red.'

        foreach ($outcome in 'InvocationFailure', 'Incomplete') {
            . $mocks
            $script:next = [pscustomobject]@{ Outcome = $outcome; Reason = "reason-$outcome"; Json = $null }
            $summary = Invoke-DeployRunVerifyTests -Cfg $cfg
            Assert-Equal $script:legacyRuns 1 "$outcome : web-client runner used."
            Assert-Equal $Script:DeployRunVerifyRoutes['Tests'].Route 'webClient' "$outcome : route."
            Assert-True ($Script:DeployRunVerifyFallbacks[0] -like "ROUTE-FALLBACK: tests $rightArrow webClient ($outcome`: reason-$outcome)") "$outcome : fallback line: $($Script:DeployRunVerifyFallbacks[0])"
            Assert-True ($Script:DeployRunVerifyPinnedLegacy.ContainsKey('Tests')) "$outcome : pinned."
        }

        . $mocks
        $script:next = [pscustomobject]@{ Outcome = 'AuthFailure'; Reason = 'UserNotAuthenticated'; Json = $null }
        Assert-Throws { Invoke-DeployRunVerifyTests -Cfg $cfg } 'TESTS_AUTH_FAILED' 'Windows auth failure.' | Out-Null
        Assert-Equal $script:legacyRuns 0 'No route change on auth failure.'
        . $mocks
        $script:next = [pscustomobject]@{ Outcome = 'AuthFailure'; Reason = 'UserNotAuthenticated'; Json = $null }
        $userCfg = [pscustomobject]@{ authentication = 'UserPassword'; server = 'dev.example.com'; testRoute = 'auto' }
        Assert-Throws { Invoke-DeployRunVerifyTests -Cfg $userCfg } 'TESTS_AUTH_FAILED' 'UserPassword auth failure twice.' | Out-Null
        Assert-Equal $script:runs 2 'altool run twice.'
        Assert-Equal $script:resetCalls 1 'One re-prompt.'
        Assert-Equal $script:legacyRuns 0 'No legacy run after auth failures.'

        # Forced altool does not fall back.
        . $mocks
        $script:next = [pscustomobject]@{ Outcome = 'InvocationFailure'; Reason = 'down'; Json = $null }
        $forced = [pscustomobject]@{ authentication = 'Windows'; server = 'nst-test.example.com'; testRoute = 'altool' }
        Assert-Throws { Invoke-DeployRunVerifyTests -Cfg $forced } 'ROUTE_UNAVAILABLE: tests=altool' 'Forced altool.' | Out-Null
        Assert-Equal $script:legacyRuns 0 'Forced altool never runs the web client.'
        $Script:DeployRunVerifyCredentialFromStore = $false
    }

    Invoke-TestCase 'S-4b.12c altool test run: groups file, complete bundle, raw output kept' {
        $runnerDir = Join-Path $drvTempRoot ('runner-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $runnerDir -Force | Out-Null
        $cfg = [pscustomobject]@{
            runnerDirFull = $runnerDir; companyName = 'CRONUS CH'; runTimeoutMs = 60000
            apps = @([pscustomobject]@{ ProjectDir = 'C:\repo\Base' }, [pscustomobject]@{ ProjectDir = 'C:\repo\Test' })
            targetBundle = [pscustomobject]@{ ServerUrl = 'http://nst-test.example.com'; ServerInstance = 'BC'; Port = 7049; Authentication = 'Windows'; Tenant = 'default' }
        }
        $script:capturedArguments = $null
        function Invoke-DeployRunVerifyAlTool {
            param($AlTool, $Arguments, $Credential, $TimeoutMs)
            $script:capturedArguments = @($Arguments)
            [pscustomobject]@{ ExitCode = 0; StdOut = (Get-AlToolFixture 'runtests-green-complete.txt'); StdErr = ''; DurationMs = 1; TimedOut = $false; LaunchError = $null }
        }
        $decision = [pscustomobject]@{ Route = 'altool'; Reason = ''; Codeunits = [int[]]@(59010, 59013); AlTool = [pscustomobject]@{ Path = 'C:\fake\altool.exe' } }
        $run = Invoke-Captured { Invoke-DeployRunVerifyAlToolTestRun -Cfg $cfg -Decision $decision }
        Assert-Equal $run.Result[0].Outcome 'Green' 'Outcome.'
        $groups = Get-Content -LiteralPath (Join-Path $runnerDir '_altool\testgroups.json') -Raw | ConvertFrom-Json
        Assert-Equal (@($groups | ForEach-Object { $_.codeunitId }) -join ',') '59010,59013' 'Groups file lists the codeunits.'
        $groupFile = Join-Path $runnerDir '_altool\testgroups.json'
        Assert-Equal ($script:capturedArguments -join ' ') "runtests --testgroups $groupFile --project C:\repo\Test --company CRONUS CH --server http://nst-test.example.com --serverinstance BC --port 7049 --authentication Windows --tenant default --environmenttype OnPrem" 'Arguments: complete bundle, test project, company.'
        Assert-True ((Get-Content -LiteralPath (Join-Path $runnerDir '_altool\runtests.out.txt') -Raw) -like 'A task was canceled.*') 'Raw stdout saved.'
        $single = [pscustomobject]@{ Route = 'altool'; Reason = ''; Codeunits = [int[]]@(59010); AlTool = $decision.AlTool }
        Invoke-Captured { Invoke-DeployRunVerifyAlToolTestRun -Cfg $cfg -Decision $single } | Out-Null
        Assert-True ((Get-Content -LiteralPath $groupFile -Raw).TrimStart().StartsWith('[')) 'A single codeunit is still a JSON array.'
    }

    Invoke-TestCase 'S-4b.12d test route selection' {
        $projectDir = Join-Path $drvTempRoot ('route-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $projectDir 'A.Codeunit.al'), "codeunit 59010 ""T""`n{`n    Subtype = Test;`n}")
        $base = { param($Overrides) $c = [ordered]@{ apps = @([pscustomobject]@{ ProjectDir = $projectDir }); testSuite = 'DEFAULT'; companyName = 'CRONUS CH'; testCodeunitRange = '59010..59013' }; foreach ($k in $Overrides.Keys) { $c[$k] = $Overrides[$k] }; [pscustomobject]$c }
        $mocks = {
            Reset-DeployRunVerifyRunState
            $script:caps = [pscustomobject]@{ Compile = $true; PublishApp = $true; RunTests = $true; TestGroups = $true }
            function Get-DeployRunVerifyAlTool { [pscustomobject]@{ Path = 'C:\fake\altool.exe'; Version = '18.1.43'; Source = 'extension'; Error = $null } }
            function Get-DeployRunVerifyAlToolCapabilities { $script:caps }
        }
        . $mocks
        $decision = Select-DeployRunVerifyTestRoute -Cfg (& $base @{})
        Assert-Equal $decision.Route 'altool' 'Default: altool.'
        Assert-Equal (@($decision.Codeunits) -join ',') '59010' 'Codeunits.'
        foreach ($case in @(@{ testSuite = 'NIGHTLY' }, @{ companyName = '' }, @{ testCodeunitRange = '59010..x' })) {
            . $mocks
            $web = Select-DeployRunVerifyTestRoute -Cfg (& $base $case)
            Assert-Equal $web.Route 'webClient' "Case $($case.Keys[0])."
        }
        . $mocks
        $script:caps = [pscustomobject]@{ Compile = $true; PublishApp = $true; RunTests = $true; TestGroups = $false }
        Assert-True ((Select-DeployRunVerifyTestRoute -Cfg (& $base @{})).Reason -like '*--testgroups*') 'Missing --testgroups.'
        . $mocks
        $script:caps = [pscustomobject]@{ Compile = $true; PublishApp = $true; RunTests = $false; TestGroups = $false }
        Assert-True ((Select-DeployRunVerifyTestRoute -Cfg (& $base @{})).Reason -like '*no runtests*') 'Missing runtests.'
        . $mocks
        $Script:DeployRunVerifyPinnedLegacy['Tests'] = 'earlier failure'
        Assert-True ((Select-DeployRunVerifyTestRoute -Cfg (& $base @{})).Reason -like 'pinned*') 'Pinned.'
        . $mocks
        function Get-DeployRunVerifyAlTool { [pscustomobject]@{ Path = $null; Version = $null; Source = 'none'; Error = 'ALTOOL_NOT_FOUND' } }
        Assert-True ((Select-DeployRunVerifyTestRoute -Cfg (& $base @{})).Reason -like 'altool unavailable*') 'No altool.'
        . $mocks
        $empty = Join-Path $drvTempRoot ('empty-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Path $empty -Force | Out-Null
        Assert-Equal (Select-DeployRunVerifyTestRoute -Cfg (& $base @{ apps = @([pscustomobject]@{ ProjectDir = $empty }) })).Reason 'NO_TEST_CODEUNITS' 'No test codeunits.'
    }

    Invoke-TestCase 'S-4b.14 engine source scan' {
        $source = Get-Content -LiteralPath $enginePath -Raw
        Assert-True ($source -notmatch '(?i)(?<!un)publish-NAVApp') 'No Publish-NAVApp.'
        Assert-True ($source -notmatch '(?i)fkh\s+publishapp') 'No fkh publishapp.'
        Assert-True ($source -notmatch 'InstallOrUpgrade') 'No InstallOrUpgrade.'
        Assert-True ($source -notmatch '(?i)(?<!un)Sync-NAVApp') 'No Sync-NAVApp.'
        Assert-True ($source -notmatch '(?i)\bRecreate\b') 'No Recreate.'
        Assert-True ($source -notmatch '(?i)\b(Un)?Install-NAVApp\b|Start-NAVAppDataUpgrade') 'No install / uninstall / data upgrade cmdlets.'
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
        Assert-Equal @($parseErrors).Count 0 'The engine parses.'
        $remove = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Remove-DeployRunVerifyAppVersion' }, $true))
        Assert-Equal $remove.Count 1 'Remove-DeployRunVerifyAppVersion exists once.'
        Assert-True ($remove[0].Extent.Text -match 'Unpublish-NAVApp') 'Unpublish-NAVApp lives in Remove-DeployRunVerifyAppVersion.'
        Assert-True ($remove[0].Extent.Text -notmatch '(?i)-ClearSchema|-DoNotSaveData|-ForceSync|-Mode ') 'The removal passes no destructive switch.'
        $outside = $source.Replace($remove[0].Extent.Text, '')
        Assert-True ($outside -notmatch 'Unpublish-NAVApp') 'Unpublish-NAVApp appears nowhere else.'
    }

    Invoke-TestCase 'S-4b.15 report: Routes, AlTool, ROUTE and ROUTE-FALLBACK lines after TIMING' {
        . $publishMocks
        function Get-DeployRunVerifyAlTool { [pscustomobject]@{ Path = 'C:\fake\altool.exe'; Version = '18.1.43'; Source = 'extension'; Error = $null } }
        function Test-DeployRunVerifyPreflight { [pscustomobject]@{ Reachable = $true; ServiceUrl = 'x' } }
        function Invoke-DeployRunVerifyBuild { Set-DeployRunVerifyRoute -Step Build -Route altool; $true }
        function Test-DeployRunVerifyTargetDependencies { }
        function Invoke-DeployRunVerifyPublish { Set-DeployRunVerifyRoute -Step Deploy -Route devEndpoint -Reason 'InvocationFailure: refused' -Fallback; $true }
        function Invoke-DeployRunVerifyTests { Set-DeployRunVerifyRoute -Step Tests -Route altool; [pscustomobject]@{ Stage = 'ran'; Ok = $true; Total = 3; Passed = 3; Failed = 0; Skipped = 0; Failures = @() } }
        $configPath = New-DrvTestRepo -Fixture 'case-configured-windows'
        $run = Invoke-Captured { Invoke-AprodaDeployRunVerify -ConfigPath $configPath }
        $summary = $run.Result[0]
        Assert-Equal $summary.Routes.Build.Route 'altool' 'Routes.Build.'
        Assert-Equal $summary.Routes.Deploy.Route 'devEndpoint' 'Routes.Deploy.'
        Assert-Equal $summary.Routes.Deploy.Reason 'InvocationFailure: refused' 'Routes.Deploy.Reason.'
        Assert-Equal $summary.Routes.Tests.Route 'altool' 'Routes.Tests.'
        Assert-Equal $summary.AlTool.Version '18.1.43' 'AlTool.Version.'
        Assert-Equal $summary.AlTool.Source 'extension' 'AlTool.Source.'
        Assert-Equal $summary.AlTool.Path 'C:\fake\altool.exe' 'AlTool.Path.'
        $timing = [array]::FindIndex($run.Info, [Predicate[string]] { param($l) $l -like 'TIMING:*' })
        $route = [array]::FindIndex($run.Info, [Predicate[string]] { param($l) $l -like 'ROUTE:*' })
        $fallback = @($run.Info | Where-Object { $_ -like 'ROUTE-FALLBACK:*' })
        Assert-True ($timing -ge 0 -and $route -gt $timing) 'ROUTE: follows TIMING:.'
        Assert-Equal $run.Info[$route] "ROUTE: build=altool $middleDot deploy=devEndpoint $middleDot tests=altool" 'ROUTE line.'
        Assert-Equal $fallback.Count 1 'One ROUTE-FALLBACK line.'
        Assert-Equal $fallback[0] "ROUTE-FALLBACK: deploy $rightArrow devEndpoint (InvocationFailure: refused)" 'ROUTE-FALLBACK line.'
        Assert-True ([array]::IndexOf($run.Info, $fallback[0]) -gt $route) 'ROUTE-FALLBACK follows ROUTE.'
    }

    Invoke-TestCase 'S-4b.16 modes and forced routes' {
        $configPath = New-DrvTestRepo -Fixture 'case-configured-windows'
        . $publishMocks
        function Test-DeployRunVerifyPreflight { [pscustomobject]@{ Reachable = $true; ServiceUrl = 'x' } }
        function Invoke-DeployRunVerifyBuild { throw 'BUILD_WAS_CALLED' }
        function Test-DeployRunVerifyTargetDependencies { throw 'DEPENDENCIES_WERE_CHECKED' }
        function Invoke-DeployRunVerifyPublish { throw 'PUBLISH_WAS_CALLED' }
        function Select-DeployRunVerifyTestRoute { throw 'ROUTE_SELECTION_WAS_CALLED' }
        function Invoke-DeployRunVerifyAlToolTestRun { throw 'ALTOOL_TEST_RUN_WAS_CALLED' }
        $script:legacyRuns = 0
        function Invoke-DeployRunVerifyRun { $script:legacyRuns++; [pscustomobject]@{ Stage = 'ran'; Ok = $true; Total = 2; Passed = 2; Failed = 0; Skipped = 0; Failures = @() } }
        $run = Invoke-Captured { Invoke-AprodaDeployRunVerify -ConfigPath $configPath -RunOnly -TestRoute webClient }
        Assert-Equal $run.Result[0].Passed 2 'runonly + TestRoute webClient: the runner result.'
        Assert-Equal $script:legacyRuns 1 'The web-client runner ran once.'
        Assert-Equal $run.Result[0].Routes.Tests.Route 'webClient' 'Route webClient.'
        Assert-Equal $run.Result[0].Routes.Build.Route 'n/a' 'No build route.'
        Assert-Equal $run.Result[0].Routes.Deploy.Route 'n/a' 'No deploy route.'
        Assert-True (@($run.Info | Where-Object { $_ -like 'TIMING: build=skipped * deploy=skipped *' }).Count -eq 1) 'TIMING shows skipped build and deploy.'

        # TestRoute altool but not available: stop.
        function Select-DeployRunVerifyTestRoute { [pscustomobject]@{ Route = 'webClient'; Reason = 'altool unavailable (x)'; Codeunits = [int[]]@(); AlTool = $null } }
        Assert-Throws { Invoke-AprodaDeployRunVerify -ConfigPath $configPath -RunOnly -TestRoute altool } 'ROUTE_UNAVAILABLE: tests=altool' 'Forced altool tests.' | Out-Null
        Assert-Equal $script:legacyRuns 1 'No web-client run after ROUTE_UNAVAILABLE.'

        # DeployRoute devEndpoint with the direct POST unavailable; DeployRoute altool without altool.
        . $publishMocks
        $cfg = New-DrvPublishCfg -DeployRoute devEndpoint
        $script:postOutcome = 'InvocationFailure'
        Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' } 'ROUTE_UNAVAILABLE: deploy=devEndpoint' 'Forced devEndpoint.' | Out-Null
        Assert-Equal $script:alToolCalls 0 'Forced devEndpoint never calls altool.'
        . $publishMocks
        $script:postOutcome = 'Published'
        Invoke-DeployRunVerifyPublishApp -Cfg $cfg -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0'
        Assert-Equal $script:postCalls 1 'Forced devEndpoint publishes through the POST.'
        Assert-Equal @($Script:DeployRunVerifyFallbacks).Count 0 'A forced route is not a fallback.'
        . $publishMocks
        function Get-DeployRunVerifyAlTool { [pscustomobject]@{ Path = $null; Version = $null; Source = 'none'; Error = 'ALTOOL_NOT_FOUND' } }
        Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg (New-DrvPublishCfg -DeployRoute altool) -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' } 'ROUTE_UNAVAILABLE: deploy=altool' 'Forced altool deploy.' | Out-Null
        . $publishMocks
        $script:alOutcome = 'InvocationFailure'
        Assert-Throws { Invoke-DeployRunVerifyPublishApp -Cfg (New-DrvPublishCfg -DeployRoute altool) -AppFile 'x.app' -Name 'AppA' -Version '1.0.0.0' } 'ROUTE_UNAVAILABLE: deploy=altool' 'Forced altool deploy, invocation failure.' | Out-Null
        Assert-Equal $script:postCalls 0 'Forced altool never falls back to the POST.'
    }

    Invoke-TestCase 'S-4b.16b entry script validates the route environment variables' {
        $entryPath = Join-Path $repositoryRoot 'skills\skill-aproda-deploy-run-verify\scripts\Invoke-AprodaDeployRunVerify.ps1'
        $run = {
            param($Name, $Value)
            $previous = [Environment]::GetEnvironmentVariable($Name)
            try {
                $env:APRODA_DEPLOY_RUN_VERIFY_CONFIG = 'C:\nonexistent\deploy-run-verify.config.jsonc'
                $env:APRODA_DEPLOY_RUN_VERIFY_MODULE = $enginePath
                [Environment]::SetEnvironmentVariable($Name, $Value)
                $child = 'try { Get-Content -LiteralPath $env:DRV_ENTRY -Raw | Invoke-Expression } catch { $_.Exception.Message }'
                $env:DRV_ENTRY = $entryPath
                $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($child))
                return (& $pwshPath -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String).Trim()
            }
            finally {
                [Environment]::SetEnvironmentVariable($Name, $previous)
                Remove-Item Env:\DRV_ENTRY -ErrorAction SilentlyContinue
                Remove-Item Env:\APRODA_DEPLOY_RUN_VERIFY_CONFIG -ErrorAction SilentlyContinue
            }
        }
        Assert-True ((& $run 'APRODA_DEPLOY_RUN_VERIFY_FORCE_UPGRADE' 'yes') -like '*FORCE_UPGRADE must be empty or ''1''*') 'FORCE_UPGRADE value.'
        Assert-True ((& $run 'APRODA_DEPLOY_RUN_VERIFY_TEST_ROUTE' 'bogus') -like '*TEST_ROUTE must be auto, altool or webClient*') 'TEST_ROUTE value.'
        Assert-True ((& $run 'APRODA_DEPLOY_RUN_VERIFY_DEPLOY_ROUTE' 'webClient') -like '*DEPLOY_ROUTE must be auto, altool or devEndpoint*') 'DEPLOY_ROUTE value.'
        # Valid values pass validation and reach the (missing) config.
        Assert-True ((& $run 'APRODA_DEPLOY_RUN_VERIFY_TEST_ROUTE' 'webClient') -like '*Config not found*') 'A valid route reaches the engine.'
    }

    Invoke-TestCase 'S-4b.17 cleanup candidate selection' {
        $rows = @(
            [pscustomobject]@{ Name = 'Base'; Publisher = 'P'; Version = '25.0.0.158'; Scope = 'Tenant'; IsInstalled = $true; SyncState = 'Synced' },
            [pscustomobject]@{ Name = 'Base'; Publisher = 'P'; Version = '25.0.0.156'; Scope = 'Tenant'; IsInstalled = $false; SyncState = 'NotSynced' },
            [pscustomobject]@{ Name = 'Base'; Publisher = 'P'; Version = '25.0.0.150'; Scope = 'Tenant'; IsInstalled = $false; SyncState = 'Synced' },
            [pscustomobject]@{ Name = 'Base'; Publisher = 'P'; Version = '24.0.0.1'; Scope = 'Global'; IsInstalled = $false; SyncState = 'Synced' },
            [pscustomobject]@{ Name = 'Base'; Publisher = 'P'; Version = '23.0.0.1'; Scope = 'Global'; IsInstalled = $true; SyncState = 'Synced' },
            [pscustomobject]@{ Name = 'Test'; Publisher = 'P'; Version = '1.0.0.0'; Scope = 'Tenant'; IsInstalled = $false; SyncState = '' })
        $selected = @(Select-DeployRunVerifyCleanupCandidates -Rows $rows)
        Assert-Equal $selected.Count 6 'One row per input row.'
        Assert-True ($selected[0].Candidate -eq $false -and $selected[0].Reason -like 'installed*') 'Installed: never a candidate.'
        Assert-True ($selected[1].Candidate -eq $true -and $selected[1].Reason -like '*NotSynced*') 'NotSynced leftover.'
        Assert-True ($selected[2].Candidate -eq $true -and $selected[2].Reason -like '*SyncState=Synced*') 'Not installed, synced.'
        Assert-True ($selected[3].Candidate -eq $true -and $selected[3].Reason -like '*Global scope*every tenant*') 'Global scope warning.'
        Assert-True ($selected[4].Candidate -eq $false) 'Installed Global: never a candidate.'
        Assert-True ($selected[5].Candidate -eq $true -and $selected[5].Reason -like '*no tenant state*') 'No tenant state.'
        Assert-Equal @(Select-DeployRunVerifyCleanupCandidates -Rows @()).Count 0 'No rows.'
        Assert-Throws { Get-DeployRunVerifyCleanupCandidates -Cfg ([pscustomobject]@{ adapter = 'Fkh' }) } 'CLEANUP_ASINST_ONLY' 'Fkh listing.' | Out-Null
        Assert-Throws { Remove-DeployRunVerifyAppVersion -Cfg ([pscustomobject]@{ adapter = 'Fkh' }) -Name 'x' -Publisher 'p' -Version '1.0.0.0' } 'CLEANUP_ASINST_ONLY' 'Fkh removal.' | Out-Null
    }

    Invoke-TestCase 'S-4b.18 dependency install goes through the publish chain on both adapters' {
        $appFile = Join-Path $drvTempRoot 'Dependency_1.0.0.0.app'
        [System.IO.File]::WriteAllBytes($appFile, [byte[]](1..8))
        $script:published = @()
        function Get-DeployRunVerifyPublishContext { param($Cfg) [pscustomobject]@{ BackendUrl = 'b'; AppLabel = 'l' } }
        function Invoke-DeployRunVerifyPublishApp { param($Cfg, $AppFile, $Name, $Version, $Context, [switch]$ForceUpgrade) $script:published += "$($Cfg.adapter):$Name $Version" }
        foreach ($adapter in 'Asinst', 'Fkh') {
            $cfg = New-DrvPublishCfg -Adapter $adapter
            Invoke-Captured { Install-DeployRunVerifyResolvedDependency -Cfg $cfg -AppFile $appFile -Name 'Dep' -Version '1.0.0.0' } | Out-Null
        }
        Assert-Equal ($script:published -join ';') 'Asinst:Dep 1.0.0.0;Fkh:Dep 1.0.0.0' 'Both adapters publish through the chain.'
        Assert-Throws { Install-DeployRunVerifyResolvedDependency -Cfg (New-DrvPublishCfg) -AppFile (Join-Path $drvTempRoot 'missing.app') -Name 'Dep' -Version '1' } 'Resolved dependency file not found' 'Missing file.' | Out-Null
    }

    Invoke-TestCase 'S-4b.19 ASINST publish context needs mgmtDllPath before any publish' {
        $cfg = New-DrvPublishCfg
        Assert-Throws { Get-DeployRunVerifyPublishContext -Cfg $cfg } 'mgmtDllPath is required for the ASINST adapter' 'No mgmtDllPath.' | Out-Null
        $cfg | Add-Member mgmtDllPath 'D:\x\Microsoft.Dynamics.Nav.Management.dll' -Force
        Assert-Null (Get-DeployRunVerifyPublishContext -Cfg $cfg) 'ASINST needs no context object.'
    }

    Write-Host "PASS: $script:passed offline Deploy-Run-Verify test case(s)."
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:APRODA_DEPLOY_RUN_VERIFY_MODULE = $originalEngineModule
    Remove-Item -LiteralPath $testStoreRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $drvTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}