# E-012: skill-aproda-bc-data-access library + layer checks (S-12.1 .. S-12.28, S-12.L1 .. S-12.L9).
# Self-contained harness, no Pester (only Pester 3.4 is installed). Run content-based (SRP-safe), pwsh 7:
#   $env:APRODA_TEST_REPOSITORY_ROOT = '<repo>'
#   Get-Content -LiteralPath tests\powershell\BcDataAccess.Tests.ps1 -Raw | Invoke-Expression
# HTTP, login, clock and delays are replaced by fakes; no network call is made.

Set-StrictMode -Version Latest

$repositoryRoot = $env:APRODA_TEST_REPOSITORY_ROOT
if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$skillRoot = Join-Path $repositoryRoot 'skills\skill-aproda-bc-data-access'
$libraryPath = Join-Path $skillRoot 'scripts\BcDataAccess.ps1'
$appRoot = Join-Path $repositoryRoot 'tools\aproda-bc-data-access\app'
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP ('aproda-bcda-tests-' + [guid]::NewGuid().ToString('N'))))
$originalSessionDir = $env:BCDA_SESSION_DIR

$script:passed = 0
$script:failed = [System.Collections.Generic.List[string]]::new()
$script:allText = [System.Collections.Generic.List[string]]::new()

function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Test)
    try {
        $out = & $Test *>&1 | Out-String
        $script:allText.Add($out)
        $script:passed++
        Write-Host "PASS: $Name"
    }
    catch {
        $script:failed.Add($Name)
        Write-Host "FAIL: $Name"
        Write-Host "      $($_.Exception.Message)"
    }
}

function Assert-True { param($Condition, [string]$Message) if (-not $Condition) { throw $Message } }

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if (-not ($Actual -ceq $Expected)) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$CodePrefix, [string]$Message)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught) { throw "$Message Expected an error starting with '$CodePrefix' but nothing was thrown." }
    $script:allText.Add($caught)
    if (-not $caught.StartsWith($CodePrefix, [System.StringComparison]::Ordinal)) { throw "$Message Expected an error starting with '$CodePrefix', got '$caught'." }
    $caught
}

function Write-TestFile {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-B64Url { param([string]$Text) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }

# ---------------------------------------------------------------- library + fakes
. ([ScriptBlock]::Create((Get-Content -LiteralPath $libraryPath -Raw)))

$tenant = '11111111-2222-3333-4444-555555555555'
$company = 'c0c0c0c0-0000-0000-0000-000000000001'
$appId = 'a1a1a1a1-0000-0000-0000-00000000a001'
$appName = 'Aproda BC Data Access'
$publisher = 'Aproda AG'
$refreshSecret = 'RT-SECRET-0123456789'
$authCodeSecret = 'AUTH-CODE-SECRET-42'

$script:clock = [DateTimeOffset]::Parse('2026-11-13T10:00:00Z')
$script:calls = [System.Collections.Generic.List[object]]::new()
$script:loginPosts = [System.Collections.Generic.List[object]]::new()
$script:authUrl = $null
$script:forceState = $null
$script:fake = $null
$script:fakeToken = $null

function Get-BcdaNow { $script:clock }
function Wait-BcdaDelay { param([double]$Seconds) $script:clock = $script:clock.AddSeconds($Seconds) }
function Get-BcdaFreePort { 50123 }

function Receive-BcdaAuthCode {
    param([string]$AuthUrl, [string]$RedirectUri, [int]$TimeoutSec)
    $script:authUrl = $AuthUrl
    $state = if ($script:forceState) { $script:forceState } else { ([regex]::Match($AuthUrl, '[?&]state=([0-9a-f]+)')).Groups[1].Value }
    @{ code = $authCodeSecret; state = $state; error = $null; error_description = $null }
}

function Invoke-BcdaLoginPost {
    param([string]$Uri, [hashtable]$Body)
    $script:loginPosts.Add([pscustomobject]@{ Uri = $Uri; Body = $Body })
    [pscustomobject]@{ access_token = $script:fakeToken; refresh_token = $refreshSecret; expires_in = 3600; token_type = 'Bearer' }
}

function New-FakeToken {
    param([DateTimeOffset]$Expires)
    (ConvertTo-B64Url '{"alg":"none","typ":"JWT"}') + '.' + (ConvertTo-B64Url ('{"aud":"https://api.businesscentral.dynamics.com","exp":' + $Expires.ToUnixTimeSeconds() + '}')) + '.c2ln'
}

function New-Pkg {
    param([string]$PackageId = ([guid]::NewGuid().ToString()), [string]$Id = $appId, [string]$Name = $appName, [string]$Pub = $publisher,
        [string]$As = ' PTE', [bool]$Installed = $true, [int[]]$Version = @(1, 0, 0, 0))
    [ordered]@{ packageId = $PackageId; id = $Id; displayName = $Name; publisher = $Pub; publishedAs = $As; isInstalled = $Installed
        versionMajor = $Version[0]; versionMinor = $Version[1]; versionBuild = $Version[2]; versionRevision = $Version[3] }
}

function New-Response {
    param([int]$Status, $Object)
    $raw = if ($null -ne $Object) { $Object | ConvertTo-Json -Depth 20 -Compress } else { '' }
    [pscustomobject]@{ Status = $Status; Raw = $raw; Json = $(if ($raw) { $raw | ConvertFrom-Json -Depth 20 } else { $null }) }
}

function Invoke-BcdaHttp {
    param([string]$Method = 'GET', [string]$Uri, [string]$Body, [string]$ContentType, [hashtable]$Headers = @{}, [string]$InFile)
    $script:calls.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body; ContentType = $ContentType; Headers = $Headers; InFile = $InFile })
    $f = $script:fake
    if ($Method -eq 'POST' -and $Uri -match '/dataRequests$') {
        $next = if ($f.dataQueue.Count) { $f.dataQueue[0] } else { $null }
        if ($f.dataQueue.Count) { $f.dataQueue.RemoveAt(0) }
        if ($next -is [scriptblock]) { return & $next $Body }
        if ($next -is [int]) {
            if ($next -eq 404) { return New-Response 404 @{ error = @{ code = 'BadRequest_NotFound'; message = 'No HTTP resource was found that matches the request URI.' } } }
            return New-Response $next @{ error = @{ code = 'BadRequest'; message = 'Field NoSuchField was not found in table Payment Terms.' } }
        }
        $id = ($Body | ConvertFrom-Json).id
        return New-Response 201 @{ id = $id; result = '[{"tableNo":3,"tableName":"Payment Terms","records":[{"Code":"10D"},{"Code":"30D"}]}]' }
    }
    if ($Uri -match '/automation/v2\.0/companies$') { return New-Response 200 @{ value = @(@{ id = $company; name = 'Test Co'; displayName = 'Test Co' }) } }
    if ($Uri -match '/extensions\?\$filter=id eq ([0-9a-fA-F-]+)$') {
        $id = $Matches[1]
        return New-Response 200 @{ value = @($f.packages | Where-Object { $_.id -eq $id } | ForEach-Object { @{ packageId = $_.packageId; id = $_.id } }) }
    }
    if ($Uri -match '/extensions\(([^)]+)\)/Microsoft\.NAV\.(\w+)$') {
        $pid_ = $Matches[1]; $action = $Matches[2]
        $p = @($f.packages | Where-Object { $_.packageId -eq $pid_ })
        if ($f.actionReturns404 -or -not $p.Count) {
            $f.packages = @($f.packages | Where-Object { $_.packageId -ne $pid_ })
            return New-Response 404 @{ error = @{ code = 'BadRequest_ResourceNotFound'; message = "Resource not found for the segment 'extensions'." } }
        }
        switch ($action) {
            'uninstallAndDeleteExtensionData' { $p[0].isInstalled = $false }
            'unpublish' { $f.packages = @($f.packages | Where-Object { $_.packageId -ne $pid_ }) }
        }
        return New-Response 204 $null
    }
    if ($Uri -match '/extensions\(([^)]+)\)$') {
        $pid_ = $Matches[1]
        $p = @($f.packages | Where-Object { $_.packageId -eq $pid_ })
        if (-not $p.Count) { return New-Response 404 @{ error = @{ code = 'BadRequest_ResourceNotFound'; message = "Resource not found for the segment 'extensions'." } } }
        return New-Response 200 $p[0]
    }
    if ($Method -eq 'POST' -and $Uri -match '/extensionUpload$') { return New-Response 201 @{ systemId = 'eeeeeeee-0000-0000-0000-000000000001' } }
    if ($Method -eq 'PATCH' -and $Uri -match '/extensionContent$') { return New-Response 204 $null }
    if ($Method -eq 'POST' -and $Uri -match '/Microsoft\.NAV\.upload$') {
        $f.deployPolls = 0
        $f.deployRow = [ordered]@{ name = $appName; appVersion = '1.0.0.0'; status = 'InProgress'; operationType = 'Upload'; startedOn = $script:clock.ToString('o') }
        return New-Response 200 $null
    }
    if ($Uri -match '/extensionDeploymentStatus$') {
        $f.deployPolls++
        if ($f.deployRow -and $f.deployPolls -ge $f.completeAfter -and $f.deployRow.status -eq 'InProgress' -and $f.deployOutcome -ne 'Never') {
            $f.deployRow.status = $f.deployOutcome
            if ($f.deployOutcome -eq 'Completed') { $f.packages = @($f.packages) + @(New-Pkg) }
        }
        $rows = @($f.extraRows) + @($(if ($f.deployRow) { $f.deployRow }))
        return New-Response 200 @{ value = @($rows | Where-Object { $_ }) }
    }
    throw "Fake: unexpected $Method $Uri"
}

function Reset-Fake {
    param([object[]]$Packages = @())
    $script:clock = [DateTimeOffset]::Parse('2026-11-13T10:00:00Z')
    $script:calls.Clear(); $script:loginPosts.Clear(); $script:authUrl = $null; $script:forceState = $null
    $script:fake = @{ packages = @($Packages); dataQueue = [System.Collections.Generic.List[object]]::new(); deployRow = $null; deployPolls = 0
        completeAfter = 2; deployOutcome = 'Completed'; extraRows = @(); actionReturns404 = $false }
    $script:fakeToken = New-FakeToken -Expires $script:clock.AddMinutes(73)
    $env:BCDA_SESSION_DIR = Join-Path $tempRoot ('s-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}

function New-TestSkill {
    param([switch]$WrongHash)
    $root = Join-Path $tempRoot ('skill-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $app = Join-Path $root 'assets\x.app'
    Write-TestFile -Path $app -Content ('fake app ' + [guid]::NewGuid())
    $hash = (Get-FileHash -LiteralPath $app -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($WrongHash) { $hash = '0' * 64 }
    $m = [ordered]@{ appId = $appId; name = $appName; publisher = $publisher; version = '1.0.0.0'; minimumApplication = '25.4.0.0'; file = 'x.app'; sha256 = $hash }
    Write-TestFile -Path (Join-Path $root 'assets\app-manifest.json') -Content ($m | ConvertTo-Json)
    $root
}

function Connect-Fake { param([string]$Skill) Connect-BcDataAccess -SkillRoot $Skill -TenantId $tenant -Environment 'Sandbox1' }

function Start-Fake { Start-BcDataAccessSession -CompanyId $company -EnvironmentType Sandbox -Purpose 'test' -Acknowledged }

function Get-PostActions { @($script:calls | Where-Object { $_.Method -eq 'POST' -and $_.Uri -match 'Microsoft\.NAV\.(uninstallAndDeleteExtensionData|unpublish|uninstall)$' }) }

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    $skill = New-TestSkill

    # ------------------------------------------------------------ guard and clean-up
    Invoke-TestCase 'S-12.1 guard accepts our package (publishedAs with leading space)' {
        $p = New-Pkg; Reset-Fake -Packages @($p); $null = Connect-Fake $skill
        $e = Assert-BcDataAccessPackage -PackageId $p.packageId -CompanyId $company
        Assert-Equal $e.packageId $p.packageId 'returned package'
    }

    Invoke-TestCase 'S-12.2 guard refuses each wrong attribute, no POST' {
        $variants = @(
            @{ Id = 'b2b2b2b2-0000-0000-0000-00000000b002' }, @{ Name = 'aproda BC Data Access' }, @{ Name = 'Aproda BC Data Access (prototype)' },
            @{ Pub = 'Aproda' }, @{ As = 'Dev' }, @{ As = ' Global' })
        foreach ($v in $variants) {
            $p = New-Pkg @v; Reset-Fake -Packages @($p); $null = Connect-Fake $skill
            $msg = Assert-Throws { Assert-BcDataAccessPackage -PackageId $p.packageId -CompanyId $company } 'BCDA: GUARD' "variant $($v.Keys)"
            Assert-True ($msg -match ($v.Keys | Select-Object -First 1).Replace('Pub', 'publisher').Replace('As', 'publishedAs').Replace('Name', 'displayName').Replace('Id', 'id')) "message names the attribute: $msg"
            Assert-Equal @($script:calls | Where-Object Method -ne 'GET').Count 0 'no write call'
        }
    }

    Invoke-TestCase 'S-12.3 guard refuses Data Administration (same publisher, PTE)' {
        $da = New-Pkg -Id 'd4d4d4d4-0000-0000-0000-00000000d004' -Name 'Data Administration'
        Reset-Fake -Packages @($da); $null = Connect-Fake $skill
        $null = Assert-Throws { Invoke-BcdaPackageAction -PackageId $da.packageId -Action uninstallAndDeleteExtensionData -CompanyId $company } 'BCDA: GUARD' 'DA'
        Assert-Equal @(Get-PostActions).Count 0 'no action call'
    }

    Invoke-TestCase 'S-12.4 guard: non-GUID and missing package' {
        Reset-Fake; $null = Connect-Fake $skill
        $null = Assert-Throws { Assert-BcDataAccessPackage -PackageId 'abc' -CompanyId $company } 'BCDA: GUARD' 'non-GUID'
        Assert-Equal $script:calls.Count 0 'no HTTP call for a non-GUID'
        $null = Assert-Throws { Invoke-BcdaPackageAction -PackageId ([guid]::NewGuid().ToString()) -Action unpublish -CompanyId $company } 'BCDA: GUARD' '404 lookup'
        Assert-Equal @(Get-PostActions).Count 0 'no action call'
    }

    Invoke-TestCase 'S-12.5 + S-12.8 clean-up order, data deletion, guard before every action' {
        $p1 = New-Pkg -Installed $true; $p2 = New-Pkg -Installed $false -Version 0, 9, 0, 0; $p3 = New-Pkg -Installed $false -Version 0, 8, 0, 0
        Reset-Fake -Packages @($p1, $p2, $p3); $null = Connect-Fake $skill
        $null = Start-Fake   # reuse path: installed version = manifest
        $script:calls.Clear()
        $msg = Stop-BcDataAccessSession
        Assert-True ("$msg".StartsWith('BCDA: CLEAN')) "result $msg"
        $actions = @(Get-PostActions)
        Assert-Equal $actions.Count 4 'one delete-data uninstall + three unpublish'
        Assert-True ($actions[0].Uri -match "extensions\($($p1.packageId)\)/Microsoft\.NAV\.uninstallAndDeleteExtensionData$") 'first: delete-data uninstall of the installed package'
        Assert-True (-not ($script:calls | Where-Object { $_.Uri -match 'Microsoft\.NAV\.uninstall$' })) 'never uninstall without data deletion'
        for ($i = 0; $i -lt $script:calls.Count; $i++) {
            $c = $script:calls[$i]
            if ($c.Method -eq 'POST' -and $c.Uri -match 'extensions\(([^)]+)\)/Microsoft\.NAV\.') {
                $pkgId = $Matches[1]; $prev = $script:calls[$i - 1]
                Assert-True ($prev.Method -eq 'GET' -and $prev.Uri -match "extensions\($pkgId\)$") "guard lookup directly before action on $pkgId"
            }
        }
        Assert-Equal $script:fake.packages.Count 0 'nothing left'
        Assert-True (-not (Test-Path (Join-Path $env:BCDA_SESSION_DIR 'session.json'))) 'session file deleted'
    }

    Invoke-TestCase 'S-12.6 clean-up tolerates 404 from actions' {
        $p1 = New-Pkg; Reset-Fake -Packages @($p1); $null = Connect-Fake $skill; $null = Start-Fake
        $script:fake.actionReturns404 = $true
        $msg = Stop-BcDataAccessSession
        Assert-True ("$msg".StartsWith('BCDA: CLEAN')) "result $msg"
    }

    Invoke-TestCase 'S-12.7 a foreign row under our app id (Dev copy) stops before any action' {
        $p1 = New-Pkg; $dev = New-Pkg -As 'Dev' -Installed $false
        Reset-Fake -Packages @($p1, $dev); $null = Connect-Fake $skill
        $null = Assert-Throws { Stop-BcDataAccessSession -CompanyId $company } 'BCDA: GUARD' 'Dev copy'
        Assert-Equal @(Get-PostActions).Count 0 'no action at all'
    }

    # ------------------------------------------------------------ install and readiness
    Invoke-TestCase 'S-12.9 asset hash mismatch: no upload' {
        Reset-Fake; $bad = New-TestSkill -WrongHash; $null = Connect-Fake $bad
        $null = Assert-Throws { Start-Fake } 'BCDA: ASSET_HASH_MISMATCH' 'hash'
        Assert-True (-not ($script:calls | Where-Object { $_.Uri -match 'extensionUpload' })) 'no extensionUpload'
    }

    Invoke-TestCase 'S-12.10 install happy path: exact sequence and bodies' {
        Reset-Fake; $null = Connect-Fake $skill
        $msg = Start-Fake
        Assert-True ("$msg".StartsWith('BCDA: READY')) "result $msg"
        $up = @($script:calls | Where-Object { $_.Uri -match '/extensionUpload$' })
        Assert-Equal $up.Count 1 'one extensionUpload'
        Assert-Equal $up[0].Body '{"schedule":"Current version","schemaSyncMode":"Add"}' 'upload body'
        $content = @($script:calls | Where-Object { $_.Uri -match '/extensionContent$' })[0]
        Assert-Equal $content.Method 'PATCH' 'content method'
        Assert-Equal $content.ContentType 'application/octet-stream' 'content type'
        Assert-Equal $content.Headers['If-Match'] '*' 'If-Match'
        Assert-Equal $content.InFile (Join-Path $skill 'assets\x.app') 'InFile'
        Assert-True ($script:calls | Where-Object { $_.Uri -match 'Microsoft\.NAV\.upload$' }) 'upload action'
        $order = @($script:calls | ForEach-Object { if ($_.Uri -match '/(extensionUpload|extensionContent|Microsoft\.NAV\.upload|extensionDeploymentStatus|dataRequests)$') { $Matches[1] } })
        Assert-Equal (($order | Select-Object -Unique) -join ',') 'extensionUpload,extensionContent,Microsoft.NAV.upload,extensionDeploymentStatus,dataRequests' 'call order'
        $s = Get-Content (Join-Path $env:BCDA_SESSION_DIR 'session.json') -Raw | ConvertFrom-Json
        Assert-True ($s.packageId) 'packageId recorded'
    }

    Invoke-TestCase 'S-12.11 deployment status: client-side filter, older and foreign rows ignored' {
        Reset-Fake; $null = Connect-Fake $skill
        $script:fake.completeAfter = 3
        $script:fake.extraRows = @(
            [ordered]@{ name = $appName; appVersion = '1.0.0.0'; status = 'Completed'; startedOn = $script:clock.AddHours(-1).ToString('o') },
            [ordered]@{ name = 'Other App'; appVersion = '1.0.0.0'; status = 'Completed'; startedOn = $script:clock.ToString('o') })
        $null = Start-Fake
        Assert-True ($script:fake.deployPolls -ge 3) "waited for our current row (polls $($script:fake.deployPolls))"
        Assert-True (-not ($script:calls | Where-Object { $_.Uri -match 'filter=name' })) 'no server-side name filter'
    }

    Invoke-TestCase 'S-12.12 deployment Failed: status surfaced, no readiness' {
        Reset-Fake; $null = Connect-Fake $skill; $script:fake.deployOutcome = 'Failed'
        $msg = Assert-Throws { Start-Fake } 'BCDA: INSTALL_FAILED' 'failed'
        Assert-True ($msg -match 'Failed') 'status in message'
        Assert-True (-not ($script:calls | Where-Object { $_.Uri -match 'dataRequests' })) 'no readiness'
    }

    Invoke-TestCase 'S-12.13 deployment timeout (10 min)' {
        Reset-Fake; $null = Connect-Fake $skill; $script:fake.deployOutcome = 'Never'
        $script:fakeToken = New-FakeToken -Expires $script:clock.AddHours(2); $null = Connect-Fake $skill
        $null = Assert-Throws { Start-Fake } 'BCDA: INSTALL_TIMEOUT' 'timeout'
    }

    Invoke-TestCase 'S-12.14 readiness: 404, 404, then ready (5-s steps)' {
        Reset-Fake; $null = Connect-Fake $skill
        $script:fake.dataQueue.Add(404); $script:fake.dataQueue.Add(404)
        $null = Start-Fake
        Assert-Equal @($script:calls | Where-Object { $_.Uri -match 'dataRequests' }).Count 3 'three readiness requests'
    }

    Invoke-TestCase 'S-12.15 readiness gives up after 3 min' {
        Reset-Fake; $null = Connect-Fake $skill
        for ($i = 0; $i -lt 100; $i++) { $script:fake.dataQueue.Add(404) }
        $null = Assert-Throws { Start-Fake } 'BCDA: API_NOT_FOUND' 'readiness'
        $n = @($script:calls | Where-Object { $_.Uri -match 'dataRequests' }).Count
        Assert-True ($n -ge 36 -and $n -le 38) "about 180 s / 5 s requests, got $n"
    }

    Invoke-TestCase 'S-12.16 start reuses an installed current version' {
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill
        $msg = Start-Fake
        Assert-True ("$msg".StartsWith('BCDA: REUSE')) "result $msg"
        Assert-True (-not ($script:calls | Where-Object { $_.Uri -match 'extensionUpload' })) 'no upload'
    }

    Invoke-TestCase 'S-12.17 start cleans another version, then installs' {
        Reset-Fake -Packages @((New-Pkg -Version 0, 9, 0, 0), (New-Pkg -Installed $false -Version 0, 8, 0, 0)); $null = Connect-Fake $skill
        $msg = Start-Fake
        Assert-True ("$msg".StartsWith('BCDA: READY')) "result $msg"
        $idxUpload = $script:calls.FindIndex({ param($c) $c.Uri -match '/extensionUpload$' })
        $idxLastAction = -1
        for ($i = 0; $i -lt $script:calls.Count; $i++) { if ($script:calls[$i].Uri -match 'Microsoft\.NAV\.(uninstallAndDeleteExtensionData|unpublish)$') { $idxLastAction = $i } }
        Assert-True ($idxLastAction -ge 0 -and $idxLastAction -lt $idxUpload) 'clean-up before upload'
        Assert-Equal @(Get-PostActions).Count 3 'one delete-data uninstall + two unpublish'
    }

    Invoke-TestCase 'S-12.18 start without -Acknowledged: no HTTP call' {
        Reset-Fake; $null = Connect-Fake $skill; $script:calls.Clear()
        $null = Assert-Throws { Start-BcDataAccessSession -CompanyId $company -EnvironmentType Production -Purpose 'x' } 'BCDA: NOT_ACKNOWLEDGED' 'ack'
        Assert-Equal $script:calls.Count 0 'no HTTP call'
    }

    # ------------------------------------------------------------ auth, query, secrets
    Invoke-TestCase 'S-12.19 authorize URL (PKCE S256) and state check' {
        Reset-Fake; $null = Connect-Fake $skill
        foreach ($part in 'response_type=code', 'code_challenge_method=S256', 'prompt=select_account', "client_id=$script:BcdaPublicClientId",
            [uri]::EscapeDataString('https://api.businesscentral.dynamics.com/.default offline_access'), [uri]::EscapeDataString('http://localhost:50123/')) {
            Assert-True ($script:authUrl.Contains($part)) "authorize URL contains $part"
        }
        $challenge = ([regex]::Match($script:authUrl, 'code_challenge=([^&]+)')).Groups[1].Value
        $verifier = $script:loginPosts[0].Body.code_verifier
        $expected = [Convert]::ToBase64String([Security.Cryptography.SHA256]::HashData([Text.Encoding]::ASCII.GetBytes($verifier))).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        Assert-Equal $challenge $expected 'challenge = S256(verifier)'
        Assert-Equal $script:loginPosts[0].Body.grant_type 'authorization_code' 'grant'
        Reset-Fake; $script:forceState = 'deadbeef'
        $null = Assert-Throws { Connect-Fake $skill } 'BCDA: LOGIN_ERROR state mismatch' 'state'
    }

    Invoke-TestCase 'S-12.20 token file holds the access token only; expiry from exp' {
        Reset-Fake; $msg = Connect-Fake $skill
        Assert-True ("$msg".StartsWith('BCDA: LOGIN_OK')) "result $msg"
        $tokenFile = Join-Path $env:BCDA_SESSION_DIR 'token.txt'
        Assert-Equal (Get-Content $tokenFile -Raw) $script:fakeToken 'token.txt'
        foreach ($file in Get-ChildItem $env:BCDA_SESSION_DIR -Recurse -File) {
            Assert-True (-not (Get-Content $file.FullName -Raw).Contains($refreshSecret)) "refresh token in $($file.Name)"
            Assert-True (-not (Get-Content $file.FullName -Raw).Contains($authCodeSecret)) "auth code in $($file.Name)"
        }
        $s = Get-Content (Join-Path $env:BCDA_SESSION_DIR 'session.json') -Raw | ConvertFrom-Json -AsHashtable
        Assert-Equal ([long]$s['tokenExpiresUnix']) $script:clock.AddMinutes(73).ToUnixTimeSeconds() 'expiry'
    }

    Invoke-TestCase 'S-12.21 expired token: TOKEN_EXPIRED, no HTTP call' {
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill; $null = Start-Fake
        $script:clock = $script:clock.AddMinutes(69); $script:calls.Clear()
        $null = Assert-Throws { Invoke-BcDataQuery -Request '{"tables":[]}' } 'BCDA: TOKEN_EXPIRED' 'expiry margin'
        Assert-Equal $script:calls.Count 0 'no HTTP call'
    }

    Invoke-TestCase 'S-12.22 every query sends a new id and the request as a string' {
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill; $null = Start-Fake; $script:calls.Clear()
        $req = '{"tables":[{"table":"Payment Terms","fields":["Code"],"top":10}]}'
        $r1 = Invoke-BcDataQuery -Request $req; $null = Invoke-BcDataQuery -Request $req
        $bodies = @($script:calls | Where-Object { $_.Uri -match 'dataRequests' } | ForEach-Object { $_.Body | ConvertFrom-Json })
        Assert-Equal $bodies.Count 2 'two posts'
        Assert-True ($bodies[0].id -and $bodies[1].id -and $bodies[0].id -ne $bodies[1].id) 'two different ids'
        Assert-Equal $bodies[0].request $req 'request string'
        Assert-Equal @($r1[0].records).Count 2 'parsed result'
    }

    Invoke-TestCase 'S-12.23 query 400: message verbatim' {
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill; $null = Start-Fake
        $script:fake.dataQueue.Add(400)
        $msg = Assert-Throws { Invoke-BcDataQuery -Request '{}' } 'BCDA: QUERY_ERROR' '400'
        Assert-True ($msg.Contains('Field NoSuchField was not found in table Payment Terms.')) "verbatim: $msg"
    }

    Invoke-TestCase 'S-12.24 query 404: one readiness cycle, then retry or API_NOT_FOUND' {
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill; $null = Start-Fake
        $script:fake.dataQueue.Add(404); $script:fake.dataQueue.Add(404)
        $r = Invoke-BcDataQuery -Request '{"tables":[]}'
        Assert-Equal @($r).Count 1 'recovered after readiness'
        for ($i = 0; $i -lt 100; $i++) { $script:fake.dataQueue.Add(404) }
        $null = Assert-Throws { Invoke-BcDataQuery -Request '{"tables":[]}' } 'BCDA: API_NOT_FOUND' 'gives up'
    }

    Invoke-TestCase 'S-12.25 -OutFile writes to out\ and returns counts only' {
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill; $null = Start-Fake
        $r = @(Invoke-BcDataQuery -Request '{"tables":[]}' -OutFile '..\..\escape.json')
        Assert-Equal $r[0].rows 2 'row count'
        Assert-True (-not $r[0].PSObject.Properties['records']) 'no data returned'
        Assert-Equal (Split-Path $r[0].file -Parent) (Join-Path $env:BCDA_SESSION_DIR 'out') 'file stays in out\'
    }

    Invoke-TestCase 'S-12.27 stop removes out, session and token; -KeepToken keeps the token' {
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill; $null = Start-Fake
        $null = Invoke-BcDataQuery -Request '{"tables":[]}' -OutFile 'r.json'
        $null = Stop-BcDataAccessSession
        foreach ($n in 'out', 'session.json', 'token.txt') { Assert-True (-not (Test-Path (Join-Path $env:BCDA_SESSION_DIR $n))) "$n removed" }
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill; $null = Start-Fake
        $null = Stop-BcDataAccessSession -KeepToken
        Assert-True (Test-Path (Join-Path $env:BCDA_SESSION_DIR 'token.txt')) 'token kept'
        $s = Get-Content (Join-Path $env:BCDA_SESSION_DIR 'session.json') -Raw | ConvertFrom-Json -AsHashtable
        Assert-True (-not $s.Contains('companyId') -and -not $s.Contains('packageId')) 'session reset'
    }

    Invoke-TestCase 'S-12.28 session folder: no secret field, no script files' {
        Reset-Fake -Packages @(New-Pkg); $null = Connect-Fake $skill; $null = Start-Fake
        $s = Get-Content (Join-Path $env:BCDA_SESSION_DIR 'session.json') -Raw
        Assert-True ($s -notmatch '(?i)"[^"]*(token|secret|refresh|password)[^"]*"\s*:' -or $s -match '"tokenExpiresAt"') 'no secret-like key'
        Assert-True (-not $s.Contains($script:fakeToken)) 'no token value in session.json'
        Assert-Equal @(Get-ChildItem $tempRoot -Recurse -File -Include *.ps1, *.psm1).Count 0 'no script file in session folders'
    }

    Invoke-TestCase 'S-12.26 secret scan over all captured output' {
        $joined = $script:allText -join "`n"
        Assert-True (-not $joined.Contains($script:fakeToken)) 'token value'
        Assert-True ($joined -notmatch 'Bearer\s') 'Bearer header'
        Assert-True (-not $joined.Contains($refreshSecret)) 'refresh token'
        Assert-True (-not $joined.Contains($authCodeSecret)) 'auth code'
        Assert-True ($joined -notmatch 'eyJ') 'JWT prefix'
    }

    # ------------------------------------------------------------ layer
    Invoke-TestCase 'S-12.L1 SKILL.md frontmatter and no BOM' {
        $md = Get-Content (Join-Path $skillRoot 'SKILL.md') -Raw
        Assert-True ($md -match '(?s)^---\s*\r?\nname:\s*skill-aproda-bc-data-access\s*\r?\ndescription:\s*".+?"\s*\r?\n---') 'frontmatter name/description'
        $files = @(Get-ChildItem $skillRoot -Recurse -File | Where-Object Extension -ne '.app') + @(Get-ChildItem (Join-Path $repositoryRoot 'tools\aproda-bc-data-access') -Recurse -File |
                Where-Object { $_.Extension -ne '.app' -and $_.FullName -notmatch '\\\.alpackages\\' }) + @(Get-Item (Join-Path $repositoryRoot 'tests\powershell\BcDataAccess.Tests.ps1'))
        foreach ($f in $files) { $b = [IO.File]::ReadAllBytes($f.FullName); Assert-True (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) "BOM in $($f.Name)" }
    }

    Invoke-TestCase 'S-12.L2 no customer data in the shipped skill' {
        $manifest = Get-Content (Join-Path $skillRoot 'assets\app-manifest.json') -Raw | ConvertFrom-Json
        $allowed = @($manifest.appId, '1950a258-227b-4e31-a9cf-717495945fc2')
        foreach ($f in Get-ChildItem $skillRoot -Recurse -File | Where-Object Extension -ne '.app') {
            $t = Get-Content $f.FullName -Raw
            foreach ($g in [regex]::Matches($t, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')) {
                Assert-True ($allowed -contains $g.Value.ToLowerInvariant()) "foreign GUID $($g.Value) in $($f.Name)"
            }
            Assert-True ($t -notmatch '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') "e-mail address in $($f.Name)"
            foreach ($bad in '7391b259', 'e276d4c8', '14c13f57', 'ab23bc15', 'Gustav', 'Toga', 'Relesta') { Assert-True (-not $t.Contains($bad)) "'$bad' in $($f.Name)" }
        }
    }

    Invoke-TestCase 'S-12.L3 app-manifest matches the asset and app.json' {
        $m = Get-Content (Join-Path $skillRoot 'assets\app-manifest.json') -Raw | ConvertFrom-Json
        $asset = Join-Path $skillRoot "assets\$($m.file)"
        Assert-True (Test-Path -LiteralPath $asset) 'asset exists'
        Assert-Equal (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant() $m.sha256 'sha256'
        Assert-Equal @(Get-ChildItem (Join-Path $skillRoot 'assets') -Filter *.app).Count 1 'exactly one .app'
        $app = Get-Content (Join-Path $appRoot 'app.json') -Raw | ConvertFrom-Json
        Assert-Equal $m.version $app.version 'version'; Assert-Equal $m.appId $app.id 'id'; Assert-Equal $m.name $app.name 'name'; Assert-Equal $m.publisher $app.publisher 'publisher'
    }

    Invoke-TestCase 'S-12.L4 AL source: read-only, temporary table, ID range, names' {
        foreach ($f in Get-ChildItem (Join-Path $appRoot 'src') -Filter *.al) {
            $t = Get-Content $f.FullName -Raw
            $code = [regex]::Replace($t, '(?m)//.*$', '')
            foreach ($m in [regex]::Matches($code, '(\w+)\s*\.\s*(Insert|Modify|Delete|Rename|ModifyAll|DeleteAll)\s*\(')) {
                Assert-True ($m.Groups[1].Value -eq 'Rec' -and $code -match 'SourceTableTemporary\s*=\s*true') "write call $($m.Value) in $($f.Name)"
            }
            foreach ($bad in 'InherentPermissions', 'Commit\s*\(', 'EventSubscriber', 'HttpClient') { Assert-True ($code -notmatch $bad) "$bad in $($f.Name)" }
            if ($code -notmatch '(?m)^\s*permissionset\s') { Assert-True ($code -notmatch '(?m)^\s*Permissions\s*=') "Permissions property in $($f.Name)" }
            if ($code -match '(?m)^\s*table\s') { Assert-True ($code -match 'TableType\s*=\s*Temporary') "non-temporary table $($f.Name)" }
            $obj = [regex]::Match($code, '(?m)^\s*(table|page|codeunit|permissionset)\s+(\d+)\s+"([^"]+)"')
            Assert-True $obj.Success "object header in $($f.Name)"
            $id = [int]$obj.Groups[2].Value
            Assert-True ($id -ge 91050 -and $id -le 91099) "ID $id in $($f.Name)"
            Assert-True ($obj.Groups[3].Value -match '(^DA APD )|( DA APD$)') "name affix in $($f.Name)"
        }
    }

    Invoke-TestCase 'S-12.L5 AL compile: 0 errors, 0 warnings (maintainer symbols)' {
        $ext = Get-ChildItem (Join-Path $env:USERPROFILE '.vscode\extensions') -Directory -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue |
            Sort-Object { [version](($_.Name -replace '^ms-dynamics-smb\.al-', '') -replace '-.*$', '') } -Descending | Select-Object -First 1
        $alc = if ($ext) { Join-Path $ext.FullName 'bin\alc.exe' } else { $null }
        if (-not $alc -or -not (Test-Path $alc) -or -not (Test-Path (Join-Path $appRoot '.alpackages'))) { Write-Host '      SKIP: alc.exe or app\.alpackages not available'; return }
        $out = Join-Path $tempRoot 'build.app'
        $log = & $alc /project:"$appRoot" /packagecachepath:"$(Join-Path $appRoot '.alpackages')" /out:"$out" 2>&1 | Out-String
        Assert-Equal $LASTEXITCODE 0 "alc exit: $log"
        Assert-True ($log -notmatch '(?i)\bwarning\b|\berror\b') "diagnostics: $log"
    }

    Invoke-TestCase 'S-12.L8 catalogs list the skill' {
        foreach ($rel in 'skills\index.md', '.github\copilot-instructions.md', '.github\readme.aproda.md', 'aldc.yaml', 'docs\copilot-reference.md', 'tools\aproda-sync\templates\gitignore-block.txt') {
            Assert-True ((Get-Content (Join-Path $repositoryRoot $rel) -Raw).Contains('skill-aproda-bc-data-access')) "$rel"
        }
        Assert-True ((Get-Content (Join-Path $repositoryRoot 'tools\aproda-sync\aproda-sync.json') -Raw).Contains('tools/aproda-bc-data-access/**')) 'neverTouch'
        $ci = Get-Content (Join-Path $repositoryRoot '.github\copilot-instructions.md') -Raw
        Assert-True ($ci -match '23 skills \(7 🟦') 'footer/header count 23 / 7'
        Assert-True ($ci -notmatch '22 skills') 'no stale 22'
    }

    Invoke-TestCase 'S-12.L9 al-triage wiring and register' {
        $t = Get-Content (Join-Path $repositoryRoot 'agents\al-triage.agent.md') -Raw
        Assert-Equal ([regex]::Matches($t, 'skill-aproda-bc-data-access')).Count 2 'skill named in reproduce + diagnose'
        Assert-True ($t.Contains('Stop-BcDataAccessSession')) 'stop rule'
        Assert-True ($t -match '(?s)^---.*?\btools:') 'frontmatter intact'
        $d = Get-Content (Join-Path $repositoryRoot '.github\decisions.aproda.md') -Raw
        Assert-True ($d -match '\|\s*`agents/al-triage\.agent\.md`\s*\|[^\n]*D-55') 'D-7 register row for al-triage'
    }

    if ($script:failed.Count -gt 0) {
        throw "FAIL: $($script:failed.Count) of $($script:passed + $script:failed.Count) test case(s) failed: $($script:failed -join '; ')"
    }
    Write-Host "PASS: $script:passed BC data access test case(s), 0 failed."
}
finally {
    $env:BCDA_SESSION_DIR = $originalSessionDir
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
