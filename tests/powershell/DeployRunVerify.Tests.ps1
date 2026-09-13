$repositoryRoot = $env:APRODA_TEST_REPOSITORY_ROOT
if ([string]::IsNullOrWhiteSpace($repositoryRoot)) {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$credentialStorePath = Join-Path $repositoryRoot 'skills\skill-aproda-fkh\scripts\FkhCredentialStore.ps1'
$enginePath = Join-Path $repositoryRoot 'skills\skill-aproda-deploy-run-verify\scripts\AprodaDeployRunVerify.psm1'
$testStoreRoot = Join-Path $env:TEMP ('aproda-fkh-tests-' + [guid]::NewGuid().ToString('N'))
$originalLocalAppData = $env:LOCALAPPDATA

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
    . ([scriptblock]::Create($engineContent))

    Invoke-TestCase 'adapter selection requires HTTPS cloudapp target for Fkh' {
        Assert-Equal (Get-DeployRunVerifyAdapter -Cfg ([pscustomobject]@{ scheme = 'https'; server = 'sample.cloudapp.azure.com' })) 'Fkh' 'HTTPS cloudapp target did not select Fkh.'
        Assert-Equal (Get-DeployRunVerifyAdapter -Cfg ([pscustomobject]@{ scheme = 'http'; server = 'sample.cloudapp.azure.com' })) 'Asinst' 'HTTP cloudapp target selected Fkh.'
        Assert-Equal (Get-DeployRunVerifyAdapter -Cfg ([pscustomobject]@{ scheme = 'https'; server = 'sample.example.com' })) 'Asinst' 'Non-cloudapp target selected Fkh.'
    }

    Invoke-TestCase 'XUnit summary counts passed and failed tests' {
        $result = [pscustomobject]@{
            stage = 'ran'
            ok = $true
            error = ''
            xml = '<tests><test name="passes" result="Pass"/><test name="fails" result="Fail"/></tests>'
        }

        $summary = Get-DeployRunVerifySummary -ResultObject $result

        Assert-Equal $summary.Stage 'ran' 'Summary stage mismatch.'
        Assert-Equal $summary.Total 2 'Summary total mismatch.'
        Assert-Equal $summary.Passed 1 'Summary passed count mismatch.'
        Assert-Equal $summary.Failed 1 'Summary failed count mismatch.'
        Assert-Contains $summary.Failures 'fails' 'Summary failures mismatch.'
    }

    Write-Host "PASS: $script:passed offline Deploy-Run-Verify test case(s)."
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $testStoreRoot -Recurse -Force -ErrorAction SilentlyContinue
}