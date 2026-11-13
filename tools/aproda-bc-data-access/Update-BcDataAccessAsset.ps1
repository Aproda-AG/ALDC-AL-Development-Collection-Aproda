#Requires -Version 7.0
<#
.SYNOPSIS
    Copies a freshly built "Aproda BC Data Access" .app into the skill's assets and rewrites app-manifest.json.

.DESCRIPTION
    Fork-only maintainer script (E-012, D-55). It reads the package manifest of the .app with
    `altool GetPackageManifest`, checks id/name/publisher/version against app/app.json, refuses a version that is
    not higher than the current asset (unless -AllowSameVersion), replaces the asset and writes the manifest with
    the SHA-256 that the skill verifies before every upload.

.PARAMETER AppFile
    Path of the built .app.

.PARAMETER AlToolPath
    Optional path of altool.exe. Default: the newest ms-dynamics-smb.al extension under the user's VS Code extensions.

.PARAMETER AllowSameVersion
    Rewrite the asset for the same version (only before the first release of that version).

.PARAMETER RepositoryRoot
    Fork root. Required when the script is run content-based (SRP-safe), where $PSScriptRoot is empty:
    & ([ScriptBlock]::Create((Get-Content -LiteralPath tools\aproda-bc-data-access\Update-BcDataAccessAsset.ps1 -Raw))) -RepositoryRoot (Get-Location).Path -AppFile <app>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppFile,
    [string]$AlToolPath,
    [switch]$AllowSameVersion,
    [string]$RepositoryRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $RepositoryRoot) {
    if (-not $PSScriptRoot) { throw 'Pass -RepositoryRoot when running the script content-based.' }
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..'
}
$repoRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$appJsonPath = Join-Path $repoRoot 'tools\aproda-bc-data-access\app\app.json'
$assetDir = Join-Path $repoRoot 'skills\skill-aproda-bc-data-access\assets'
$manifestPath = Join-Path $assetDir 'app-manifest.json'

function Resolve-AlTool {
    if ($AlToolPath) { return (Resolve-Path -LiteralPath $AlToolPath).Path }
    $extRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
    $candidates = Get-ChildItem -LiteralPath $extRoot -Directory -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $v = $null
            if ([version]::TryParse(($_.Name -replace '^ms-dynamics-smb\.al-', '' -replace '-.*$', ''), [ref]$v)) {
                [pscustomobject]@{ Version = $v; Tool = Join-Path $_.FullName 'bin\altool.exe' }
            }
        } | Where-Object { Test-Path -LiteralPath $_.Tool } | Sort-Object Version -Descending
    if (-not $candidates) { throw 'altool.exe not found; pass -AlToolPath.' }
    @($candidates)[0].Tool
}

$appFull = (Resolve-Path -LiteralPath $AppFile).Path
$altool = Resolve-AlTool
$raw = & $altool GetPackageManifest $appFull 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "altool GetPackageManifest failed: $raw" }
$pkg = $raw | ConvertFrom-Json
$src = Get-Content -LiteralPath $appJsonPath -Raw | ConvertFrom-Json

foreach ($k in 'id', 'name', 'publisher', 'version') {
    if ("$($pkg.$k)" -ne "$($src.$k)") { throw "Package $k '$($pkg.$k)' does not match app/app.json '$($src.$k)'." }
}

if (Test-Path -LiteralPath $manifestPath) {
    $current = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($current.appId -ne $pkg.id) { throw "App id changed ($($current.appId) -> $($pkg.id)); the guard would no longer match released installs. Update D-55/spec first." }
    $cmp = ([version]$pkg.version).CompareTo([version]$current.version)
    if ($cmp -lt 0 -or ($cmp -eq 0 -and -not $AllowSameVersion)) {
        throw "Version $($pkg.version) is not higher than the current asset $($current.version)."
    }
}

New-Item -ItemType Directory -Force -Path $assetDir | Out-Null
Get-ChildItem -LiteralPath $assetDir -Filter '*.app' | Remove-Item -Force
$fileName = '{0}_{1}_{2}.app' -f $pkg.publisher, $pkg.name, $pkg.version
$target = Join-Path $assetDir $fileName
Copy-Item -LiteralPath $appFull -Destination $target -Force

$manifest = [ordered]@{
    appId              = $pkg.id
    name               = $pkg.name
    publisher          = $pkg.publisher
    version            = $pkg.version
    minimumApplication = $pkg.application
    file               = $fileName
    sha256             = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
}
[IO.File]::WriteAllText($manifestPath, (($manifest | ConvertTo-Json) + "`n"), [Text.UTF8Encoding]::new($false))
[pscustomobject]$manifest
