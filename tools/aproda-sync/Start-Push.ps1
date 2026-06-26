# Aproda Sync — Push starter (machine-local, git-ignored)
# SETUP: Copy this file to Start-Push.ps1 (same folder), fill in the two paths, save.
#        Do NOT commit Start-Push.ps1 — it is in .gitignore (machine-specific paths).
# RUN:   Select All → PowerShell: Run Selection  (SRP-safe, no path-based execution)

$env:APRODA_SYNC_SCRIPTDIR = 'C:\_EphemeralWorkspace\Florian Köll\Straub Medical AG Base\Base\.github\tools\aproda-sync'
# Example: 'C:\MyWorkspace\MyProject\.github\tools\aproda-sync'

$env:APRODA_FORK_PATH = 'C:\_EphemeralWorkspace\Florian Köll\ALDC-AL-Development-Collection-Aproda'
# Example: 'C:\MyWorkspace\ALDC-AL-Development-Collection-Aproda'

# ── SRP-safe engine call (no path-based execution) ───────────────────────────
$src = Get-Content "$env:APRODA_SYNC_SCRIPTDIR\Sync-AprodaLayer.ps1" -Raw
& ([ScriptBlock]::Create($src)) -Direction push -ForkPath $env:APRODA_FORK_PATH
