param(
    [Parameter(Mandatory)]
    [string]$BaseProjectPath,
    [Parameter(Mandatory)]
    [string]$TestProjectPath
)

$ErrorActionPreference = 'Stop'
$credentialStorePath = Join-Path (Split-Path -Parent $BaseProjectPath) '.github\skills\skill-aproda-fkh\scripts\FkhCredentialStore.ps1'
$credentialKey = 'flobi-wan-kenobi-gustavgerig-dev.switzerlandnorth.cloudapp.azure.com'

$alToolCandidates = @(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.vscode\extensions') -Directory -Filter 'ms-dynamics-smb.al-*' |
    ForEach-Object {
        $extensionDirectory = $_
        $candidatePaths = @(
            (Join-Path -Path $extensionDirectory.FullName -ChildPath 'bin\altool.exe')
            (Join-Path -Path $extensionDirectory.FullName -ChildPath 'bin\win32\altool.exe')
        )
        $candidatePaths |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        ForEach-Object {
            [pscustomobject]@{
                Path             = $_
                ExtensionVersion = $extensionDirectory.Name
                LastWriteTimeUtc = $extensionDirectory.LastWriteTimeUtc
            }
        }
    } |
    Sort-Object LastWriteTimeUtc -Descending)

if (-not $alToolCandidates) {
    throw 'No altool.exe was found in an installed ms-dynamics-smb.al extension.'
}

$latestTimestamp = $alToolCandidates[0].LastWriteTimeUtc
$latestCandidates = @($alToolCandidates | Where-Object { $_.LastWriteTimeUtc -eq $latestTimestamp })
if ($latestCandidates.Count -ne 1) {
    throw "Cannot choose one altool.exe from the newest AL extension candidates: $($latestCandidates.Path -join '; ')."
}

$alToolPath = $latestCandidates[0].Path
$alToolDirectory = Split-Path -Parent $AlToolPath
$env:PATH = "$alToolDirectory;$env:PATH"

. ([ScriptBlock]::Create((Get-Content -LiteralPath $credentialStorePath -Raw -Encoding utf8)))
$credential = Get-FkhStoredCredential -Key $credentialKey
if (-not $credential) {
    throw "No Fkh credential is stored for '$credentialKey'."
}

$env:BC_SERVER_USERNAME = $credential.UserName
$env:BC_SERVER_PASSWORD = $credential.GetNetworkCredential().Password

& $AlToolPath launchmcpserver $BaseProjectPath $TestProjectPath --transport stdio
exit $LASTEXITCODE