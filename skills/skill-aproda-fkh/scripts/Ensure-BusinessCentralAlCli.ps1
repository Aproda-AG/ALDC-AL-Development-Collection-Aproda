[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$alCommand = Get-Command al -ErrorAction SilentlyContinue
if (-not $alCommand) {
    dotnet tool install --global Microsoft.Dynamics.BusinessCentral.Development.Tools
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Microsoft.Dynamics.BusinessCentral.Development.Tools (exit code $LASTEXITCODE)."
    }

    $dotnetToolsDirectory = Join-Path $env:USERPROFILE '.dotnet\tools'
    if ($env:PATH -notlike "*$dotnetToolsDirectory*") {
        $env:PATH = "$dotnetToolsDirectory;$env:PATH"
    }

    $alCommand = Get-Command al -ErrorAction SilentlyContinue
}

if (-not $alCommand) {
    throw 'The AL CLI is unavailable after installation. Restart the terminal or add the .NET global tools directory to PATH.'
}

return $alCommand.Source