# Aproda Sync — New-Project initializer (FORK-ONLY tool; lives next to the engine).
# PURPOSE: One-click onboarding of a FRESH repo. Pick a target folder → done:
#          the repo is pulled, initialized, and left with a ready Start-Pull.ps1.
# HOME:    <fork>/tools/aproda-sync/Start-InitNewProject.ps1. This is FORK
#          INFRASTRUCTURE, not layer content — it is NOT synced into projects
#          (deliberately absent from aproda-sync.json). See decisions.aproda.md D-20.
# RUN:     Open this file → Select All → "PowerShell: Run Selection" (SRP-safe,
#          no path-based execution). Nothing to fill in — the fork path is
#          self-resolved from this script's own location.

# ── Optional override: only needed if self-location fails (empty by design) ─────
$forkPath = ''

# ── Self-locate the fork: this script sits at <fork>/tools/aproda-sync/ ─────────
# Resolution order (covers both ways the PS extension can run this file):
#   1) $PSScriptRoot           — set when run as a file (F5 / Run File)
#   2) $psEditor current file  — set under "Run Selection" in the Integrated Console
# Either yields <fork>/tools/aproda-sync; the fork root is two levels up. Because
# the path is derived, never hardcoded, this file is machine-agnostic and committed
# in the fork as-is (no .template / no .gitignore needed).
if ([string]::IsNullOrWhiteSpace($forkPath)) {
    $selfPath = $null
    if ($PSScriptRoot) {
        $selfPath = $PSScriptRoot
    }
    elseif ($psEditor) {
        try { $selfPath = Split-Path -Parent $psEditor.GetEditorContext().CurrentFile.Path } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($selfPath)) {
        Write-Host 'Could not self-locate the fork. Open THIS file in the editor and use "Run Selection", or set $forkPath manually at the top.'
        return
    }
    # $selfPath = <fork>/tools/aproda-sync  ->  fork root is two levels up.
    $forkPath = Split-Path -Parent (Split-Path -Parent $selfPath)
}
Write-Host "Init New Project -> fork: $forkPath"

# ── Target repo: leave EMPTY to get a folder picker; or hardcode a path here ────
$targetRepo = ''
# Example: 'C:\MyWorkspace\MyNewRepo'   (must already be a git work tree: run `git init` first)

# ── Resolve the target via a Windows folder picker when not provided ───────────
# Shell.Application BrowseForFolder is STA-independent (works in pwsh's default MTA),
# unlike WinForms FolderBrowserDialog — chosen for reliability under Run Selection.
if ([string]::IsNullOrWhiteSpace($targetRepo)) {
    $shell = New-Object -ComObject Shell.Application
    $picked = $shell.BrowseForFolder(0, 'Select the target project repo folder (must already contain .git)', 0, 0)
    if ($null -eq $picked) { Write-Host 'Cancelled — no target selected.'; return }
    $targetRepo = $picked.Self.Path
    if ([string]::IsNullOrWhiteSpace($targetRepo)) { Write-Host 'Could not resolve the selected folder path.'; return }
}
Write-Host "Init New Project -> target: $targetRepo"

# ── Run the bootstrap from the FORK (SRP-safe content-load, no path execution) ─
# The engine lives in the fork; point the script-dir env var at the fork's aproda-sync
# folder so the bootstrap can resolve the fork side. The bootstrap pulls the whole
# layer into the target, runs the project init, and materializes Start-Pull.ps1.
$env:APRODA_SYNC_SCRIPTDIR = Join-Path $forkPath 'tools\aproda-sync'
$bootSrc = Get-Content "$env:APRODA_SYNC_SCRIPTDIR\Bootstrap-AprodaProject.ps1" -Raw
& ([ScriptBlock]::Create($bootSrc)) -ProjectRoot $targetRepo -ForkPath $forkPath
