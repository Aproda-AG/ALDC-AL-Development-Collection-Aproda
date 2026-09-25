<#
.SYNOPSIS
    Aproda ALDC — one-time project initialization (idempotent), run after a pull.

.DESCRIPTION
    Seeds the project-local artifacts the toolkit needs but never syncs:
      1. plans/memory.md          — seeded once from the ALDC template (never pushed).
      2. .gitignore               — the Aproda machine-local patterns, kept inside a
                                     "# Aproda ALDC Tool - BEGIN/END" marker block so
                                     they are obvious and updated as one unit.
      3. *.code-workspace          — the .github root (toolkit discovery) + the .external
                                     wrapper root (BCQuality, consumed outside the build via a
                                     junction/symlink so its example .al files never enter
                                     compilation), plus chat.useCustomizationsInParentRepositories
                                     and the search.exclude / files.watcherExclude rules that keep
                                     the mounted junction out of project-wide search.
      4. .external/README.md       — seeded once from the ALDC template; explains the junction
                                     the Aproda VS Code extension creates inside .external/bcquality.
      5. Legacy-layout migration   — chains Migrate-AprodaProjectLayout.ps1 (T-35) as the LAST
                                     step, so a pre-Block-4 project (root aldc.yaml, sibling
                                     BCQuality workspace root, BCQUALITY_HOME in the workspace
                                     file) is migrated onto the current layout on every pull.
                                     Idempotent; no-op on an already-migrated project.

    Split out of Start-Pull so the run script stays thin. SRP-safe: cmdlet-only, no
    path-based dot-sourcing — load its content and invoke:

        $src = Get-Content "$env:APRODA_SYNC_SCRIPTDIR\Initialize-AprodaProject.ps1" -Raw
        & ([ScriptBlock]::Create($src))

.NOTES
    Decision: D-19 (decisions.aproda.md). Sibling of Sync-AprodaLayer.ps1.
    Deliberately does not support -WhatIf: Init 1-4 write unconditionally, so accepting
    the switch without honouring it would be a lie. To preview, run
    Migrate-AprodaProjectLayout.ps1 -WhatIf directly (Init 5 only).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ── Resolve roots ────────────────────────────────────────────────────────────
# Under SRP content-loading $PSScriptRoot is empty; fall back to the env var the
# Start-Pull script sets.
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $env:APRODA_SYNC_SCRIPTDIR
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Cannot resolve script directory. Set `$env:APRODA_SYNC_SCRIPTDIR when loading content-based."
}

# Anchor at the REAL git root by walking up until a .git entry is found. This is
# encoding-safe (pure path ops) — parsing `git rev-parse` stdout mangles non-ASCII
# path segments (e.g. umlauts) under non-UTF-8 consoles. Robust for multi-app repos
# where .github sits at the repo root next to several app folders. Fall back to
# "scriptDir up 3" only when no .git is found (off-git).
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
$githubRoot = Join-Path $projectRoot '.github'
$templatesDir = Join-Path $scriptDir 'templates'

# ── Init 1: seed plans/memory.md if not yet present (first pull only) ─────────
# The project-local memory.md is never synced back to the fork (plans/** is
# neverTouch for the syncer). This block seeds it once with a minimal stub that
# tells the AI agent to initialize it properly on first use.
$memoryTarget = Join-Path $githubRoot 'plans\memory.md'
if (-not (Test-Path $memoryTarget)) {
    New-Item -ItemType Directory -Force (Split-Path $memoryTarget) | Out-Null
    $memoryStub = [System.IO.File]::ReadAllText((Join-Path $templatesDir 'memory.seed.md'))
    [System.IO.File]::WriteAllText($memoryTarget, $memoryStub, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Init: plans/memory.md created (uninitialized stub)."
}
else {
    Write-Host "Init: plans/memory.md already exists — skipped."
}

# ── Init 2: keep the Aproda machine-local .gitignore block in sync ────────────
# All Aproda patterns live inside one labelled marker block so they are easy to
# spot and maintained as a unit. Idempotent: if the block already matches it is
# left untouched (no EOL churn); otherwise it is replaced/appended in place.
$gitignorePath = Join-Path $projectRoot '.gitignore'
$beginMarker = '# Aproda ALDC Tool - BEGIN'
$endMarker = '# Aproda ALDC Tool - END'
$blockLines = @(Get-Content (Join-Path $templatesDir 'gitignore-block.txt'))
# Wrap the whole conditional in @(...): a bare `else { @() }` would be enumerated to
# zero pipeline items and collapse to $null (PowerShell gotcha), crashing IndexOf on a
# fresh repo that has no .gitignore yet. @( if (...) { ... } ) yields a real empty array.
$lines = @(if (Test-Path $gitignorePath) { Get-Content $gitignorePath })
$beginIdx = [array]::IndexOf($lines, $beginMarker)
$endIdx = [array]::IndexOf($lines, $endMarker)

if ($beginIdx -ge 0 -and $endIdx -gt $beginIdx) {
    # Marker block exists — replace only if its content differs.
    $currentBlock = $lines[$beginIdx..$endIdx]
    if (($currentBlock -join "`n") -eq ($blockLines -join "`n")) {
        Write-Host "Init: .gitignore Aproda block already current — skipped."
    }
    else {
        $before = @(if ($beginIdx -gt 0) { $lines[0..($beginIdx - 1)] })
        $after = @(if ($endIdx -lt ($lines.Count - 1)) { $lines[($endIdx + 1)..($lines.Count - 1)] })
        Set-Content -Path $gitignorePath -Value ($before + $blockLines + $after)
        Write-Host "Init: .gitignore Aproda block updated."
    }
}
else {
    # No marker block — append one (separated by a blank line if the file is non-empty).
    $prefix = @(if ($lines.Count -gt 0 -and $lines[-1] -ne '') { '' })
    Add-Content -Path $gitignorePath -Value ($prefix + $blockLines)
    Write-Host "Init: .gitignore Aproda block added."
}

# ── Init 3: ensure the *.code-workspace carries the roots ALDC needs ──────────
# Two roots must be present for the toolkit to work when you open the workspace:
#   1) the .github root — the toolkit (copilot-instructions, instructions/, prompts/,
#      agents/) lives here; surfacing it as a folder keeps it editable/visible.
#   2) the .external wrapper root — BCQuality is reached through a junction/symlink at
#      .external/bcquality, never mounted directly (a workspace root cannot exclude
#      itself, so the clone's example .al files would otherwise leak into every search).
# Both are added only when missing (idempotent). JSONC that does not parse is left
# untouched with a manual hint. Existing projects that still carry the legacy sibling
# root (../BCQuality-Aproda) are left alone here — migrating them off it is T-35.
$requiredRoots = @(
    @{ name = '.github'; path = '.github'; match = '^\.github$' },
    @{ name = 'BCQuality (Aproda ALDC)'; path = '.external'; match = '^\.external$' }
)
# Settings ALDC needs surfaced in every workspace. parentCustomizations lets Copilot
# walk up to the .git root and pick up the repo-root .github customizations even when
# only a single app folder is opened (VS Code: chat.useCustomizationsInParentRepositories).
$parentCustomizationsKey = 'chat.useCustomizationsInParentRepositories'
# Exclude globs that keep the .external/bcquality junction out of search/watcher without
# hiding it from reads — files.exclude would also block the agents' read path (never use it).
$bcqualityExcludeKeys = @('search.exclude', 'files.watcherExclude')
$bcqualityExcludeGlob = 'bcquality/**'
$wsFiles = Get-ChildItem -Path $projectRoot -Filter '*.code-workspace' -File -ErrorAction SilentlyContinue
if (-not $wsFiles) {
    # No workspace file found — create one from the seed template.
    # The seed (templates/workspace.seed.jsonc) is the canonical reference; here we
    # produce a clean JSON equivalent (comments stripped so ConvertFrom-Json can
    # round-trip it on future pulls). App folder placeholders ("App", "Test") are
    # included so the developer knows where to add real entries.
    $ws = [ordered]@{
        folders  = @(
            [ordered]@{ name = '.github'; path = '.github' },
            [ordered]@{ name = 'App'; path = 'App' },
            [ordered]@{ name = 'Test'; path = 'Test' },
            [ordered]@{ name = 'BCQuality (Aproda ALDC)'; path = '.external' }
        )
        settings = [ordered]@{
            $parentCustomizationsKey = $true
            'search.exclude'         = [ordered]@{ $bcqualityExcludeGlob = $true }
            'files.watcherExclude'   = [ordered]@{ $bcqualityExcludeGlob = $true }
        }
    }
    $target = Join-Path $projectRoot 'aldc.code-workspace'
    [System.IO.File]::WriteAllText($target, ($ws | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Init: aldc.code-workspace created from seed (.github + App + Test + .external roots, parent customizations + bcquality excludes on)."
    Write-Host "      -> Edit app folder names/paths to match your project layout before committing."
    Write-Host "      -> Reference (fork-side only, not shipped): tools/aproda-sync/templates/workspace.seed.jsonc"
}
else {
    foreach ($wsFile in $wsFiles) {
        $raw = Get-Content $wsFile.FullName -Raw
        try {
            $json = $raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Warning "Init: could not parse $($wsFile.Name) (JSONC/comments?). Ensure it has roots: '.github' and a BCQuality folder."
            continue
        }
        if (-not $json.folders) {
            $json | Add-Member -NotePropertyName folders -NotePropertyValue @() -Force
        }
        $existingPaths = @($json.folders | ForEach-Object { "$($_.path)" })
        $added = @()
        foreach ($root in $requiredRoots) {
            $present = $existingPaths | Where-Object { $_ -match $root.match }
            if (-not $present) {
                $entry = [pscustomobject]@{ name = $root.name; path = $root.path }
                # .github must always be the first workspace folder.
                if ($root.path -eq '.github') {
                    $json.folders = @($entry) + @($json.folders)
                }
                else {
                    $json.folders = @($json.folders) + @($entry)
                }
                $added += $root.path
            }
        }
        # Ensure the parent-customizations setting is present (idempotent).
        if (-not $json.settings) {
            $json | Add-Member -NotePropertyName settings -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $settingChanged = $false
        if ($json.settings.$parentCustomizationsKey -ne $true) {
            $json.settings | Add-Member -NotePropertyName $parentCustomizationsKey -NotePropertyValue $true -Force
            $settingChanged = $true
        }
        # Ensure the bcquality/** excludes are present without clobbering any other globs
        # the project already has under the same setting key (idempotent, additive-only).
        foreach ($excludeKey in $bcqualityExcludeKeys) {
            $existingProp = $json.settings.PSObject.Properties[$excludeKey]
            if (-not $existingProp) {
                $json.settings | Add-Member -NotePropertyName $excludeKey -NotePropertyValue ([pscustomobject]@{ $bcqualityExcludeGlob = $true }) -Force
                $settingChanged = $true
            }
            else {
                $globProp = $existingProp.Value.PSObject.Properties[$bcqualityExcludeGlob]
                if (-not $globProp -or $globProp.Value -ne $true) {
                    $existingProp.Value | Add-Member -NotePropertyName $bcqualityExcludeGlob -NotePropertyValue $true -Force
                    $settingChanged = $true
                }
            }
        }
        if ($added.Count -gt 0 -or $settingChanged) {
            [System.IO.File]::WriteAllText($wsFile.FullName, ($json | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
            $changes = @()
            if ($added.Count -gt 0) { $changes += "root(s): $($added -join ', ')" }
            if ($settingChanged) { $changes += $parentCustomizationsKey }
            Write-Host "Init: $($wsFile.Name) — updated ($($changes -join '; '))."
        }
        else {
            Write-Host "Init: $($wsFile.Name) already has the required roots and settings — skipped."
        }
    }
}

# ── Init 4: seed .external/README.md if not yet present ───────────────────────
# The wrapper folder itself is tracked (unlike the junction inside it, which is
# gitignored) so it exists in every fresh clone and explains itself. Never
# overwritten once present — same "copy, never clobber" rule as Init 1's memory
# seed: a developer may have annotated it, and there is nothing time-sensitive in
# its content that would justify a forced refresh.
$externalDir = Join-Path $projectRoot '.external'
$externalReadmeTarget = Join-Path $externalDir 'README.md'
$externalReadmeStubPath = Join-Path $templatesDir 'external-readme.seed.md'
if (-not (Test-Path $externalReadmeTarget)) {
    # A pull loads the PROJECT's syncer, but updates it in place: on the first pull
    # that introduces this template the old engine ran and never copied it. Skip
    # instead of throwing -- the next pull completes it.
    if (-not (Test-Path -LiteralPath $externalReadmeStubPath)) {
        Write-Host "Init: templates/external-readme.seed.md not in this project yet -- skipping .external/README.md. Run the pull once more to complete it." -ForegroundColor Yellow
    }
    else {
        New-Item -ItemType Directory -Force $externalDir | Out-Null
        $externalReadmeStub = [System.IO.File]::ReadAllText($externalReadmeStubPath)
        [System.IO.File]::WriteAllText($externalReadmeTarget, $externalReadmeStub, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Init: .external/README.md created."
    }
}
else {
    Write-Host "Init: .external/README.md already exists — skipped."
}

# ── Init 5: migrate a pre-Block-4 project onto the current layout (T-35) ──────
# Chained LAST so its preconditions (.github/aldc.yaml, .external/) are already
# satisfied by Init 2/4 above. Own script (not inlined) so it can carry its own
# -WhatIf support without touching the unconditional writes in Init 1-4.
$migratePath = Join-Path $scriptDir 'Migrate-AprodaProjectLayout.ps1'
if (-not (Test-Path -LiteralPath $migratePath)) {
    Write-Host "Init 5: Migrate-AprodaProjectLayout.ps1 not in this project yet -- skipping the layout migration. Run the pull once more to complete it." -ForegroundColor Yellow
}
else {
    $migrateSrc = Get-Content -LiteralPath $migratePath -Raw
    & ([ScriptBlock]::Create($migrateSrc))
}
