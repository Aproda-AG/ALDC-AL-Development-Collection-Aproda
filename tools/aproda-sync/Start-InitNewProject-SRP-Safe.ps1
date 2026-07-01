# Aproda Sync — SRP-safe launcher for Start-InitNewProject.ps1.
# RUN: Open this file → Select All → "PowerShell: Run Selection" in the PS Extension terminal.
# This file is machine-agnostic and committed in the fork as-is.

# FALLBACK — if self-location fails, fill in the path below (leave empty for auto-detect):
$selfDir = ''   # e.g. 'C:\src\ALDC-AL-Development-Collection-Aproda\tools\aproda-sync'

# TARGET REPO — leave empty for interactive selection; or fill in a fixed path:
$targetRepo = ''   # e.g. 'C:\MyWorkspace\MyNewProject'

# Auto-detect (three tiers: F5 file-run, PS-extension Run-Selection, env var)
if ([string]::IsNullOrWhiteSpace($selfDir) -and $PSScriptRoot) { $selfDir = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($selfDir) -and $psEditor) {
    try { $selfDir = Split-Path -Parent $psEditor.GetEditorContext().CurrentFile.Path } catch { }
}
if ([string]::IsNullOrWhiteSpace($selfDir) -and $env:APRODA_SYNC_SCRIPTDIR) { $selfDir = $env:APRODA_SYNC_SCRIPTDIR }

if ([string]::IsNullOrWhiteSpace($selfDir)) {
    Write-Host 'Could not self-locate the fork. Fix options:' -ForegroundColor Yellow
    Write-Host '  1) Open THIS file in VS Code and use "Run Selection" (PowerShell Extension terminal).'
    Write-Host '  2) Fill in $selfDir at the top of this file (line 6) and re-run.'
    Write-Host '  3) Run in terminal: $env:APRODA_SYNC_SCRIPTDIR = ''<fork>\tools\aproda-sync''  then re-run.'
    return
}

$env:APRODA_SYNC_SCRIPTDIR = $selfDir
$p = Join-Path $selfDir 'Start-InitNewProject.ps1'
$content = Get-Content $p -Raw
# Inject $targetRepo override if set (replaces the empty default in the main script)
if (-not [string]::IsNullOrWhiteSpace($targetRepo)) {
    $escaped = $targetRepo.Replace("'", "''")
    $content = $content -replace "(?m)^\`$targetRepo\s*=\s*''", "`$targetRepo = '$escaped'"
}
& ([ScriptBlock]::Create($content))
