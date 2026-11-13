# skill-aproda-bc-data-access — session library (E-012, D-55). PowerShell 7.
#
# Load content-based (SRP-safe), never by path:
#   . ([ScriptBlock]::Create((Get-Content -LiteralPath '<toolkitRoot>\skills\skill-aproda-bc-data-access\scripts\BcDataAccess.ps1' -Raw)))
#
# Public:  Connect-BcDataAccess, Get-BcDataAccessCompany, Start-BcDataAccessSession, Invoke-BcDataQuery,
#          Get-BcDataAccessState, Stop-BcDataAccessSession
# Lines meant for the agent start with 'BCDA:'. The access token is never returned, printed or logged.
# Session data lives in $env:TEMP\aproda-bcda (override: $env:BCDA_SESSION_DIR) — data files only, no scripts.

$script:BcdaPublicClientId = '1950a258-227b-4e31-a9cf-717495945fc2'
$script:BcdaScope = 'https://api.businesscentral.dynamics.com/.default offline_access'
$script:BcdaApiHost = 'https://api.businesscentral.dynamics.com'
$script:BcdaLoginHost = 'https://login.microsoftonline.com'
$script:BcdaReadinessRequest = '{"tables":[{"table":"Payment Terms","fields":["Code"],"top":1}]}'
$script:BcdaTokenMarginMinutes = 5

#region Replaceable hooks (tests redefine these after loading)

function Invoke-BcdaHttp {
    param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [string]$Body, [string]$ContentType = 'application/json',
        [hashtable]$Headers = @{}, [string]$InFile)
    $p = @{ Method = $Method; Uri = $Uri; Headers = $Headers; SkipHttpErrorCheck = $true; ErrorAction = 'Stop' }
    if ($InFile) { $p.InFile = $InFile; $p.ContentType = $ContentType }
    elseif ($PSBoundParameters.ContainsKey('Body')) { $p.Body = $Body; $p.ContentType = $ContentType }
    try { $r = Invoke-WebRequest @p }
    catch { throw "BCDA: HTTP_FAILED $Method $(([uri]$Uri).AbsolutePath): $($_.Exception.Message)" }
    $json = $null
    if ($r.Content) { try { $json = $r.Content | ConvertFrom-Json -Depth 50 } catch { $json = $null } }
    [pscustomobject]@{ Status = [int]$r.StatusCode; Raw = [string]$r.Content; Json = $json }
}

function Invoke-BcdaLoginPost {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][hashtable]$Body)
    try { Invoke-RestMethod -Method Post -Uri $Uri -Body $Body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop }
    catch {
        $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        throw "BCDA: LOGIN_ERROR $detail"
    }
}

function Receive-BcdaAuthCode {
    param([Parameter(Mandatory)][string]$AuthUrl, [Parameter(Mandatory)][string]$RedirectUri, [int]$TimeoutSec = 300)
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($RedirectUri)
    $listener.Start()
    try {
        Start-Process $AuthUrl
        $task = $listener.GetContextAsync()
        if (-not $task.Wait($TimeoutSec * 1000)) { throw "BCDA: LOGIN_TIMEOUT no sign-in within $TimeoutSec s" }
        $ctx = $task.Result
        $query = [System.Web.HttpUtility]::ParseQueryString($ctx.Request.Url.Query)
        $html = [Text.Encoding]::UTF8.GetBytes('<html><body>Sign-in finished. You can close this tab.</body></html>')
        $ctx.Response.ContentType = 'text/html'
        $ctx.Response.OutputStream.Write($html, 0, $html.Length)
        $ctx.Response.Close()
        @{ code = $query['code']; state = $query['state']; error = $query['error']; error_description = $query['error_description'] }
    }
    finally { $listener.Stop() }
}

function Get-BcdaNow { [DateTimeOffset]::UtcNow }

function Wait-BcdaDelay { param([double]$Seconds) Start-Sleep -Milliseconds ([int]($Seconds * 1000)) }

function Get-BcdaFreePort {
    $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $tcp.Start(); $port = $tcp.LocalEndpoint.Port; $tcp.Stop()
    $port
}

#endregion

#region Private helpers

function Get-BcdaProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function Get-BcdaSessionDir {
    $dir = if ($env:BCDA_SESSION_DIR) { $env:BCDA_SESSION_DIR } else { Join-Path $env:TEMP 'aproda-bcda' }
    [System.IO.Path]::GetFullPath($dir)
}

function Read-BcdaSession {
    $f = Join-Path (Get-BcdaSessionDir) 'session.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    Get-Content -LiteralPath $f -Raw | ConvertFrom-Json -AsHashtable
}

function Save-BcdaSession {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Session)
    $dir = Get-BcdaSessionDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'session.json'), ($Session | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
}

function Get-BcdaRequiredSession {
    $s = Read-BcdaSession
    if (-not $s) { throw 'BCDA: NOT_CONNECTED run Connect-BcDataAccess first' }
    $s
}

function ConvertTo-BcdaBase64Url { param([byte[]]$Bytes) [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_') }

function New-BcdaAuthRequest {
    param([Parameter(Mandatory)][string]$TenantId, [Parameter(Mandatory)][string]$ClientId, [Parameter(Mandatory)][int]$Port)
    $bytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $verifier = ConvertTo-BcdaBase64Url $bytes
    $challenge = ConvertTo-BcdaBase64Url ([Security.Cryptography.SHA256]::HashData([Text.Encoding]::ASCII.GetBytes($verifier)))
    $state = [guid]::NewGuid().ToString('N')
    $redirect = "http://localhost:$Port/"
    $url = "$script:BcdaLoginHost/$TenantId/oauth2/v2.0/authorize?client_id=$ClientId&response_type=code" +
        "&redirect_uri=$([uri]::EscapeDataString($redirect))&response_mode=query&scope=$([uri]::EscapeDataString($script:BcdaScope))" +
        "&code_challenge=$challenge&code_challenge_method=S256&prompt=select_account&state=$state"
    [pscustomobject]@{ Url = $url; Verifier = $verifier; Challenge = $challenge; State = $state; Redirect = $redirect }
}

function Get-BcdaJwtExpiry {
    param([Parameter(Mandatory)][string]$Token)
    $parts = $Token.Split('.')
    if ($parts.Count -lt 2) { throw 'BCDA: TOKEN_INVALID not a JWT' }
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    while ($payload.Length % 4) { $payload += '=' }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp)
}

function Save-BcdaToken {
    param([Parameter(Mandatory)][string]$AccessToken)
    $dir = Get-BcdaSessionDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'token.txt'), $AccessToken, [Text.Encoding]::ASCII)
}

function Get-BcdaToken {
    $s = Get-BcdaRequiredSession
    $f = Join-Path (Get-BcdaSessionDir) 'token.txt'
    if (-not (Test-Path -LiteralPath $f)) { throw 'BCDA: NOT_CONNECTED token missing, run Connect-BcDataAccess' }
    $expires = [DateTimeOffset]::FromUnixTimeSeconds([long]$s['tokenExpiresUnix'])
    if ($expires -le (Get-BcdaNow).AddMinutes($script:BcdaTokenMarginMinutes)) {
        throw "BCDA: TOKEN_EXPIRED token expires $($expires.ToLocalTime().ToString('HH:mm')) - run Connect-BcDataAccess again (the session and the app stay)"
    }
    (Get-Content -LiteralPath $f -Raw).Trim()
}

function Get-BcdaEnvBase {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Session)
    "$script:BcdaApiHost/v2.0/$($Session['tenantId'])/$($Session['environment'])"
}

function Get-BcdaErrorText {
    param([string]$Raw)
    if (-not $Raw) { return '' }
    try {
        $j = $Raw | ConvertFrom-Json -Depth 10
        $e = Get-BcdaProp $j 'error'
        if ($e) { return "$(Get-BcdaProp $e 'code'): $(Get-BcdaProp $e 'message')" }
    }
    catch { }
    if ($Raw.Length -gt 400) { $Raw.Substring(0, 400) } else { $Raw }
}

function Invoke-BcdaApi {
    param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [string]$Body, [string]$ContentType = 'application/json',
        [hashtable]$Headers = @{}, [string]$InFile)
    $h = @{ Authorization = 'Bearer ' + (Get-BcdaToken) }
    foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
    $p = @{ Method = $Method; Uri = $Uri; Headers = $h; ContentType = $ContentType }
    if ($InFile) { $p.InFile = $InFile }
    elseif ($PSBoundParameters.ContainsKey('Body')) { $p.Body = $Body }
    $r = Invoke-BcdaHttp @p
    if ($r.Status -eq 401) { throw 'BCDA: UNAUTHORIZED the token was refused - run Connect-BcDataAccess again' }
    $r
}

function Get-BcdaCompanyId {
    param([System.Collections.IDictionary]$Session, [string]$CompanyId)
    if ($CompanyId) { return $CompanyId }
    if ($Session['companyId']) { return $Session['companyId'] }
    throw 'BCDA: NO_COMPANY pass -CompanyId (see Get-BcDataAccessCompany)'
}

function Get-BcdaAutoBase {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Session, [Parameter(Mandatory)][string]$CompanyId)
    "$(Get-BcdaEnvBase $Session)/api/microsoft/automation/v2.0/companies($CompanyId)"
}

function Get-BcdaManifest {
    param([Parameter(Mandatory)][string]$SkillRoot)
    $f = Join-Path $SkillRoot 'assets\app-manifest.json'
    if (-not (Test-Path -LiteralPath $f)) { throw "BCDA: ASSET_MISSING $f" }
    Get-Content -LiteralPath $f -Raw | ConvertFrom-Json -AsHashtable
}

#endregion

#region Identity guard and clean-up (D-55 item 6)

function Assert-BcDataAccessPackage {
    param([Parameter(Mandatory)][string]$PackageId, [string]$CompanyId)
    $s = Get-BcdaRequiredSession
    if ($PackageId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { throw "BCDA: GUARD '$PackageId' is not a GUID - no call" }
    $c = Get-BcdaCompanyId -Session $s -CompanyId $CompanyId
    $r = Invoke-BcdaApi -Uri "$(Get-BcdaAutoBase $s $c)/extensions($PackageId)"
    if ($r.Status -ne 200) { throw "BCDA: GUARD lookup of package $PackageId returned HTTP $($r.Status) - no call" }
    $e = $r.Json
    $fails = @()
    if ("$(Get-BcdaProp $e 'id')" -ne $s['appId']) { $fails += "id='$(Get-BcdaProp $e 'id')'" }
    if ("$(Get-BcdaProp $e 'displayName')" -cne $s['appName']) { $fails += "displayName='$(Get-BcdaProp $e 'displayName')'" }
    if ("$(Get-BcdaProp $e 'publisher')" -cne $s['appPublisher']) { $fails += "publisher='$(Get-BcdaProp $e 'publisher')'" }
    if ("$(Get-BcdaProp $e 'publishedAs')".Trim() -ne 'PTE') { $fails += "publishedAs='$("$(Get-BcdaProp $e 'publishedAs')".Trim())'" }
    if ($fails) { throw "BCDA: GUARD package $PackageId is not ours ($($fails -join ', ')) - no call" }
    $e
}

function Get-BcDataAccessPackages {
    param([string]$CompanyId)
    $s = Get-BcdaRequiredSession
    $c = Get-BcdaCompanyId -Session $s -CompanyId $CompanyId
    $r = Invoke-BcdaApi -Uri "$(Get-BcdaAutoBase $s $c)/extensions?`$filter=id eq $($s['appId'])"
    if ($r.Status -ne 200) { throw "BCDA: STATE_READ_FAILED HTTP $($r.Status) $(Get-BcdaErrorText $r.Raw)" }
    foreach ($row in @(Get-BcdaProp $r.Json 'value')) {
        if ($null -eq $row) { continue }
        $e = Assert-BcDataAccessPackage -PackageId "$(Get-BcdaProp $row 'packageId')" -CompanyId $c
        [pscustomobject]@{
            packageId   = "$(Get-BcdaProp $e 'packageId')"
            version     = '{0}.{1}.{2}.{3}' -f (Get-BcdaProp $e 'versionMajor'), (Get-BcdaProp $e 'versionMinor'), (Get-BcdaProp $e 'versionBuild'), (Get-BcdaProp $e 'versionRevision')
            isInstalled = [bool](Get-BcdaProp $e 'isInstalled')
        }
    }
}

function Invoke-BcdaPackageAction {
    param([Parameter(Mandatory)][string]$PackageId, [Parameter(Mandatory)][ValidateSet('uninstallAndDeleteExtensionData', 'unpublish')][string]$Action,
        [Parameter(Mandatory)][string]$CompanyId)
    $null = Assert-BcDataAccessPackage -PackageId $PackageId -CompanyId $CompanyId
    $s = Get-BcdaRequiredSession
    Invoke-BcdaApi -Method POST -Uri "$(Get-BcdaAutoBase $s $CompanyId)/extensions($PackageId)/Microsoft.NAV.$Action"
}

function Wait-BcdaPackageUninstalled {
    param([Parameter(Mandatory)][string]$PackageId, [Parameter(Mandatory)][string]$CompanyId, [int]$TimeoutSec = 300)
    $s = Get-BcdaRequiredSession
    $start = Get-BcdaNow
    do {
        Wait-BcdaDelay 2
        $r = Invoke-BcdaApi -Uri "$(Get-BcdaAutoBase $s $CompanyId)/extensions($PackageId)"
        if ($r.Status -eq 404) { return }
        if ($r.Status -eq 200 -and -not [bool](Get-BcdaProp $r.Json 'isInstalled')) { return }
    } while (((Get-BcdaNow) - $start).TotalSeconds -lt $TimeoutSec)
    throw "BCDA: UNINSTALL_TIMEOUT package $PackageId still installed after $TimeoutSec s"
}

function Invoke-BcdaCleanup {
    param([Parameter(Mandatory)][string]$CompanyId)
    foreach ($p in @(Get-BcDataAccessPackages -CompanyId $CompanyId | Where-Object isInstalled)) {
        $r = Invoke-BcdaPackageAction -PackageId $p.packageId -Action uninstallAndDeleteExtensionData -CompanyId $CompanyId
        if ($r.Status -notin 200, 204, 404) { throw "BCDA: CLEANUP_FAILED uninstallAndDeleteExtensionData $($p.packageId): HTTP $($r.Status) $(Get-BcdaErrorText $r.Raw)" }
        if ($r.Status -ne 404) { Wait-BcdaPackageUninstalled -PackageId $p.packageId -CompanyId $CompanyId }
    }
    foreach ($p in @(Get-BcDataAccessPackages -CompanyId $CompanyId)) {
        $r = Invoke-BcdaPackageAction -PackageId $p.packageId -Action unpublish -CompanyId $CompanyId
        if ($r.Status -notin 200, 204, 404) { throw "BCDA: CLEANUP_FAILED unpublish $($p.packageId): HTTP $($r.Status) $(Get-BcdaErrorText $r.Raw)" }
    }
    $left = @(Get-BcDataAccessPackages -CompanyId $CompanyId)
    if ($left.Count) { throw "BCDA: CLEANUP_INCOMPLETE $($left.Count) package(s) left" }
}

#endregion

#region Install and readiness

function Test-BcdaApiReady {
    param([Parameter(Mandatory)][string]$CompanyId, [int]$TimeoutSec = 180)
    $s = Get-BcdaRequiredSession
    $uri = "$(Get-BcdaEnvBase $s)/api/aproda/bcDataAccess/v1.0/companies($CompanyId)/dataRequests"
    $start = Get-BcdaNow
    while ($true) {
        $body = [ordered]@{ id = [guid]::NewGuid().ToString(); request = $script:BcdaReadinessRequest } | ConvertTo-Json -Compress
        $r = Invoke-BcdaApi -Method POST -Uri $uri -Body $body
        if ($r.Status -ne 404) { return $true }
        if (((Get-BcdaNow) - $start).TotalSeconds -ge $TimeoutSec) { return $false }
        Wait-BcdaDelay 5
    }
}

function Install-BcdaApp {
    param([Parameter(Mandatory)][string]$CompanyId, [int]$InstallTimeoutSec = 600, [int]$ReadyTimeoutSec = 180)
    $s = Get-BcdaRequiredSession
    $appFile = Join-Path $s['skillRoot'] "assets\$($s['appFile'])"
    if (-not (Test-Path -LiteralPath $appFile)) { throw "BCDA: ASSET_MISSING $appFile" }
    $hash = (Get-FileHash -LiteralPath $appFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne "$($s['appSha256'])".ToLowerInvariant()) { throw "BCDA: ASSET_HASH_MISMATCH $($s['appFile']) - no upload" }

    $auto = Get-BcdaAutoBase $s $CompanyId
    $t0 = Get-BcdaNow
    $r = Invoke-BcdaApi -Method POST -Uri "$auto/extensionUpload" -Body '{"schedule":"Current version","schemaSyncMode":"Add"}'
    if ($r.Status -ne 201) { throw "BCDA: INSTALL_FAILED extensionUpload HTTP $($r.Status) $(Get-BcdaErrorText $r.Raw)" }
    $sid = "$(Get-BcdaProp $r.Json 'systemId')"
    $r = Invoke-BcdaApi -Method PATCH -Uri "$auto/extensionUpload($sid)/extensionContent" -InFile $appFile -ContentType 'application/octet-stream' -Headers @{ 'If-Match' = '*' }
    if ($r.Status -notin 200, 204) { throw "BCDA: INSTALL_FAILED extensionContent HTTP $($r.Status) $(Get-BcdaErrorText $r.Raw)" }
    $r = Invoke-BcdaApi -Method POST -Uri "$auto/extensionUpload($sid)/Microsoft.NAV.upload"
    if ($r.Status -notin 200, 204) { throw "BCDA: INSTALL_FAILED Microsoft.NAV.upload HTTP $($r.Status) $(Get-BcdaErrorText $r.Raw)" }

    # extensionDeploymentStatus is not filterable by name (HTTP 400) - filter client-side, newest row of this run.
    $since = $t0.AddMinutes(-2)
    $status = $null
    do {
        Wait-BcdaDelay 5
        $r = Invoke-BcdaApi -Uri "$auto/extensionDeploymentStatus"
        if ($r.Status -ne 200) { continue }
        $rows = @(@(Get-BcdaProp $r.Json 'value') | Where-Object {
                $null -ne $_ -and "$(Get-BcdaProp $_ 'name')" -eq $s['appName'] -and "$(Get-BcdaProp $_ 'appVersion')" -eq $s['appVersion'] -and
                [DateTimeOffset](Get-BcdaProp $_ 'startedOn') -ge $since
            } | Sort-Object { [DateTimeOffset](Get-BcdaProp $_ 'startedOn') })
        if ($rows.Count) { $status = $rows[-1] }
        $state = "$(Get-BcdaProp $status 'status')"
        if ($state -eq 'Failed') { throw "BCDA: INSTALL_FAILED deployment status Failed: $(($status | ConvertTo-Json -Compress -Depth 5))" }
        if ($state -eq 'Completed') { break }
    } while (((Get-BcdaNow) - $t0).TotalSeconds -lt $InstallTimeoutSec)
    if ("$(Get-BcdaProp $status 'status')" -ne 'Completed') { throw "BCDA: INSTALL_TIMEOUT not completed after $InstallTimeoutSec s - run Stop-BcDataAccessSession to clean up" }
    if (-not (Test-BcdaApiReady -CompanyId $CompanyId -TimeoutSec $ReadyTimeoutSec)) { throw "BCDA: API_NOT_FOUND the API did not answer within $ReadyTimeoutSec s after install" }
    [math]::Round(((Get-BcdaNow) - $t0).TotalSeconds)
}

#endregion

#region Public commands

function Connect-BcDataAccess {
    <# Browser sign-in (auth code + PKCE). The human signs in. Writes the token to the session folder. #>
    param([Parameter(Mandatory)][string]$SkillRoot, [Parameter(Mandatory)][string]$TenantId, [Parameter(Mandatory)][string]$Environment,
        [string]$ClientId = $script:BcdaPublicClientId, [switch]$DeviceCode, [int]$TimeoutSec = 300)
    $existing = Read-BcdaSession
    $sameTarget = $existing -and $existing['tenantId'] -eq $TenantId -and $existing['environment'] -eq $Environment
    if ($existing -and -not $sameTarget -and ($existing['companyId'] -or $existing['packageId'])) {
        throw "BCDA: SESSION_OPEN for $($existing['tenantId'])/$($existing['environment']) - run Stop-BcDataAccessSession first"
    }
    $manifest = Get-BcdaManifest -SkillRoot $SkillRoot
    $tokenUri = "$script:BcdaLoginHost/$TenantId/oauth2/v2.0/token"

    if ($DeviceCode) {
        $dc = Invoke-BcdaLoginPost -Uri "$script:BcdaLoginHost/$TenantId/oauth2/v2.0/devicecode" -Body @{ client_id = $ClientId; scope = $script:BcdaScope }
        Write-Output "BCDA: DEVICE_CODE $(Get-BcdaProp $dc 'message')"
        $deadline = (Get-BcdaNow).AddSeconds([int](Get-BcdaProp $dc 'expires_in'))
        $resp = $null
        while ((Get-BcdaNow) -lt $deadline) {
            Wait-BcdaDelay ([int](Get-BcdaProp $dc 'interval'))
            try {
                $resp = Invoke-BcdaLoginPost -Uri $tokenUri -Body @{ grant_type = 'urn:ietf:params:oauth:grant-type:device_code'; client_id = $ClientId; device_code = (Get-BcdaProp $dc 'device_code') }
                break
            }
            catch { if ("$_" -notmatch 'authorization_pending|slow_down') { throw } }
        }
        if (-not $resp) { throw 'BCDA: LOGIN_TIMEOUT device code expired' }
    }
    else {
        $req = New-BcdaAuthRequest -TenantId $TenantId -ClientId $ClientId -Port (Get-BcdaFreePort)
        $answer = Receive-BcdaAuthCode -AuthUrl $req.Url -RedirectUri $req.Redirect -TimeoutSec $TimeoutSec
        if ($answer.error) { throw "BCDA: LOGIN_ERROR $($answer.error) $($answer.error_description)" }
        if ($answer.state -ne $req.State) { throw 'BCDA: LOGIN_ERROR state mismatch' }
        $resp = Invoke-BcdaLoginPost -Uri $tokenUri -Body @{
            client_id = $ClientId; grant_type = 'authorization_code'; code = $answer.code; redirect_uri = $req.Redirect
            code_verifier = $req.Verifier; scope = $script:BcdaScope
        }
    }

    $access = "$(Get-BcdaProp $resp 'access_token')"
    if (-not $access) { throw 'BCDA: LOGIN_ERROR no access token in the response' }
    $expires = Get-BcdaJwtExpiry -Token $access
    Save-BcdaToken -AccessToken $access

    $session = if ($sameTarget) { $existing } else { @{} }
    $session['skillRoot'] = [System.IO.Path]::GetFullPath($SkillRoot)
    $session['tenantId'] = $TenantId
    $session['environment'] = $Environment
    $session['appId'] = $manifest.appId
    $session['appName'] = $manifest.name
    $session['appPublisher'] = $manifest.publisher
    $session['appVersion'] = $manifest.version
    $session['appFile'] = $manifest.file
    $session['appSha256'] = $manifest.sha256
    $session['tokenExpiresAt'] = $expires.ToLocalTime().ToString('yyyy-MM-dd HH:mm')
    $session['tokenExpiresUnix'] = $expires.ToUnixTimeSeconds()
    Save-BcdaSession -Session $session
    "BCDA: LOGIN_OK expires=$($expires.ToLocalTime().ToString('yyyy-MM-dd HH:mm'))"
}

function Get-BcDataAccessCompany {
    $s = Get-BcdaRequiredSession
    $r = Invoke-BcdaApi -Uri "$(Get-BcdaEnvBase $s)/api/microsoft/automation/v2.0/companies"
    if ($r.Status -ne 200) { throw "BCDA: HTTP $($r.Status) $(Get-BcdaErrorText $r.Raw)" }
    foreach ($c in @(Get-BcdaProp $r.Json 'value')) {
        if ($null -eq $c) { continue }
        [pscustomobject]@{ id = Get-BcdaProp $c 'id'; name = Get-BcdaProp $c 'name'; displayName = Get-BcdaProp $c 'displayName' }
    }
}

function Start-BcDataAccessSession {
    <# Installs (or reuses) the read-only app. Call only after the human acknowledged tenant, environment, type and purpose. #>
    param([Parameter(Mandatory)][string]$CompanyId, [Parameter(Mandatory)][ValidateSet('Sandbox', 'Production')][string]$EnvironmentType,
        [Parameter(Mandatory)][string]$Purpose, [switch]$Acknowledged, [int]$InstallTimeoutSec = 600, [int]$ReadyTimeoutSec = 180)
    if (-not $Acknowledged) { throw 'BCDA: NOT_ACKNOWLEDGED show the acknowledgement text to the human and pass -Acknowledged only after a yes' }
    $s = Get-BcdaRequiredSession
    $null = Get-BcdaToken
    if ($s['companyId'] -and $s['companyId'] -ne $CompanyId -and $s['packageId']) {
        throw "BCDA: SESSION_OPEN for company $($s['companyId']) - run Stop-BcDataAccessSession first"
    }
    $s['companyId'] = $CompanyId
    $s['environmentType'] = $EnvironmentType
    $s['purpose'] = $Purpose
    $s['acknowledgedAt'] = (Get-BcdaNow).ToString('o')
    Save-BcdaSession -Session $s

    $packages = @(Get-BcDataAccessPackages -CompanyId $CompanyId)
    $current = @($packages | Where-Object { $_.isInstalled -and $_.version -eq $s['appVersion'] })
    if ($current.Count) {
        if (-not (Test-BcdaApiReady -CompanyId $CompanyId -TimeoutSec $ReadyTimeoutSec)) { throw 'BCDA: API_NOT_FOUND the installed app does not answer' }
        $s['packageId'] = $current[0].packageId
        if (-not $s['installedAt']) { $s['installedAt'] = (Get-BcdaNow).ToString('o') }
        Save-BcdaSession -Session $s
        return "BCDA: REUSE app $($s['appVersion']) was already installed in $($s['environment']) (left by an earlier session) - ready"
    }
    if ($packages.Count) { Invoke-BcdaCleanup -CompanyId $CompanyId }

    $seconds = Install-BcdaApp -CompanyId $CompanyId -InstallTimeoutSec $InstallTimeoutSec -ReadyTimeoutSec $ReadyTimeoutSec
    $installed = @(Get-BcDataAccessPackages -CompanyId $CompanyId | Where-Object { $_.isInstalled -and $_.version -eq $s['appVersion'] })
    if (-not $installed.Count) { throw 'BCDA: INSTALL_FAILED the app is not listed as installed after Completed' }
    $s['packageId'] = $installed[0].packageId
    $s['installedAt'] = (Get-BcdaNow).ToString('o')
    Save-BcdaSession -Session $s
    "BCDA: READY app $($s['appVersion']) installed in $($s['environment']) ($EnvironmentType) in $seconds s"
}

function Invoke-BcDataQuery {
    <# Runs one read request. -Request: {"tables":[{"table":..,"fields":[..],"filters":[..],"top":n}]} #>
    param([Parameter(Mandatory)][string]$Request, [string]$OutFile, [int]$ReadyTimeoutSec = 180)
    $s = Get-BcdaRequiredSession
    $c = Get-BcdaCompanyId -Session $s
    $uri = "$(Get-BcdaEnvBase $s)/api/aproda/bcDataAccess/v1.0/companies($c)/dataRequests"
    $attempt = 0
    while ($true) {
        # Always a new id: without a Rec-bound field the API page does not run OnInsertRecord (E-012 F-19).
        $body = [ordered]@{ id = [guid]::NewGuid().ToString(); request = $Request } | ConvertTo-Json -Compress
        $r = Invoke-BcdaApi -Method POST -Uri $uri -Body $body
        if ($r.Status -ne 404 -or $attempt -ge 1) { break }
        $attempt++
        if (-not (Test-BcdaApiReady -CompanyId $c -TimeoutSec $ReadyTimeoutSec)) { break }
    }
    switch ($r.Status) {
        201 { }
        400 { throw "BCDA: QUERY_ERROR $(Get-BcdaErrorText $r.Raw)" }
        404 { throw 'BCDA: API_NOT_FOUND the data-access API is not available - run Start-BcDataAccessSession' }
        default { throw "BCDA: HTTP $($r.Status) $(Get-BcdaErrorText $r.Raw)" }
    }
    $resultText = "$(Get-BcdaProp $r.Json 'result')"
    if (-not $resultText) { throw 'BCDA: EMPTY_RESULT the API returned no result' }
    $result = @($resultText | ConvertFrom-Json -Depth 50)
    if ($OutFile) {
        $outDir = Join-Path (Get-BcdaSessionDir) 'out'
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        $target = Join-Path $outDir ([System.IO.Path]::GetFileName($OutFile))
        [IO.File]::WriteAllText($target, $resultText, [Text.UTF8Encoding]::new($false))
        return @($result | ForEach-Object { [pscustomobject]@{ tableName = $_.tableName; rows = @($_.records).Count; file = $target } })
    }
    $result
}

function Get-BcDataAccessState {
    $s = Get-BcdaRequiredSession
    $packages = if ($s['companyId']) { @(Get-BcDataAccessPackages -CompanyId $s['companyId']) } else { @() }
    [pscustomobject]@{
        tenantId        = $s['tenantId']
        environment     = $s['environment']
        environmentType = $s['environmentType']
        companyId       = $s['companyId']
        purpose         = $s['purpose']
        appVersion      = $s['appVersion']
        installedAt     = $s['installedAt']
        tokenExpiresAt  = $s['tokenExpiresAt']
        packages        = $packages
    }
}

function Stop-BcDataAccessSession {
    <# Guarded clean-up: uninstall with data deletion + unpublish of this app only; then the session files are removed. #>
    param([string]$CompanyId, [switch]$KeepToken)
    $s = Get-BcdaRequiredSession
    $c = Get-BcdaCompanyId -Session $s -CompanyId $CompanyId
    Invoke-BcdaCleanup -CompanyId $c
    $dir = Get-BcdaSessionDir
    $out = Join-Path $dir 'out'
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
    if ($KeepToken) {
        foreach ($k in 'companyId', 'environmentType', 'purpose', 'acknowledgedAt', 'packageId', 'installedAt') { $null = $s.Remove($k) }
        Save-BcdaSession -Session $s
    }
    else {
        foreach ($f in 'session.json', 'token.txt') {
            $p = Join-Path $dir $f
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
        }
    }
    "BCDA: CLEAN app removed from $($s['environment']) (uninstall with data deletion + unpublish); session files deleted"
}

#endregion
