# Aproda Sync — SRP-safe launcher for Start-InitNewProject.ps1.
# RUN: Open this file → Select All → "PowerShell: Run Selection" in the PS Extension terminal.
# This file is machine-agnostic and committed in the fork as-is.

$selfDir = $null
if ($PSScriptRoot) { $selfDir = $PSScriptRoot }
elseif ($psEditor) {
    try { $selfDir = Split-Path -Parent $psEditor.GetEditorContext().CurrentFile.Path } catch { }
}
if ([string]::IsNullOrWhiteSpace($selfDir)) {
    Write-Host 'Could not self-locate. Open THIS file in VS Code and use "Run Selection".'; return
}

$env:APRODA_SYNC_SCRIPTDIR = $selfDir
$p = Join-Path $selfDir 'Start-InitNewProject.ps1'
& ([ScriptBlock]::Create((Get-Content $p -Raw)))
