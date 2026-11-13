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
      3. A `*.code-workspace` legacy BCQuality root (sibling clone `../BCQuality-Aproda`,
         any direct clone path, or the D-49 `.external` path root), superseded by the
         constant virtual root `{ "name": ".external", "uri": "aldc-external:/" }` (D-54).
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
    `toolkitRoot:` key) -- never leave a half-migrated project with no config at all.
    The workspace migration has no `.external/` precondition: the virtual root works
    without the real folder. This script stays the route for projects opened without
    the Aproda VS Code extension (whose reconcile does the same migration).

    Never touches `.external/bcquality` itself (an optional extension-managed junction
    onto the developer's real clone, outside the repo); nothing here enumerates it.

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
param(
    # Optional: lets a caller that is NOT inside the project (the VS Code extension runs this
    # from the managed fork cache) target the project explicitly. Without it the .git-walk below
    # would resolve to the cache repository instead.
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

# ── Resolve roots (same self-location + .git-walk pattern as Initialize-AprodaProject.ps1) ──
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $env:APRODA_SYNC_SCRIPTDIR
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Set `$env:APRODA_SYNC_SCRIPTDIR when loading content-based."
}

if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    if (-not (Test-Path -LiteralPath $ProjectRoot)) {
        throw "ProjectRoot does not exist: $ProjectRoot"
    }
    $projectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}
else {
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
}

$rootAldcYaml = Join-Path $projectRoot 'aldc.yaml'
$githubAldcYaml = Join-Path $projectRoot '.github\aldc.yaml'

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
# The target is the constant virtual root `aldc-external:/` (D-54); it needs no real
# `.external/` folder. Only the explicit file `skills/entry.md` is probed in a candidate
# clone path, never its contents.
$externalUri = 'aldc-external:/'
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
            $manual.Add("$($wsFile.Name) could not be parsed (JSONC/comments?) -- left untouched. Manually: replace the BCQuality folder entry (or the '.external' path root) with { name: '.external', uri: 'aldc-external:/' }, and remove any 'BCQUALITY_HOME' key under settings 'terminal.integrated.env.*'.")
            continue
        }

        $changed = $false

        # Classify each folder entry: constant virtual root (keep one), `.external` path root
        # (D-49, replace in place), legacy direct clone root (remove), anything else (untouched).
        if ($json.folders) {
            $newFolders = New-Object System.Collections.Generic.List[object]
            $hasConstant = $false
            $replacedExternal = $false
            $removedLegacy = @()
            $droppedDuplicates = 0
            foreach ($folder in @($json.folders)) {
                $folderPath = "$($folder.path)"
                $folderUri = "$($folder.uri)"
                if ($folderUri -eq $externalUri) {
                    if ($hasConstant) { $droppedDuplicates++; continue }
                    $hasConstant = $true
                    $newFolders.Add($folder)
                    continue
                }
                $normalised = ($folderPath -replace '\\', '/').Trim().TrimEnd('/')
                $normalised = $normalised -replace '^(\./)+', ''
                $isExternalPathRoot = ($folder.name -eq '.external') -or ($folderPath -and $normalised -eq '.external')
                if ($isExternalPathRoot) {
                    $replacedExternal = $true
                    if ($hasConstant) { continue }
                    $hasConstant = $true
                    $newFolders.Add([pscustomobject]@{ name = '.external'; uri = $externalUri })
                    continue
                }
                $isLegacyClone = $false
                if ($folderPath) {
                    $leaf = ($normalised -split '/')[-1]
                    if ($leaf -match '^bcquality(-aproda)?$') {
                        $isLegacyClone = $true
                    }
                    else {
                        $candidate = if ([System.IO.Path]::IsPathRooted($folderPath)) { $folderPath } else { Join-Path $wsFile.DirectoryName $folderPath }
                        if (Test-Path -LiteralPath (Join-Path $candidate 'skills/entry.md') -PathType Leaf) { $isLegacyClone = $true }
                    }
                }
                if ($isLegacyClone) {
                    $removedLegacy += $folderPath
                    continue
                }
                $newFolders.Add($folder)
            }
            if (-not $hasConstant) {
                $newFolders.Add([pscustomobject]@{ name = '.external'; uri = $externalUri })
                $hasConstant = $true
                if ($removedLegacy.Count -eq 0 -and -not $replacedExternal) {
                    $migrated.Add("$($wsFile.Name): added the missing '.external' virtual root ($externalUri).")
                }
            }

            if ($removedLegacy.Count -gt 0 -or $replacedExternal -or $droppedDuplicates -gt 0 -or ($newFolders.Count -ne @($json.folders).Count) -or (-not (@($json.folders) | Where-Object { "$($_.uri)" -eq $externalUri }))) {
                $json.folders = $newFolders.ToArray()
                $changed = $true
            }
            if ($removedLegacy.Count -gt 0) {
                $migrated.Add("$($wsFile.Name): replaced the legacy BCQuality root(s) '$($removedLegacy -join "', '")' with the '.external' virtual root ($externalUri).")
            }
            if ($replacedExternal) {
                $migrated.Add("$($wsFile.Name): replaced the '.external' path root with the virtual root ($externalUri).")
            }
            if ($droppedDuplicates -gt 0) {
                $migrated.Add("$($wsFile.Name): dropped $droppedDuplicates duplicate '.external' virtual root(s).")
            }
            if ($removedLegacy.Count -eq 0 -and -not $replacedExternal -and $droppedDuplicates -eq 0) {
                $current.Add("$($wsFile.Name): no legacy BCQuality root found.")
            }

            # A retired root's exclude globs are meaningless once it is gone; the junction-mode
            # `bcquality/**` glob is kept.
            if ($removedLegacy.Count -gt 0 -and $json.settings) {
                foreach ($excludeKey in @('search.exclude', 'files.watcherExclude')) {
                    $excludeProp = $json.settings.PSObject.Properties[$excludeKey]
                    if (-not $excludeProp) { continue }
                    $staleGlobs = @($excludeProp.Value.PSObject.Properties | Where-Object {
                            $globName = $_.Name
                            $globName -ne 'bcquality/**' -and @($removedLegacy | Where-Object { $_ -and $globName.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0
                        } | Select-Object -ExpandProperty Name)
                    foreach ($glob in $staleGlobs) { $excludeProp.Value.PSObject.Properties.Remove($glob) }
                    if ($staleGlobs.Count -gt 0) {
                        $migrated.Add("$($wsFile.Name): removed $($staleGlobs.Count) stale '$excludeKey' glob(s) for the retired root.")
                    }
                }
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
                # One backup per file, ever -- it is the only copy of the pre-rewrite
                # comments/formatting. Init 3 may already have taken it (E-006 F2); a
                # second run must never clobber it.
                $backupPath = "$($wsFile.FullName).bak"
                if (-not (Test-Path -LiteralPath $backupPath)) {
                    Copy-Item -LiteralPath $wsFile.FullName -Destination $backupPath -Force
                    $migrated.Add("$($wsFile.Name): comments and formatting are NOT preserved by this rewrite -- original saved to $($wsFile.Name).bak.")
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
