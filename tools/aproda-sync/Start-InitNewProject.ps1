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
    elseif ($env:APRODA_SYNC_SCRIPTDIR) {
        $selfPath = $env:APRODA_SYNC_SCRIPTDIR
    }
    elseif ($psEditor) {
        try { $selfPath = Split-Path -Parent $psEditor.GetEditorContext().CurrentFile.Path } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($selfPath)) {
        Write-Host 'Could not self-locate the fork. Set $env:APRODA_SYNC_SCRIPTDIR to the aproda-sync folder, or set $forkPath manually at the top.'
        return
    }
    # $selfPath = <fork>/tools/aproda-sync  ->  fork root is two levels up.
    $forkPath = Split-Path -Parent (Split-Path -Parent $selfPath)
}
Write-Host "Init New Project -> fork: $forkPath"

# ── Target repo: leave EMPTY to get interactive selection; or hardcode a path here ────
$targetRepo = ''
# Example: 'C:\MyWorkspace\MyNewRepo'   (must already be a git work tree: run `git init` first)

# ── Resolve the target interactively when not provided ───────────────────────
if ([string]::IsNullOrWhiteSpace($targetRepo)) {
    # Scan the fork's parent recursively, while avoiding generated dependency folders.
    $searchRoot = Split-Path -Parent $forkPath
    $excludedDirectoryNames = @('.git', '.alpackages', '.venv', 'bin', 'node_modules', 'obj')
    $pendingDirectories = [System.Collections.Generic.Queue[string]]::new()
    $pendingDirectories.Enqueue($searchRoot)
    $candidates = @()

    while ($pendingDirectories.Count -gt 0) {
        $currentDirectory = $pendingDirectories.Dequeue()
        $childDirectories = @(Get-ChildItem -Path $currentDirectory -Directory -ErrorAction SilentlyContinue)
        foreach ($childDirectory in $childDirectories) {
            if ($childDirectory.Name -in $excludedDirectoryNames) {
                continue
            }

            if (Test-Path (Join-Path $childDirectory.FullName '.git')) {
                $candidates += $childDirectory.FullName
            }

            $pendingDirectories.Enqueue($childDirectory.FullName)
        }
    }
    $candidates = @($candidates | Sort-Object -Unique)

    # TIER 1: Out-GridView (GUI, works in VS Code integrated terminal + standard PS)
    if ($candidates.Count -gt 0 -and (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
        Write-Host 'Select target repo from list (or cancel to enter path manually)...'
        $picked = $candidates | Out-GridView -Title 'Select target project repo (must contain .git)' -OutputMode Single
        if ($picked) { $targetRepo = $picked }
    }

    # TIER 2: Console fallback — show candidates + Read-Host
    if ([string]::IsNullOrWhiteSpace($targetRepo)) {
        Write-Host ''
        Write-Host '=== Available git repos ===' -ForegroundColor Cyan
        if ($candidates.Count -gt 0) {
            for ($i = 0; $i -lt $candidates.Count; $i++) {
                Write-Host "[$i] $($candidates[$i])" -ForegroundColor Yellow
            }
            Write-Host ''
            $sel = Read-Host "Enter index (0-$($candidates.Count-1)) or full path"
            if ($sel -match '^\d+$' -and [int]$sel -lt $candidates.Count) {
                $targetRepo = $candidates[[int]$sel]
            }
            else {
                $targetRepo = $sel.Trim()
            }
        }
        else {
            $targetRepo = (Read-Host 'No repos found. Enter full path to target repo').Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($targetRepo)) { Write-Host 'Cancelled — no target selected.'; return }
    if (-not (Test-Path (Join-Path $targetRepo '.git'))) {
        Write-Host "No .git folder found in: $targetRepo  — run 'git init' first."; return
    }
}
Write-Host "Init New Project -> target: $targetRepo"

# ── Run the bootstrap from the FORK (SRP-safe content-load, no path execution) ─
# The engine lives in the fork; point the script-dir env var at the fork's aproda-sync
# folder so the bootstrap can resolve the fork side. The bootstrap pulls the whole
# layer into the target, runs the project init, and materializes Start-Pull.ps1.
$env:APRODA_SYNC_SCRIPTDIR = Join-Path $forkPath 'tools\aproda-sync'
$bootSrc = Get-Content "$env:APRODA_SYNC_SCRIPTDIR\Bootstrap-AprodaProject.ps1" -Raw
& ([ScriptBlock]::Create($bootSrc)) -ProjectRoot $targetRepo -ForkPath $forkPath
