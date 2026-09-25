<#
.SYNOPSIS
    Aproda ALDC — one-time migration of a pre-Block-4 project onto the current layout (T-35).

.DESCRIPTION
    Existing projects onboarded before Block 4 (E-006) carry superseded state that
    Initialize-AprodaProject.ps1's own Init steps introduce for NEW projects but never
    remove from OLD ones:

      1. A stale `aldc.yaml` at the REPO ROOT, superseded by `.github/aldc.yaml` (T-33).
      2. (No code here — the `.gitignore` Aproda block already covers both locations;
         Initialize-AprodaProject.ps1's own Init 2 keeps it current on every run, so
         this is not duplicated.)
      3. A `*.code-workspace` legacy sibling BCQuality root (`../BCQuality-Aproda`),
         superseded by the tracked `.external/` wrapper (T-29).
      4. A `BCQUALITY_HOME` entry under `terminal.integrated.env.*` in the workspace
         file, superseded by a Global VS Code setting the extension writes (T-17).

    Idempotent and a no-op on an already-migrated project. Never discards content it
    does not own: a `*.code-workspace` that genuinely fails to parse is left completely
    untouched, with a manual instruction printed instead of guessing. A workspace file
    that DOES parse -- including one with `//` comments and non-standard indentation,
    which PowerShell 7's JSON parser silently tolerates -- is rewritten without them:
    the original is saved once to a sibling `.bak` before the first edit (never
    overwritten afterwards), and the report names it so the loss is visible on the
    pull that caused it, not discovered later.
    Order-sensitive preconditions: the stale root `aldc.yaml` is only removed once
    `.github/aldc.yaml` exists, is non-empty, and looks like a real config (contains a
    `toolkitRoot:` key) -- never leave a half-migrated project with no config at all;
    the legacy BCQuality root is only replaced once `.external/` exists in the repo
    (never leave a project with no BCQuality root at all). Both are normally already
    satisfied by the time this runs, because Initialize-AprodaProject.ps1 chains it as
    its LAST step, after its own Init 2/4 have run.

    Never touches `.external/bcquality` itself — that is an extension-managed junction
    onto the developer's real clone, outside the repo. Only its PARENT folder's existence
    is checked here; nothing in this script enumerates or recurses into it.

    SRP-safe: content-load and invoke (no path-based dot-sourcing / execution):

        $src = Get-Content "$env:APRODA_SYNC_SCRIPTDIR\Migrate-AprodaProjectLayout.ps1" -Raw
        & ([ScriptBlock]::Create($src))

.PARAMETER WhatIf
    Dry-run: report what would be migrated, change nothing on disk.

.NOTES
    Decision: D-49 / item T-35 (decisions.aproda.md, bcquality.md §5). Sibling of
    Initialize-AprodaProject.ps1, which chains this script as its last step so the
    migration runs automatically on every pull.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

# ── Resolve roots (same self-location + .git-walk pattern as Initialize-AprodaProject.ps1) ──
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $env:APRODA_SYNC_SCRIPTDIR
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Set `$env:APRODA_SYNC_SCRIPTDIR when loading content-based."
}

$gitRoot = $null
$dir = Get-Item -LiteralPath $scriptDir
while ($null -ne $dir) {
    if (Test-Path -LiteralPath (Join-Path $dir.FullName '.git')) { $gitRoot = $dir.FullName; break }
    $dir = $dir.Parent
}
if ($gitRoot) {
    $projectRoot = $gitRoot
}
else {
    $projectRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
}

$rootAldcYaml = Join-Path $projectRoot 'aldc.yaml'
$githubAldcYaml = Join-Path $projectRoot '.github\aldc.yaml'
$externalDir = Join-Path $projectRoot '.external'

$migrated = New-Object System.Collections.Generic.List[string]
$current = New-Object System.Collections.Generic.List[string]
$manual = New-Object System.Collections.Generic.List[string]

# ── Item 1: stale root aldc.yaml, superseded by .github/aldc.yaml (T-33) ──────
if (Test-Path -LiteralPath $rootAldcYaml) {
    # Fail closed: byte-length alone is not proof of real content (a single space is
    # 1 byte and would pass) -- require non-blank text AND the `toolkitRoot:` key the
    # dualVariant rewrite guarantees on every write. Any ambiguity keeps the root file.
    $githubYamlOk = $false
    if (Test-Path -LiteralPath $githubAldcYaml) {
        $githubYamlContent = Get-Content -LiteralPath $githubAldcYaml -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($githubYamlContent) -and $githubYamlContent -match 'toolkitRoot\s*:') {
            $githubYamlOk = $true
        }
    }
    if ($githubYamlOk) {
        if ($PSCmdlet.ShouldProcess($rootAldcYaml, 'Remove stale root aldc.yaml (superseded by .github/aldc.yaml)')) {
            Remove-Item -LiteralPath $rootAldcYaml -Force
        }
        $migrated.Add('Removed stale root aldc.yaml (superseded by .github/aldc.yaml).')
    }
    else {
        $manual.Add('Root aldc.yaml is still present, but .github/aldc.yaml is missing, empty, or does not look like a real config (no toolkitRoot: key found) -- run a pull first (it writes .github/aldc.yaml), then re-run this migration. Root file left untouched so the project never loses its configuration.')
    }
}
else {
    $current.Add('Root aldc.yaml already absent.')
}

# ── Items 3 & 4: *.code-workspace -- legacy BCQuality root + BCQUALITY_HOME ───
# `.external/bcquality` is an extension-managed junction onto the developer's real
# clone outside the repo -- only its parent folder's existence is checked below,
# never its contents.
$externalExists = Test-Path -LiteralPath $externalDir
$envKeys = @('terminal.integrated.env.windows', 'terminal.integrated.env.linux', 'terminal.integrated.env.osx')

$wsFiles = Get-ChildItem -Path $projectRoot -Filter '*.code-workspace' -File -ErrorAction SilentlyContinue
if (-not $wsFiles) {
    $current.Add('No *.code-workspace file found.')
}
else {
    foreach ($wsFile in $wsFiles) {
        $raw = Get-Content -LiteralPath $wsFile.FullName -Raw
        try {
            $json = $raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $manual.Add("$($wsFile.Name) could not be parsed (JSONC/comments?) -- left untouched. Manually: replace the '../BCQuality-Aproda' folder entry with a '.external' root, and remove any 'BCQUALITY_HOME' key under settings 'terminal.integrated.env.*'.")
            continue
        }

        $changed = $false

        # Legacy sibling BCQuality root -> `.external`, only once `.external/` exists --
        # never leave the project with no BCQuality root at all.
        if ($json.folders) {
            $legacyFolders = @($json.folders | Where-Object { "$($_.path)" -match 'BCQuality-Aproda' })
            if ($legacyFolders.Count -gt 0) {
                if ($externalExists) {
                    $json.folders = @($json.folders | Where-Object { "$($_.path)" -notmatch 'BCQuality-Aproda' })
                    $hasExternalRoot = @($json.folders | Where-Object { "$($_.path)" -match '^\.external$' }).Count -gt 0
                    if (-not $hasExternalRoot) {
                        $json.folders = @($json.folders) + @([pscustomobject]@{ name = 'BCQuality (Aproda ALDC)'; path = '.external' })
                    }
                    $changed = $true
                    $migrated.Add("$($wsFile.Name): replaced the legacy '../BCQuality-Aproda' root with '.external'.")
                }
                else {
                    $manual.Add("$($wsFile.Name) still has the legacy '../BCQuality-Aproda' root, but '.external/' does not exist in this repo yet -- run a pull first (it seeds .external/README.md), then re-run this migration.")
                }
            }
            else {
                $current.Add("$($wsFile.Name): no legacy BCQuality sibling root found.")
            }
        }

        # BCQUALITY_HOME is now a Global VS Code setting (T-17); drop it from the
        # tracked workspace file. Remove the container key too if it becomes empty.
        if ($json.settings) {
            $removedFrom = @()
            foreach ($envKey in $envKeys) {
                $prop = $json.settings.PSObject.Properties[$envKey]
                if ($prop -and $prop.Value.PSObject.Properties['BCQUALITY_HOME']) {
                    $prop.Value.PSObject.Properties.Remove('BCQUALITY_HOME')
                    if (@($prop.Value.PSObject.Properties).Count -eq 0) {
                        $json.settings.PSObject.Properties.Remove($envKey)
                    }
                    $removedFrom += $envKey
                    $changed = $true
                }
            }
            if ($removedFrom.Count -gt 0) {
                $migrated.Add("$($wsFile.Name): removed BCQUALITY_HOME from $($removedFrom -join ', ') (now a Global VS Code setting).")
            }
        }

        if ($changed) {
            if ($PSCmdlet.ShouldProcess($wsFile.FullName, 'Migrate legacy BCQuality workspace root / BCQUALITY_HOME')) {
                # One backup per file, ever -- it is the only copy of the pre-migration
                # comments/formatting, so a second run must never clobber it.
                $backupPath = "$($wsFile.FullName).bak"
                if (-not (Test-Path -LiteralPath $backupPath)) {
                    Copy-Item -LiteralPath $wsFile.FullName -Destination $backupPath -Force
                    $migrated.Add("$($wsFile.Name): comments and formatting are NOT preserved by this rewrite -- original saved to $($wsFile.Name).bak before the first edit.")
                }
                $jsonText = $json | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($wsFile.FullName, $jsonText, [System.Text.UTF8Encoding]::new($false))
            }
        }
    }
}

# ── Report (aligned to the sibling "Init: ..." convention -- this is Init 5) ──
if ($migrated.Count -eq 0 -and $manual.Count -eq 0) {
    Write-Host "Init 5: project layout already current -- nothing to migrate." -ForegroundColor Green
}
foreach ($m in $migrated) { Write-Host "Init 5: [migrated] $m" -ForegroundColor Green }
foreach ($c in $current) { Write-Host "Init 5: [current]  $c" }
foreach ($x in $manual) { Write-Host "Init 5: [manual]   $x" -ForegroundColor Yellow }
if ($WhatIfPreference) {
    Write-Host "Init 5: dry-run -- no files were changed." -ForegroundColor Yellow
}
