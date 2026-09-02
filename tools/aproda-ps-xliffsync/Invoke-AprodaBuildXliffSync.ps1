<#
.SYNOPSIS
Synchronizes, exports, applies, and validates AL XLIFF translations.

.DESCRIPTION
Loads the minimal vendored XliffSync runtime content-based, which works where
Software Restriction Policy blocks Import-Module and path-based dot-sourcing.
#>
[CmdletBinding()]
param(
    [string]$AppPath = (Get-Location).Path,
    [ValidatePattern('^[a-z]{2,3}-[A-Z]{2}$')]
    [string]$Language = 'de-CH',
    [ValidateSet('Sync', 'Resolve', 'ExportOpen', 'Apply', 'Validate', 'Report')]
    [string]$Action = 'Sync',
    [string]$BatchPath,
    [string]$ResponsePath,
    [string]$ManifestPath,
    [string]$ReportPath,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$MaxItems = 30,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$Offset = 0,
    [switch]$SkipBuild,
    [switch]$FailOnIssues,
    [switch]$FailOnUnapproved
)

function Get-AprodaXliffSyncScriptDirectory {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    if ($env:APRODA_XLIFFSYNC_SCRIPTDIR) {
        return $env:APRODA_XLIFFSYNC_SCRIPTDIR
    }

    if ($psEditor) {
        $currentFilePath = $psEditor.GetEditorContext().CurrentFile.Path
        if ($currentFilePath) {
            return Split-Path -Path $currentFilePath -Parent
        }
    }

    throw 'Cannot locate the XLIFF sync tool. Set APRODA_XLIFFSYNC_SCRIPTDIR when content-loading it outside VS Code.'
}

function Get-AprodaXliffSyncSource {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $source = Get-Content -LiteralPath $Path -Raw
    $source = $source -replace '(?m)^\s*Export-ModuleMember.*(?:\r?\n)?', ''
    return $source
}

function Find-AprodaAlCompiler {
    $extensionRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
    $compiler = Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    ForEach-Object { Join-Path $_.FullName 'bin\win32\alc.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

    if (-not $compiler) {
        throw 'AL compiler not found. Install the AL Language extension, run the build manually, then rerun with -SkipBuild.'
    }

    return $compiler
}

function Get-AprodaAlBuildArguments {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [string]$PackageCachePath,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # Without an explicit package cache the compiler resolves no symbols at all, down to base tables.
    return @(
        "/project:$ProjectPath",
        "/packagecachepath:$PackageCachePath",
        "/out:$OutputPath"
    )
}

function Get-AprodaTargetXliffPath {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory)]
        [string]$TargetLanguage
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name) -replace '\.g$', ''
    return Join-Path $SourceFile.DirectoryName "$baseName.$TargetLanguage.xlf"
}

function Get-AprodaXlfDocument {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # LoadFromPath alone leaves note-designation properties unset (null), so every note lookup
    # (Xliff Generator, Developer) silently returns empty - Sync/Test-XliffTranslations set these
    # themselves; every other call site must do the same explicitly.
    [XlfDocument]$document = [XlfDocument]::LoadFromPath($Path)
    $document.developerNoteDesignation = 'Developer'
    $document.xliffGeneratorNoteDesignation = 'Xliff Generator'
    return $document
}

function Get-AprodaSourceHash {
    param(
        [Parameter(Mandatory)]
        [string]$SourceText
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($SourceText)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-AprodaPlaceholders {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if (-not $Text) {
        return @()
    }

    return @([regex]::Matches($Text, '%\d+|#\d+###|@\d+@@@') | ForEach-Object Value)
}

function Get-AprodaMaxLength {
    param(
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Unit
    )

    if ($Unit.Attributes -and $Unit.Attributes['maxwidth'] -and $Unit.Attributes['maxwidth'].Value -match '^\d+$') {
        return [int]$Unit.Attributes['maxwidth'].Value
    }

    return $null
}

function Get-AprodaTargetFiles {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [string]$TargetLanguage
    )

    $targetFiles = @(Get-ChildItem -LiteralPath $ProjectPath -Recurse -File -Filter "*.$TargetLanguage.xlf")
    if (-not $targetFiles) {
        throw "No target XLIFF files (*.$TargetLanguage.xlf) found below '$ProjectPath'. Run -Action Sync first."
    }

    return $targetFiles
}

function Test-AprodaApproved {
    param(
        [Parameter(Mandatory)]
        [XlfDocument]$Document,
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Unit
    )

    $translation = $Document.GetUnitTranslation($Unit)
    if ([string]::IsNullOrWhiteSpace($translation)) {
        return $false
    }

    $targetNode = $Unit.SelectSingleNode("./*[local-name()='target']")
    $hasStateAttribute = $targetNode -and $targetNode.Attributes -and $targetNode.Attributes['state']
    if (-not $hasStateAttribute) {
        return $true
    }

    return $Document.GetState($Unit) -eq [XlfTranslationState]::Translated
}

function Set-AprodaUnitState {
    param(
        [Parameter(Mandatory)]
        [XlfDocument]$Document,
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Unit,
        [Parameter(Mandatory)]
        [ValidateSet('needs-review-translation', 'needs-l10n', 'translated')]
        [string]$State
    )

    $translationState = switch ($State) {
        'needs-review-translation' { [XlfTranslationState]::NeedsReviewTranslation }
        'needs-l10n' { [XlfTranslationState]::NeedsLocalization }
        'translated' { [XlfTranslationState]::Translated }
    }
    $Document.SetState($Unit, $translationState)
}

function Test-AprodaSwissOrthography {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    return $Text -notmatch 'ß'
}

function Get-AprodaContextClass {
    param(
        [Parameter(Mandatory)]
        [XlfDocument]$Document,
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Unit
    )

    $note = $Document.GetUnitXliffGeneratorNote($Unit)
    if ([string]::IsNullOrWhiteSpace($note)) {
        return $null
    }

    $segments = @($note -split ' - ')
    if ($segments.Count -eq 2) {
        # Two segments: no Property part - a label has nothing to name a property after.
        $objectTypeMatch = [regex]::Match($segments[0], '^(\S+)\s')
        $elementTypeMatch = [regex]::Match($segments[1], '^(\S+)\s')
        if (-not $objectTypeMatch.Success -or -not $elementTypeMatch.Success) {
            return $null
        }
        return '{0}|{1}|Label' -f $objectTypeMatch.Groups[1].Value, $elementTypeMatch.Groups[1].Value
    }
    if ($segments.Count -eq 3) {
        $objectTypeMatch = [regex]::Match($segments[0], '^(\S+)\s')
        $elementTypeMatch = [regex]::Match($segments[1], '^(\S+)\s')
        $propertyMatch = [regex]::Match($segments[2], '^Property\s+(\S+)\s*$')
        if (-not $objectTypeMatch.Success -or -not $elementTypeMatch.Success -or -not $propertyMatch.Success) {
            return $null
        }
        return '{0}|{1}|{2}' -f $objectTypeMatch.Groups[1].Value, $elementTypeMatch.Groups[1].Value, $propertyMatch.Groups[1].Value
    }
    return $null
}

function Test-AprodaInvariant {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SourceText
    )

    return $SourceText -notmatch '\p{L}'
}

function Get-AprodaNormalisedSource {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }
    return ($Text.Trim() -replace '\s+', ' ')
}

function Resolve-AprodaInvariantTier {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TargetFiles,
        [Parameter(Mandatory)]
        [hashtable]$DocumentsByPath
    )

    $countsByFile = @{}
    $totalResolved = 0
    foreach ($targetFile in $TargetFiles) {
        [XlfDocument]$document = $DocumentsByPath[$targetFile.FullName]
        $resolvedCount = 0
        foreach ($unit in $document.TranslationUnitNodes()) {
            if (-not $document.GetUnitNeedsTranslation($unit)) {
                continue
            }
            $translation = $document.GetUnitTranslation($unit)
            if (-not [string]::IsNullOrWhiteSpace($translation)) {
                continue
            }

            $source = $document.GetUnitSourceText($unit)
            if (-not (Test-AprodaInvariant -SourceText $source)) {
                continue
            }

            $targetNode = [XlfDocument]::GetNode('target', $unit)
            $targetNode.InnerText = $source
            Set-AprodaUnitState -Document $document -Unit $unit -State 'translated'
            $resolvedCount++
        }
        $countsByFile[$targetFile.FullName] = $resolvedCount
        $totalResolved += $resolvedCount
    }

    return [pscustomobject]@{ Total = $totalResolved; ByFile = $countsByFile }
}

function Get-AprodaApprovedMemoryIndex {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TargetFiles,
        [Parameter(Mandatory)]
        [hashtable]$DocumentsByPath
    )

    $index = @{}
    foreach ($targetFile in $TargetFiles) {
        [XlfDocument]$document = $DocumentsByPath[$targetFile.FullName]
        foreach ($unit in $document.TranslationUnitNodes()) {
            if (-not $document.GetUnitNeedsTranslation($unit)) {
                continue
            }
            if (-not (Test-AprodaApproved -Document $document -Unit $unit)) {
                continue
            }

            $contextClass = Get-AprodaContextClass -Document $document -Unit $unit
            if ($null -eq $contextClass) {
                continue
            }

            $source = $document.GetUnitSourceText($unit)
            $normalisedSource = Get-AprodaNormalisedSource -Text $source
            $placeholderSignature = (Get-AprodaPlaceholders -Text $source) -join '|'
            $key = '{0}::{1}::{2}' -f $normalisedSource, $contextClass, $placeholderSignature

            if (-not $index.ContainsKey($key)) {
                $index[$key] = [System.Collections.Generic.HashSet[string]]::new()
            }
            [void]$index[$key].Add($document.GetUnitTranslation($unit))
        }
    }
    return $index
}

function Resolve-AprodaMemoryTier {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TargetFiles,
        [Parameter(Mandatory)]
        [hashtable]$MemoryIndex,
        [Parameter(Mandatory)]
        [hashtable]$DocumentsByPath
    )

    $countsByFile = @{}
    $ambiguous = @()
    $totalResolved = 0
    foreach ($targetFile in $TargetFiles) {
        [XlfDocument]$document = $DocumentsByPath[$targetFile.FullName]
        $resolvedCount = 0
        foreach ($unit in $document.TranslationUnitNodes()) {
            if (-not $document.GetUnitNeedsTranslation($unit)) {
                continue
            }
            $translation = $document.GetUnitTranslation($unit)
            if (-not [string]::IsNullOrWhiteSpace($translation)) {
                continue
            }

            $contextClass = Get-AprodaContextClass -Document $document -Unit $unit
            if ($null -eq $contextClass) {
                continue
            }

            $source = $document.GetUnitSourceText($unit)
            $normalisedSource = Get-AprodaNormalisedSource -Text $source
            $placeholderSignature = (Get-AprodaPlaceholders -Text $source) -join '|'
            $key = '{0}::{1}::{2}' -f $normalisedSource, $contextClass, $placeholderSignature

            if (-not $MemoryIndex.ContainsKey($key)) {
                continue
            }

            $candidates = $MemoryIndex[$key]
            if ($candidates.Count -gt 1) {
                $ambiguous += [pscustomobject]@{ unitId = $unit.Attributes['id'].Value; candidateCount = $candidates.Count }
                continue
            }

            $candidateTarget = @($candidates)[0]
            $maxLength = Get-AprodaMaxLength -Unit $unit
            if ($null -ne $maxLength -and $candidateTarget.Length -gt $maxLength) {
                continue
            }

            $targetNode = [XlfDocument]::GetNode('target', $unit)
            $targetNode.InnerText = $candidateTarget
            Set-AprodaUnitState -Document $document -Unit $unit -State 'translated'
            $resolvedCount++
        }
        $countsByFile[$targetFile.FullName] = $resolvedCount
        $totalResolved += $resolvedCount
    }

    return [pscustomobject]@{ Total = $totalResolved; ByFile = $countsByFile; Ambiguous = $ambiguous }
}

function Get-AprodaShortKey {
    param(
        [Parameter(Mandatory)]
        [int]$Ordinal,
        [Parameter(Mandatory)]
        [string]$SourceHash
    )

    return '{0}-{1}' -f $Ordinal, $SourceHash.Substring(0, 3)
}

function Get-AprodaManifestPath {
    param(
        [Parameter(Mandatory)]
        [string]$AiBatchPath
    )

    $directory = Split-Path -Path $AiBatchPath -Parent
    $name = Split-Path -Path $AiBatchPath -Leaf
    if ($name -match '\.ai\.json$') {
        return Join-Path $directory ($name -replace '\.ai\.json$', '.manifest.json')
    }
    return Join-Path $directory (([System.IO.Path]::GetFileNameWithoutExtension($name)) + '.manifest.json')
}

function Get-AprodaDefaultReportPath {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        [Parameter(Mandatory)]
        [string]$RunId
    )

    return Join-Path $ProjectPath ".aproda\translation\.cache\run-$RunId.json"
}

function Get-AprodaRunReport {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$RunId,
        [Parameter(Mandatory)]
        [string]$Language
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 12
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        runId         = $RunId
        language      = $Language
        batches       = @()
        ai            = @()
        validation    = [pscustomobject]@{ issues = 0; strict = $false }
    }
}

function Write-AprodaRunReport {
    param(
        [Parameter(Mandatory)]
        [object]$Report,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Get-AprodaTranslationStatistics {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TargetFiles
    )

    $total = 0
    $missing = 0
    $needsReview = 0
    $approved = 0
    foreach ($targetFile in $TargetFiles) {
        [XlfDocument]$document = Get-AprodaXlfDocument -Path $targetFile.FullName
        foreach ($unit in $document.TranslationUnitNodes()) {
            if (-not $document.GetUnitNeedsTranslation($unit)) {
                continue
            }

            $total++
            $translation = $document.GetUnitTranslation($unit)
            if ([string]::IsNullOrWhiteSpace($translation)) {
                $missing++
            }
            elseif (Test-AprodaApproved -Document $document -Unit $unit) {
                $approved++
            }
            else {
                $needsReview++
            }
        }
    }

    return [pscustomobject]@{
        Total       = $total
        Missing     = $missing
        NeedsReview = $needsReview
        Approved    = $approved
        Valid       = $approved
    }
}

function Write-AprodaTranslationStatistics {
    param(
        [Parameter(Mandatory)]
        [object]$Statistics
    )

    Write-Host "XLIFF: $($Statistics.Total) translatable unit(s): $($Statistics.Missing) missing, $($Statistics.NeedsReview) need review, $($Statistics.Valid) valid."
}

function Invoke-AprodaXliffValidation {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TargetFiles,
        [switch]$Strict,
        [switch]$RequireApproved
    )

    $issues = @()
    $unapproved = @()
    foreach ($targetFile in $TargetFiles) {
        $issues += @(Test-XliffTranslations -targetPath $targetFile.FullName -checkForMissing -checkForProblems -translationRules @('Placeholders', 'OptionMemberCount', 'OptionLeadingSpaces', 'ConsecutiveSpacesConsistent') -printProblems)
        [XlfDocument]$document = Get-AprodaXlfDocument -Path $targetFile.FullName
        foreach ($unit in $document.TranslationUnitNodes()) {
            if (-not $document.GetUnitNeedsTranslation($unit)) {
                continue
            }

            $translation = $document.GetUnitTranslation($unit)
            if ($translation -and -not (Test-AprodaSwissOrthography -Text $translation)) {
                $issues += "Swiss German orthography violation in '$($targetFile.Name)': unit '$($unit.Attributes['id'].Value)' contains ß."
            }
            if ($RequireApproved -and -not (Test-AprodaApproved -Document $document -Unit $unit)) {
                $unapproved += "$($targetFile.Name):$($unit.Attributes['id'].Value)"
            }
        }
    }

    $statistics = Get-AprodaTranslationStatistics -TargetFiles $TargetFiles
    Write-AprodaTranslationStatistics -Statistics $statistics
    # Orthography/placeholder issues apply regardless of approval state; surface them even without -Strict.
    foreach ($issue in $issues) {
        Write-Warning $issue
    }
    if ($issues.Count -gt 0 -and $Strict) {
        throw "XLIFF validation found $($issues.Count) issue(s)."
    }
    if ($RequireApproved -and $unapproved.Count -gt 0) {
        throw "XLIFF approval gate found $($unapproved.Count) unapproved translatable unit(s): $($unapproved -join ', ')."
    }

    return [pscustomobject]@{
        Statistics      = $statistics
        IssueCount      = $issues.Count
        UnapprovedCount = $unapproved.Count
    }
}

function Export-AprodaOpenTranslations {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TargetFiles,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [Parameter(Mandatory)]
        [string]$TargetLanguage,
        [Parameter(Mandatory)]
        [string]$OutputManifestPath,
        [int]$StartOffset = 0,
        [int]$ItemLimit = 30
    )

    $items = @()
    for ($fileIndex = 0; $fileIndex -lt $TargetFiles.Count; $fileIndex++) {
        $targetFile = $TargetFiles[$fileIndex]
        [XlfDocument]$document = Get-AprodaXlfDocument -Path $targetFile.FullName
        foreach ($unit in $document.TranslationUnitNodes()) {
            if (-not $document.GetUnitNeedsTranslation($unit)) {
                continue
            }

            $translation = $document.GetUnitTranslation($unit)
            if (-not [string]::IsNullOrWhiteSpace($translation)) {
                continue
            }

            $source = $document.GetUnitSourceText($unit)
            $unitId = $unit.Attributes['id'].Value
            $items += [pscustomobject]@{
                FileIndex          = $fileIndex
                TargetFileIndex    = $fileIndex
                UnitId             = $unitId
                Source             = $source
                SourceHash         = Get-AprodaSourceHash -SourceText $source
                XliffGeneratorNote = $document.GetUnitXliffGeneratorNote($unit)
                DeveloperNote      = $document.GetUnitDeveloperNote($unit)
                Placeholders       = @(Get-AprodaPlaceholders -Text $source)
                MaxLength          = Get-AprodaMaxLength -Unit $unit
            }
        }
    }

    $totalOpen = $items.Count
    $selectedItems = @($items | Select-Object -Skip $StartOffset)
    if ($ItemLimit -gt 0) {
        $selectedItems = @($selectedItems | Select-Object -First $ItemLimit)
    }
    $batchId = [guid]::NewGuid().ToString()
    $aiItems = @()
    $manifestItems = @()
    for ($itemIndex = 0; $itemIndex -lt $selectedItems.Count; $itemIndex++) {
        $item = $selectedItems[$itemIndex]
        $key = Get-AprodaShortKey -Ordinal ($itemIndex + 1) -SourceHash $item.SourceHash
        $aiItem = [ordered]@{ k = $key; s = $item.Source; c = $item.XliffGeneratorNote }
        if (-not [string]::IsNullOrWhiteSpace($item.DeveloperNote)) {
            $aiItem.d = $item.DeveloperNote
        }
        if ($null -ne $item.MaxLength) {
            $aiItem.m = $item.MaxLength
        }
        $aiItems += [pscustomobject]$aiItem
        $manifestItems += [pscustomobject][ordered]@{
            k       = $key
            file    = $item.FileIndex
            unitId  = $item.UnitId
            srcHash = $item.SourceHash
            ph      = @($item.Placeholders)
        }
    }
    $batch = [ordered]@{ v = 1; b = $batchId; lang = $TargetLanguage; items = $aiItems }
    $manifest = [ordered]@{ v = 1; b = $batchId; files = @($TargetFiles.FullName); items = $manifestItems }
    $outputDirectory = Split-Path -Path $OutputPath -Parent
    if ($outputDirectory) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $manifestDirectory = Split-Path -Path $OutputManifestPath -Parent
    if ($manifestDirectory) {
        New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
    }
    $batch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputManifestPath -Encoding utf8
    $remaining = [Math]::Max(0, $totalOpen - ($StartOffset + $selectedItems.Count))
    Write-Host "Exported $($selectedItems.Count) open translation unit(s) to '$OutputPath'; $remaining remaining."
    return [pscustomobject]@{ BatchId = $batchId; Emitted = $selectedItems.Count; Remaining = $remaining; BatchPath = $OutputPath; ManifestPath = $OutputManifestPath }
}

function Invoke-AprodaAtomicXliffCommit {
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocumentsByPath
    )

    $stagedDocuments = @()
    $replacedDocuments = @()
    try {
        foreach ($targetPath in @($DocumentsByPath.Keys | Sort-Object)) {
            $directory = Split-Path -Path $targetPath -Parent
            $fileName = Split-Path -Path $targetPath -Leaf
            $temporaryPath = Join-Path $directory ('.{0}.{1}.tmp' -f $fileName, [guid]::NewGuid())
            $backupPath = Join-Path $directory ('.{0}.{1}.bak' -f $fileName, [guid]::NewGuid())
            $replacementBackupPath = Join-Path $directory ('.{0}.{1}.replace.bak' -f $fileName, [guid]::NewGuid())
            $DocumentsByPath[$targetPath].SaveToFilePath($temporaryPath)
            [System.IO.File]::Copy($targetPath, $backupPath, $false)
            $stagedDocuments += [pscustomobject]@{ TargetPath = $targetPath; TemporaryPath = $temporaryPath; BackupPath = $backupPath; ReplacementBackupPath = $replacementBackupPath }
        }

        $commitIndex = 0
        # Failure injection: the rollback path is otherwise unreachable without mocking the filesystem.
        [int]$failureAtCommit = 0
        [void][int]::TryParse($env:APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT, [ref]$failureAtCommit)
        foreach ($stagedDocument in $stagedDocuments) {
            $commitIndex++
            if ($failureAtCommit -eq $commitIndex) {
                throw "Injected XLIFF commit failure at replacement $commitIndex."
            }
            [System.IO.File]::Replace($stagedDocument.TemporaryPath, $stagedDocument.TargetPath, $stagedDocument.ReplacementBackupPath, $true)
            $replacedDocuments += $stagedDocument
        }
    }
    catch {
        $commitFailure = $_
        $rollbackFailures = @()
        for ($replacedIndex = $replacedDocuments.Count - 1; $replacedIndex -ge 0; $replacedIndex--) {
            $replacedDocument = $replacedDocuments[$replacedIndex]
            try {
                [System.IO.File]::Replace($replacedDocument.BackupPath, $replacedDocument.TargetPath, $replacedDocument.TemporaryPath, $true)
            }
            catch {
                $rollbackFailures += $_.Exception.Message
            }
        }
        if ($rollbackFailures.Count -gt 0) {
            throw "XLIFF commit failed: $($commitFailure.Exception.Message). Rollback also failed: $($rollbackFailures -join '; ')."
        }
        throw "XLIFF commit failed and all replaced targets were rolled back: $($commitFailure.Exception.Message)"
    }
    finally {
        foreach ($stagedDocument in $stagedDocuments) {
            Remove-Item -LiteralPath $stagedDocument.TemporaryPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $stagedDocument.BackupPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $stagedDocument.ReplacementBackupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Apply-AprodaTranslations {
    param(
        [Parameter(Mandatory)]
        [string]$InputBatchPath,
        [Parameter(Mandatory)]
        [string]$InputResponsePath,
        [Parameter(Mandatory)]
        [string]$InputManifestPath,
        [Parameter(Mandatory)]
        [string]$InputReportPath
    )

    $batch = Get-Content -LiteralPath $InputBatchPath -Raw | ConvertFrom-Json -Depth 8
    $manifest = Get-Content -LiteralPath $InputManifestPath -Raw | ConvertFrom-Json -Depth 8
    $response = Get-Content -LiteralPath $InputResponsePath -Raw | ConvertFrom-Json -Depth 8
    if ($batch.v -ne 1 -or $manifest.v -ne 1 -or $response.v -ne 1 -or $manifest.b -ne $batch.b) {
        throw 'Batch, manifest, and response schema version or batch ID do not match.'
    }

    $batchItems = @($batch.items)
    $manifestItems = @($manifest.items)
    $responses = @($response.t)
    if ($batchItems.Count -ne $manifestItems.Count) {
        throw 'The batch and manifest item counts do not match.'
    }

    $manifestByOrdinal = @{}
    foreach ($manifestItem in $manifestItems) {
        if ($manifestItem.k -notmatch '^(\d+)-([0-9a-f]{3})$') {
            throw "The manifest contains an invalid key '$($manifestItem.k)'."
        }
        $ordinal = [int]$Matches[1]
        if ($ordinal -lt 1 -or $ordinal -gt $manifestItems.Count -or $manifestByOrdinal.ContainsKey($ordinal)) {
            throw "The manifest contains an invalid or duplicate ordinal '$ordinal'."
        }
        if ($Matches[2] -ne $manifestItem.srcHash.Substring(0, 3)) {
            throw "The manifest key '$($manifestItem.k)' does not match its source hash."
        }
        $manifestByOrdinal[$ordinal] = $manifestItem
    }

    $responseOrdinals = @{}
    $pendingChanges = @()
    $documentsByPath = @{}
    foreach ($responseItem in $responses) {
        if ($responseItem.k -notmatch '^(\d+)-([0-9a-f]{3})$') {
            throw "The response contains an invalid key '$($responseItem.k)'."
        }
        $ordinal = [int]$Matches[1]
        $hash3 = $Matches[2]
        if ($ordinal -lt 1 -or $ordinal -gt $manifestItems.Count) {
            throw "The response contains out-of-range ordinal '$ordinal'."
        }
        if ($responseOrdinals.ContainsKey($ordinal)) {
            throw "The response contains duplicate ordinal '$ordinal'."
        }
        $manifestItem = $manifestByOrdinal[$ordinal]
        if ($hash3 -ne $manifestItem.srcHash.Substring(0, 3)) {
            throw "The response source hash mismatch for ordinal '$ordinal'."
        }
        $responseOrdinals[$ordinal] = $responseItem
    }
    $expectedOrdinals = if ($manifestItems.Count -gt 0) { @(1..$manifestItems.Count) } else { @() }
    $missingOrdinals = @($expectedOrdinals | Where-Object { -not $responseOrdinals.ContainsKey($_) })
    if ($responses.Count -ne $manifestItems.Count -or $missingOrdinals.Count -gt 0) {
        throw "The response does not provide complete coverage. Missing ordinals: $($missingOrdinals -join ', ')."
    }
    if ($response.b -ne $batch.b) {
        throw 'The response batch ID does not match the batch.'
    }

    foreach ($ordinal in $expectedOrdinals) {
        $responseItem = $responseOrdinals[$ordinal]
        $manifestItem = $manifestByOrdinal[$ordinal]
        $targetFileIndex = [int]$manifestItem.file
        if ($targetFileIndex -lt 0 -or $targetFileIndex -ge @($manifest.files).Count) {
            throw "The manifest has an invalid target file index for ordinal '$ordinal'."
        }
        $targetFile = Get-Item -LiteralPath $manifest.files[$targetFileIndex] -ErrorAction Stop
        if (-not $documentsByPath.ContainsKey($targetFile.FullName)) {
            $documentsByPath[$targetFile.FullName] = Get-AprodaXlfDocument -Path $targetFile.FullName
        }
        [XlfDocument]$document = $documentsByPath[$targetFile.FullName]
        $unit = $document.FindTranslationUnit($manifestItem.unitId)
        if (-not $unit) {
            throw "Translation unit '$($manifestItem.unitId)' no longer exists. Export a new batch."
        }

        $currentSource = $document.GetUnitSourceText($unit)
        if ((Get-AprodaSourceHash -SourceText $currentSource) -ne $manifestItem.srcHash) {
            throw "Source text for '$($manifestItem.unitId)' changed. Export a new batch."
        }

        $targetText = [string]$responseItem.t
        $sourcePlaceholderSignature = (Get-AprodaPlaceholders -Text $currentSource) -join '|'
        $targetPlaceholderSignature = (Get-AprodaPlaceholders -Text $targetText) -join '|'
        if ($sourcePlaceholderSignature -ne $targetPlaceholderSignature) {
            throw "Placeholder mismatch for '$($manifestItem.unitId)'."
        }

        $maxLength = Get-AprodaMaxLength -Unit $unit
        if ($null -ne $maxLength -and $targetText.Length -gt $maxLength) {
            throw "Translation for '$($manifestItem.unitId)' exceeds the XLIFF maxwidth of $maxLength."
        }
        if ([string]::IsNullOrWhiteSpace($targetText)) {
            throw "The response target for ordinal '$ordinal' is empty."
        }
        if (-not (Test-AprodaSwissOrthography -Text $targetText)) {
            throw "Swiss German orthography violation for ordinal '$ordinal': target contains ß."
        }
        $pendingChanges += [pscustomobject]@{ Document = $document; Unit = $unit; Target = $targetText; TargetPath = $targetFile.FullName; Key = $responseItem.k; UnitId = $manifestItem.unitId; SourceHash = $manifestItem.srcHash }
    }

    foreach ($change in $pendingChanges) {
        Set-AprodaUnitState -Document $change.Document -Unit $change.Unit -State 'needs-review-translation'
        $targetNode = [XlfDocument]::GetNode('target', $change.Unit)
        $targetNode.InnerText = $change.Target
    }

    Invoke-AprodaAtomicXliffCommit -DocumentsByPath $documentsByPath
    $report = Get-AprodaRunReport -Path $InputReportPath -RunId $batch.b -Language $batch.lang
    $report.ai = @($report.ai) + @($pendingChanges | ForEach-Object { [pscustomobject]@{ k = $_.Key; unitId = $_.UnitId; target = $_.Target; srcHash = $_.SourceHash; tier = 'simple' } })
    $report.batches = @($report.batches) + [pscustomobject]@{ batchId = $batch.b; items = $pendingChanges.Count; applied = $pendingChanges.Count; rejected = 0; rejectReason = $null }
    Write-AprodaRunReport -Report $report -Path $InputReportPath
    Write-Host "Applied $($pendingChanges.Count) translation(s) to $($documentsByPath.Count) XLIFF file(s)."
}

function Get-AprodaReviewReport {
    param(
        [Parameter(Mandatory)]
        [object]$RunReport,
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TargetFiles
    )

    $documents = @($TargetFiles | ForEach-Object { Get-AprodaXlfDocument -Path $_.FullName })
    $pending = 0
    $accepted = 0
    $corrected = 0
    $stale = 0
    foreach ($aiItem in @($RunReport.ai)) {
        $unit = $null
        $document = $null
        foreach ($candidate in $documents) {
            $candidateUnit = $candidate.FindTranslationUnit($aiItem.unitId)
            if ($candidateUnit) {
                $unit = $candidateUnit
                $document = $candidate
                break
            }
        }
        if (-not $unit -or ((Get-AprodaSourceHash -SourceText $document.GetUnitSourceText($unit)) -ne $aiItem.srcHash)) {
            $stale++
        }
        elseif (-not (Test-AprodaApproved -Document $document -Unit $unit)) {
            $pending++
        }
        elseif ($document.GetUnitTranslation($unit) -eq $aiItem.target) {
            $accepted++
        }
        else {
            $corrected++
        }
    }
    $review = [pscustomobject]@{
        pending        = $pending
        accepted       = $accepted
        corrected      = $corrected
        stale          = $stale
        correctionRate = if (($accepted + $corrected) -eq 0) { $null } else { $corrected / ($accepted + $corrected) }
    }
    $RunReport | Add-Member -NotePropertyName review -NotePropertyValue $review -Force
    return $review
}

$resolvedAppPath = (Resolve-Path -LiteralPath $AppPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath (Join-Path $resolvedAppPath 'app.json') -PathType Leaf)) {
    throw "No app.json found in '$resolvedAppPath'. Pass the AL app root with -AppPath."
}

$toolDirectory = Get-AprodaXliffSyncScriptDirectory
$vendorDirectory = Join-Path $toolDirectory 'vendor\XliffSync'
. ([scriptblock]::Create((Get-AprodaXliffSyncSource -Path (Join-Path $vendorDirectory 'Model\XlfDocument.ps1'))))
. ([scriptblock]::Create((Get-AprodaXliffSyncSource -Path (Join-Path $vendorDirectory 'Public\Sync-XliffTranslations.ps1'))))
. ([scriptblock]::Create((Get-AprodaXliffSyncSource -Path (Join-Path $vendorDirectory 'Public\Test-XliffTranslations.ps1'))))

switch ($Action) {
    'Sync' {
        if (-not $SkipBuild) {
            $compiler = Find-AprodaAlCompiler
            $packageCachePath = Join-Path $resolvedAppPath '.alpackages'
            if (-not (Test-Path -LiteralPath $packageCachePath)) {
                throw "Symbol cache '$packageCachePath' not found. Download symbols first, or rerun with -SkipBuild."
            }

            # The build runs only to regenerate *.g.xlf; the app artifact itself is disposable.
            $buildOutputPath = Join-Path ([System.IO.Path]::GetTempPath()) ('aproda-xliffsync-{0}.app' -f [guid]::NewGuid())
            Write-Host "Building AL app '$resolvedAppPath'."
            Push-Location -LiteralPath $resolvedAppPath
            try {
                & $compiler @(Get-AprodaAlBuildArguments -ProjectPath $resolvedAppPath -PackageCachePath $packageCachePath -OutputPath $buildOutputPath)
                if ($LASTEXITCODE -ne 0) {
                    throw "AL build failed with exit code $LASTEXITCODE."
                }
            }
            finally {
                Pop-Location
                Remove-Item -LiteralPath $buildOutputPath -Force -ErrorAction SilentlyContinue
            }
        }

        $sourceFiles = @(Get-ChildItem -LiteralPath $resolvedAppPath -Recurse -File -Filter '*.g.xlf')
        if (-not $sourceFiles) {
            throw "No generated XLIFF files (*.g.xlf) found below '$resolvedAppPath'."
        }

        foreach ($sourceFile in $sourceFiles) {
            Write-Host "Synchronizing '$($sourceFile.Name)' to '$Language'."
            Sync-XliffTranslations -sourcePath $sourceFile.FullName -targetLanguage $Language -detectSourceTextChanges $true -useSelfClosingTags
        }

        $targetFiles = Get-AprodaTargetFiles -ProjectPath $resolvedAppPath -TargetLanguage $Language
        Invoke-AprodaXliffValidation -TargetFiles $targetFiles -Strict:$FailOnIssues -RequireApproved:$FailOnUnapproved
        break
    }
    'Resolve' {
        $runId = [guid]::NewGuid().ToString()
        if (-not $ReportPath) {
            $ReportPath = Get-AprodaDefaultReportPath -ProjectPath $resolvedAppPath -RunId $runId
        }
        $targetFiles = Get-AprodaTargetFiles -ProjectPath $resolvedAppPath -TargetLanguage $Language
        $documentsByPath = @{}
        foreach ($targetFile in $targetFiles) {
            $documentsByPath[$targetFile.FullName] = Get-AprodaXlfDocument -Path $targetFile.FullName
        }
        $invariantResult = Resolve-AprodaInvariantTier -TargetFiles $targetFiles -DocumentsByPath $documentsByPath
        $memoryIndex = Get-AprodaApprovedMemoryIndex -TargetFiles $targetFiles -DocumentsByPath $documentsByPath
        $memoryResult = Resolve-AprodaMemoryTier -TargetFiles $targetFiles -MemoryIndex $memoryIndex -DocumentsByPath $documentsByPath
        if (($invariantResult.Total + $memoryResult.Total) -gt 0) {
            Invoke-AprodaAtomicXliffCommit -DocumentsByPath $documentsByPath
        }
        $statistics = Get-AprodaTranslationStatistics -TargetFiles $targetFiles

        $runReport = Get-AprodaRunReport -Path $ReportPath -RunId $runId -Language $Language
        $totals = [pscustomobject]@{
            translatable = $statistics.Total
            open         = $statistics.Missing
            invariant    = $invariantResult.Total
            memoryExact  = $memoryResult.Total
        }
        $runReport | Add-Member -NotePropertyName totals -NotePropertyValue $totals -Force
        $runReport | Add-Member -NotePropertyName ambiguous -NotePropertyValue @($memoryResult.Ambiguous) -Force
        Write-AprodaRunReport -Report $runReport -Path $ReportPath
        Write-Host "XLIFF resolve: $($totals.translatable) translatable, $($totals.invariant) invariant, $($totals.memoryExact) memory-exact, $($totals.open) open; $(@($runReport.ambiguous).Count) ambiguous."
        break
    }
    'ExportOpen' {
        if (-not $BatchPath) {
            $BatchPath = Join-Path ([System.IO.Path]::GetTempPath()) "aproda-xliff-open-$Language.batch.ai.json"
        }
        if (-not $ManifestPath) {
            $ManifestPath = Get-AprodaManifestPath -AiBatchPath $BatchPath
        }
        $targetFiles = Get-AprodaTargetFiles -ProjectPath $resolvedAppPath -TargetLanguage $Language
        Export-AprodaOpenTranslations -TargetFiles $targetFiles -OutputPath $BatchPath -OutputManifestPath $ManifestPath -TargetLanguage $Language -StartOffset $Offset -ItemLimit $MaxItems
        break
    }
    'Apply' {
        if (-not $BatchPath -or -not $ResponsePath) {
            throw 'Apply requires -BatchPath and -ResponsePath.'
        }
        if (-not $ManifestPath) {
            $ManifestPath = Get-AprodaManifestPath -AiBatchPath $BatchPath
        }
        $batchMetadata = Get-Content -LiteralPath $BatchPath -Raw | ConvertFrom-Json -Depth 3
        if (-not $ReportPath) {
            $ReportPath = Get-AprodaDefaultReportPath -ProjectPath $resolvedAppPath -RunId $batchMetadata.b
        }
        try {
            Apply-AprodaTranslations -InputBatchPath $BatchPath -InputResponsePath $ResponsePath -InputManifestPath $ManifestPath -InputReportPath $ReportPath
        }
        catch {
            $applyFailure = $_
            $runReport = Get-AprodaRunReport -Path $ReportPath -RunId $batchMetadata.b -Language $batchMetadata.lang
            $runReport.batches = @($runReport.batches) + [pscustomobject]@{ batchId = $batchMetadata.b; items = @($batchMetadata.items).Count; applied = 0; rejected = 1; rejectReason = $applyFailure.Exception.Message }
            Write-AprodaRunReport -Report $runReport -Path $ReportPath
            throw $applyFailure
        }
        break
    }
    'Validate' {
        $targetFiles = Get-AprodaTargetFiles -ProjectPath $resolvedAppPath -TargetLanguage $Language
        Invoke-AprodaXliffValidation -TargetFiles $targetFiles -Strict:$FailOnIssues -RequireApproved:$FailOnUnapproved
        break
    }
    'Report' {
        if (-not $ReportPath) {
            $reportDirectory = Join-Path $resolvedAppPath '.aproda\translation\.cache'
            $ReportPath = Get-ChildItem -LiteralPath $reportDirectory -Filter 'run-*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1 -ExpandProperty FullName
            if (-not $ReportPath) {
                throw "No run report found below '$reportDirectory'. Pass -ReportPath explicitly."
            }
        }
        $runReport = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json -Depth 12
        $targetFiles = Get-AprodaTargetFiles -ProjectPath $resolvedAppPath -TargetLanguage $Language
        $review = Get-AprodaReviewReport -RunReport $runReport -TargetFiles $targetFiles
        Write-AprodaRunReport -Report $runReport -Path $ReportPath
        Write-Host "XLIFF review: $($review.accepted) accepted, $($review.corrected) corrected, $($review.pending) pending, $($review.stale) stale; correction rate: $($review.correctionRate)."
        break
    }
}

Write-Host "XLIFF action '$Action' completed."