[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testDirectory = if ($PSCommandPath) { Split-Path -Path $PSCommandPath -Parent } else { $env:APRODA_XLIFFSYNC_TESTDIR }
if (-not $testDirectory) {
    throw 'Cannot locate the Stage 0 test directory. Set APRODA_XLIFFSYNC_TESTDIR when content-loading the test script.'
}
$toolDirectory = Split-Path -Path $testDirectory -Parent
$fixtureDirectory = Join-Path $testDirectory 'fixtures'
$toolPath = Join-Path $toolDirectory 'Invoke-AprodaBuildXliffSync.ps1'
$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "aproda-xliff-stage0-$([guid]::NewGuid())"
$results = @()

function Assert-Stage0 {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Stage0Tool {
    param([hashtable]$Parameters)

    $previousScriptDirectory = $env:APRODA_XLIFFSYNC_SCRIPTDIR
    $env:APRODA_XLIFFSYNC_SCRIPTDIR = $toolDirectory
    try {
        . ([scriptblock]::Create((Get-Content -LiteralPath $toolPath -Raw))) @Parameters
    }
    finally {
        $env:APRODA_XLIFFSYNC_SCRIPTDIR = $previousScriptDirectory
    }
}

function New-Stage0Project {
    param([switch]$IncludeSecondTarget)

    $projectPath = Join-Path $workRoot ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $projectPath 'app.json') -Encoding utf8 -Value '{}'
    Copy-Item -LiteralPath (Join-Path $fixtureDirectory 'Stage0.g.xlf') -Destination (Join-Path $projectPath 'Stage0.g.xlf')
    Copy-Item -LiteralPath (Join-Path $fixtureDirectory 'Stage0.de-CH.xlf') -Destination (Join-Path $projectPath 'Stage0.de-CH.xlf')
    if ($IncludeSecondTarget) {
        Copy-Item -LiteralPath (Join-Path $fixtureDirectory 'Stage0.de-CH.xlf') -Destination (Join-Path $projectPath 'Stage1.de-CH.xlf')
    }
    return $projectPath
}

function Get-Stage0Hash {
    param([string]$ProjectPath)
    return (Get-FileHash -LiteralPath (Join-Path $ProjectPath 'Stage0.de-CH.xlf') -Algorithm SHA256).Hash
}

function Get-Stage0TargetHashes {
    param([string]$ProjectPath)

    return @(Get-ChildItem -LiteralPath $ProjectPath -File -Filter '*.de-CH.xlf' |
        Sort-Object Name |
        ForEach-Object { '{0}:{1}' -f $_.Name, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
}

function Export-Stage0Batch {
    param([string]$ProjectPath, [int]$MaxItems = 0, [int]$Offset = 0)
    $batchPath = Join-Path $ProjectPath 'batch.ai.json'
    $exportResult = Invoke-Stage0Tool @{ AppPath = $ProjectPath; Action = 'ExportOpen'; BatchPath = $batchPath; MaxItems = $MaxItems; Offset = $Offset }
    return [pscustomobject]@{
        BatchPath    = $batchPath
        ManifestPath = Join-Path $ProjectPath 'batch.manifest.json'
        Batch        = Get-Content -LiteralPath $batchPath -Raw | ConvertFrom-Json -Depth 10
        Manifest     = Get-Content -LiteralPath (Join-Path $ProjectPath 'batch.manifest.json') -Raw | ConvertFrom-Json -Depth 10
        Result       = $exportResult
    }
}

function New-Stage0Response {
    param([object]$Batch, [string]$BatchId = $Batch.b)
    $translations = @{
        'caption'      = 'Kundenname'
        'placeholders' = 'Gebucht %1 von %2'
        'maxwidth'     = 'Grösse'
        'option'       = 'Offen,Geschlossen'
        'invariant'    = '123-45'
    }
    $targets = @()
    foreach ($item in @($Batch.items)) {
        $targets += [pscustomobject]@{ k = $item.k; t = $translations[$item.s -replace 'Customer Name', 'caption' -replace 'Posted %1 of %2', 'placeholders' -replace 'Size', 'maxwidth' -replace 'Open,Closed', 'option' -replace '123-45', 'invariant'] }
    }
    return [pscustomobject]@{ v = 1; b = $BatchId; t = $targets }
}

function Write-Stage0Response {
    param([string]$ProjectPath, [object]$Response)
    $responsePath = Join-Path $ProjectPath 'response.json'
    $Response | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $responsePath -Encoding utf8
    return $responsePath
}

function Invoke-Stage0Apply {
    param([string]$ProjectPath, [object]$Export, [string]$ResponsePath)
    Invoke-Stage0Tool @{ AppPath = $ProjectPath; Action = 'Apply'; BatchPath = $Export.BatchPath; ManifestPath = $Export.ManifestPath; ResponsePath = $ResponsePath }
}

function Assert-Stage0ApplyRejected {
    param([string]$ProjectPath, [object]$Export, [string]$ResponsePath)
    $before = Get-Stage0Hash $ProjectPath
    $rejectionMessage = $null
    try {
        Invoke-Stage0Apply $ProjectPath $Export $ResponsePath
    }
    catch {
        $rejectionMessage = $_.Exception.Message
    }
    Assert-Stage0 (-not [string]::IsNullOrWhiteSpace($rejectionMessage)) 'Invalid response was accepted.'
    Assert-Stage0 ((Get-Stage0Hash $ProjectPath) -eq $before) 'Rejected batch changed the target file.'
    return $rejectionMessage
}

function Invoke-Stage0Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:results += [pscustomobject]@{ Name = $Name; Result = 'PASS'; Detail = '' }
        Write-Host "$Name PASS"
    }
    catch {
        $script:results += [pscustomobject]@{ Name = $Name; Result = 'FAIL'; Detail = $_.Exception.Message }
        Write-Host "$Name FAIL: $($_.Exception.Message)"
    }
}

New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
try {
    Invoke-Stage0Case 'T1' {
        $project = New-Stage0Project
        $export = Export-Stage0Batch -ProjectPath $project
        $responsePath = Write-Stage0Response -ProjectPath $project -Response (New-Stage0Response -Batch $export.Batch)
        Invoke-Stage0Apply -ProjectPath $project -Export $export -ResponsePath $responsePath
        [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf')
        Assert-Stage0 (@($xml.SelectNodes("//*[local-name()='target']") | Where-Object { $_.GetAttribute('state') -ne 'needs-review-translation' }).Count -eq 0) 'Not every applied unit has needs-review-translation.'
        Assert-Stage0 ($xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='caption']/*[local-name()='target']").InnerText -eq 'Kundenname') 'Caption target text was not written.'
        Assert-Stage0 ($xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='placeholders']/*[local-name()='target']").InnerText -eq 'Gebucht %1 von %2') 'Placeholder target text was not written.'
        Assert-Stage0 ($xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='maxwidth']/*[local-name()='target']").InnerText -eq 'Grösse') 'Maxwidth target text was not written.'
        Assert-Stage0 ($xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='option']/*[local-name()='target']").InnerText -eq 'Offen,Geschlossen') 'Option target text was not written.'
        Assert-Stage0 ($xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='invariant']/*[local-name()='target']").InnerText -eq '123-45') 'Invariant target text was not written.'
    }
    Invoke-Stage0Case 'T2' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; $response.t = @($response.t | Select-Object -Skip 1)
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response))
    }
    Invoke-Stage0Case 'T3' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; $response.t += $response.t[0]
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response))
    }
    Invoke-Stage0Case 'T4' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; $response.t[0].k = '99-abc'
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response))
    }
    Invoke-Stage0Case 'T5' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; $response.t[0].k = '1-fff'
        $message = Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response); Assert-Stage0 ($message -match "ordinal '1'") 'Wrong hash3 did not name its ordinal.'
    }
    Invoke-Stage0Case 'T6' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; (Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf') -Raw).Replace('Customer Name', 'Customer Number') | Set-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf') -Encoding utf8
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project (New-Stage0Response $export.Batch)))
    }
    Invoke-Stage0Case 'T7' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; ($response.t | Where-Object { $_.t -match 'Gebucht' }).t = 'Gebucht %1'
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response))
    }
    Invoke-Stage0Case 'T8' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; ($response.t | Where-Object { $_.t -eq 'Grösse' }).t = 'Eine lange Grösse'
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response))
    }
    Invoke-Stage0Case 'T9' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; $response.t[0].t = 'Straße'
        $message = Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response); Assert-Stage0 ($message -match "ordinal '1'") 'ß rejection did not name its ordinal.'
    }
    Invoke-Stage0Case 'T10' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; $response.t[0].t = ''
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response))
    }
    Invoke-Stage0Case 'T11' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch -BatchId 'wrong-batch'
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response))
    }
    Invoke-Stage0Case 'T12' {
        $project = New-Stage0Project; $bulk = Join-Path $project 'Bulk.de-CH.xlf'; $units = 1..95 | ForEach-Object { '<trans-unit id="bulk{0}" translate="yes"><source>Bulk {0}</source><target state="needs-translation" /><note from="Xliff Generator">Page Bulk|Field|Caption</note></trans-unit>' -f $_ }; ('<?xml version="1.0" encoding="utf-8"?><xliff version="1.2"><file source-language="en-US" target-language="de-CH"><body><group id="body">' + ($units -join '') + '</group></body></file></xliff>') | Set-Content -LiteralPath $bulk -Encoding utf8
        $first = Export-Stage0Batch -ProjectPath $project -MaxItems 40; Assert-Stage0 (@($first.Batch.items).Count -eq 40 -and $first.Batch.items[0].k -match '^1-') 'First batch did not contain 40 locally ordinalled items.'; Assert-Stage0 ($first.Manifest.items.Count -eq 40 -and $first.Result.Remaining -eq 60) 'First manifest did not contain 40 items or did not report 60 remaining.'
        foreach ($manifestItem in @($first.Manifest.items)) { Assert-Stage0 (($manifestItem.k -replace '^\d+-', '') -eq $manifestItem.srcHash.Substring(0, 3)) "Manifest key '$($manifestItem.k)' does not contain its source hash prefix." }
        foreach ($batchItem in @($first.Batch.items)) { Assert-Stage0 (@($batchItem.PSObject.Properties.Name | Where-Object { $_ -notin @('k', 's', 'c', 'd', 'm') }).Count -eq 0) "Batch item '$($batchItem.k)' contains a disallowed model property." }
        $second = Export-Stage0Batch -ProjectPath $project -MaxItems 40 -Offset 40; Assert-Stage0 (@($second.Batch.items).Count -eq 40) 'Continuation did not contain 40 items.'; Assert-Stage0 ($second.Batch.items[0].s -ne $first.Batch.items[0].s -and $second.Result.Remaining -eq 20) 'Continuation repeated the first item or did not report 20 remaining.'
    }
    Invoke-Stage0Case 'T13' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; $response.t[0].t = ''
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response))
    }
    Invoke-Stage0Case 'T14' {
        $project = New-Stage0Project; [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf'); $xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='caption']/*[local-name()='target']").InnerText = 'Kundenname'; $xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='caption']/*[local-name()='target']").SetAttribute('state', 'needs-review-translation'); $xml.Save((Join-Path $project 'Stage0.de-CH.xlf'))
        $validation = Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate' }
        Assert-Stage0 ($validation.Statistics.NeedsReview -eq 1 -and $validation.Statistics.Missing -eq 4) 'Text with needs-review-translation was not classified as needsReview.'
    }
    Invoke-Stage0Case 'T15' {
        $project = New-Stage0Project
        $rejectionMessage = $null
        try { Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate'; FailOnUnapproved = $true } } catch { $rejectionMessage = $_.Exception.Message }
        Assert-Stage0 ($rejectionMessage -match 'approval gate') 'FailOnUnapproved did not fail through the approval gate.'
    }
    Invoke-Stage0Case 'T16' {
        $project = New-Stage0Project; $export = Export-Stage0Batch -ProjectPath $project -MaxItems 2; Invoke-Stage0Apply $project $export (Write-Stage0Response $project (New-Stage0Response $export.Batch)); [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf'); $targets = @($xml.SelectNodes("//*[local-name()='target']")); $targets[0].SetAttribute('state', 'translated'); $targets[1].SetAttribute('state', 'translated'); $targets[1].InnerText = 'Gebuchte %1 von %2'; $xml.Save((Join-Path $project 'Stage0.de-CH.xlf'))
        $reportPath = Get-ChildItem -LiteralPath (Join-Path $project '.aproda\translation\.cache') -Filter 'run-*.json' | Select-Object -First 1 -ExpandProperty FullName; Invoke-Stage0Tool @{ AppPath = $project; Action = 'Report'; ReportPath = $reportPath }; $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 10
        Assert-Stage0 ($report.review.correctionRate -eq 0.5) 'Correction rate was not 0.5 after one correction out of two reviewed items.'
    }
    Invoke-Stage0Case 'T17' {
        $project = New-Stage0Project; [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf'); $targets = @($xml.SelectNodes("//*[local-name()='target']")); $targets[0].SetAttribute('state', 'needs-review-translation'); $targets[1].SetAttribute('state', 'needs-l10n'); $xml.Save((Join-Path $project 'Stage0.de-CH.xlf')); . ([scriptblock]::Create((Get-Content -LiteralPath (Join-Path $toolDirectory 'vendor\XliffSync\Model\XlfDocument.ps1') -Raw))); [XlfDocument]$document = [XlfDocument]::LoadFromPath((Join-Path $project 'Stage0.de-CH.xlf'))
        Assert-Stage0 ($document.GetState($document.FindTranslationUnit('caption')) -eq [XlfTranslationState]::NeedsReviewTranslation) 'needs-review-translation did not map to its enum member.'; Assert-Stage0 ($document.GetState($document.FindTranslationUnit('placeholders')) -eq [XlfTranslationState]::NeedsLocalization) 'needs-l10n did not map to its enum member.'
    }
    Invoke-Stage0Case 'T18' {
        $project = New-Stage0Project; [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf'); $target = $xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='caption']/*[local-name()='target']"); $target.InnerText = 'Kundenname'; $target.SetAttribute('state', 'needs-review-adaptation'); $xml.Save((Join-Path $project 'Stage0.de-CH.xlf'))
        $validation = Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate' }
        Assert-Stage0 ($validation.Statistics.NeedsReview -eq 1 -and $validation.Statistics.Missing -eq 4) 'Text with an unmapped state was not classified as needsReview.'
    }
    Invoke-Stage0Case 'T28' {
        $project = New-Stage0Project; [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf')
        foreach ($unit in $xml.SelectNodes("//*[local-name()='trans-unit']")) {
            $source = $unit.SelectSingleNode("./*[local-name()='source']").InnerText
            $target = $unit.SelectSingleNode("./*[local-name()='target']")
            $target.InnerText = $source
            if ($target.Attributes['state']) {
                [void]$target.Attributes.RemoveNamedItem('state')
            }
        }
        $xml.Save((Join-Path $project 'Stage0.de-CH.xlf'))
        $validation = Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate'; FailOnUnapproved = $true }
        Assert-Stage0 ($validation.Statistics.Missing -eq 0 -and $validation.Statistics.NeedsReview -eq 0 -and $validation.Statistics.Approved -eq 5) 'Filled targets without state were not treated as approved.'
        Assert-Stage0 ($validation.UnapprovedCount -eq 0) 'Approval gate still counted state-less filled targets as unapproved.'
    }
    Invoke-Stage0Case 'T19' {
        $project = New-Stage0Project -IncludeSecondTarget; $export = Export-Stage0Batch $project; $responsePath = Write-Stage0Response $project (New-Stage0Response $export.Batch); $before = Get-Stage0TargetHashes $project; $previousFailureAtCommit = $env:APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT; $env:APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT = '2'
        try {
            $rejectionMessage = $null
            try { Invoke-Stage0Apply $project $export $responsePath } catch { $rejectionMessage = $_.Exception.Message }
            Assert-Stage0 ($rejectionMessage -match 'Injected XLIFF commit failure at replacement 2') 'The injected second replacement failure was not reported.'
        }
        finally {
            $env:APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT = $previousFailureAtCommit
        }
        $after = Get-Stage0TargetHashes $project
        Assert-Stage0 ($before.Count -eq 2 -and $after.Count -eq 2) "The multi-file rollback fixture did not produce two target hashes: before=$($before.Count), after=$($after.Count)."
        Assert-Stage0 (($before -join '|') -eq ($after -join '|')) "A failed second commit did not restore both XLIFF files byte-for-byte: before=$($before -join '|'); after=$($after -join '|')."
    }
    Invoke-Stage0Case 'T20' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; Remove-Item -LiteralPath $export.ManifestPath
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project (New-Stage0Response $export.Batch)))
    }
    Invoke-Stage0Case 'T21' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; Set-Content -LiteralPath $export.ManifestPath -Encoding utf8 -Value '{'
        [void](Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project (New-Stage0Response $export.Batch)))
    }
    Invoke-Stage0Case 'T22' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; $response = New-Stage0Response $export.Batch; $response.v = 2
        $message = Assert-Stage0ApplyRejected $project $export (Write-Stage0Response $project $response); Assert-Stage0 ($message -match 'schema version') 'Schema-version mismatch was not rejected.'
    }
    Invoke-Stage0Case 'T23' {
        $project = New-Stage0Project; [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf'); $target = $xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='caption']/*[local-name()='target']"); $target.InnerText = 'Straße'; $target.SetAttribute('state', 'translated'); $xml.Save((Join-Path $project 'Stage0.de-CH.xlf'))
        $validation = Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate' }
        Assert-Stage0 ($validation.IssueCount -gt 0) 'Validate did not report a pre-existing ß in a translated unit.'
    }
    Invoke-Stage0Case 'T24' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project; Invoke-Stage0Apply $project $export (Write-Stage0Response $project (New-Stage0Response $export.Batch)); [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf'); foreach ($target in @($xml.SelectNodes("//*[local-name()='target']"))) { $target.SetAttribute('state', 'translated') }; $xml.Save((Join-Path $project 'Stage0.de-CH.xlf'))
        [void](Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate'; FailOnUnapproved = $true })
    }
    Invoke-Stage0Case 'T25' {
        $project = New-Stage0Project; [xml]$xml = Get-Content -LiteralPath (Join-Path $project 'Stage0.de-CH.xlf'); foreach ($unit in @($xml.SelectNodes("//*[local-name()='trans-unit']"))) { $target = $unit.SelectSingleNode("*[local-name()='target']"); $target.InnerText = $unit.SelectSingleNode("*[local-name()='source']").InnerText; $target.SetAttribute('state', 'translated') }; $captionTarget = $xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='caption']/*[local-name()='target']"); $captionTarget.InnerText = 'Straße'; $xml.Save((Join-Path $project 'Stage0.de-CH.xlf'))
        $issuesMessage = $null; try { Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate'; FailOnIssues = $true } } catch { $issuesMessage = $_.Exception.Message }; Assert-Stage0 ($issuesMessage -match 'validation found') 'FailOnIssues did not fail independently of approval.'
        [void](Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate'; FailOnUnapproved = $true })
        $captionTarget.InnerText = 'Kundenname'; $captionTarget.SetAttribute('state', 'needs-review-translation'); $xml.Save((Join-Path $project 'Stage0.de-CH.xlf'))
        [void](Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate'; FailOnIssues = $true })
        $approvalMessage = $null; try { Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate'; FailOnUnapproved = $true } } catch { $approvalMessage = $_.Exception.Message }; Assert-Stage0 ($approvalMessage -match 'approval gate') 'FailOnUnapproved did not fail independently of issues.'
    }
    Invoke-Stage0Case 'T26' {
        $toolPath = Join-Path $toolDirectory 'Invoke-AprodaBuildXliffSync.ps1'; $ast = [System.Management.Automation.Language.Parser]::ParseFile($toolPath, [ref]$null, [ref]$null); $definition = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-AprodaAlBuildArguments' }, $true))[0]
        Assert-Stage0 ($null -ne $definition) 'Get-AprodaAlBuildArguments is missing.'; . ([scriptblock]::Create($definition.Extent.Text)); $buildArguments = @(Get-AprodaAlBuildArguments -ProjectPath 'C:\App' -PackageCachePath 'C:\App\.alpackages' -OutputPath 'C:\Temp\out.app')
        Assert-Stage0 ($buildArguments -contains '/packagecachepath:C:\App\.alpackages') 'The build does not pass a package cache path; the compiler then resolves no symbols.'
        Assert-Stage0 ($buildArguments -contains '/out:C:\Temp\out.app') 'The build does not redirect its output; artifacts would land in the project.'
        Assert-Stage0 ($buildArguments -contains '/project:C:\App') 'The build does not pass the project path.'
    }
    Invoke-Stage0Case 'T27' {
        $vendorSource = Get-Content -LiteralPath (Join-Path $toolDirectory 'vendor\XliffSync\Model\XlfDocument.ps1') -Raw
        Assert-Stage0 ($vendorSource -match '\[boolean\]\s*\$useSelfClosingTags\s*=\s*\$true') 'The vendored default for useSelfClosingTags was lost; re-apply the patch after re-vendoring.'
        Assert-Stage0 ((Get-Content -LiteralPath (Join-Path $toolDirectory 'Invoke-AprodaBuildXliffSync.ps1') -Raw) -match 'Sync-XliffTranslations[^\r\n]*-useSelfClosingTags') 'Sync does not pass -useSelfClosingTags, which overrides the patched default.'
        $project = New-Stage0Project; $path = Join-Path $project 'Stage0.de-CH.xlf'
        [void](Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate' })
        $raw = Get-Content -LiteralPath $path -Raw
        Assert-Stage0 ($raw -notmatch '></target>' -and $raw -notmatch '></note>') 'Empty elements were expanded on save, which rewrites every note and buries the real change in the diff.'
        Assert-Stage0 ($raw -notmatch ' />') 'Empty elements were written as "<x />"; Business Central writes "<x/>", so every one of them shows up as a diff line.'
        $savedBytes = [System.IO.File]::ReadAllBytes($path)
        Assert-Stage0 (-not ($savedBytes.Length -ge 3 -and $savedBytes[0] -eq 0xEF -and $savedBytes[1] -eq 0xBB -and $savedBytes[2] -eq 0xBF)) 'A byte order mark was written; Business Central emits none, so the first line would differ on every run.'
    }
    Invoke-Stage0Case 'T29' {
        $project = New-Stage0Project; $export = Export-Stage0Batch $project
        $captionItem = @($export.Batch.items | Where-Object { $_.s -eq 'Customer Name' })[0]
        Assert-Stage0 ($null -ne $captionItem -and $captionItem.c -eq 'Table Customer|Field|Caption') "ExportOpen did not pass through the Xliff Generator note; got '$($captionItem.c)'. Every direct LoadFromPath call must set developerNoteDesignation/xliffGeneratorNoteDesignation via Get-AprodaXlfDocument, or note lookups silently return empty."
    }
    Invoke-Stage0Case 'T30' {
        $project = New-Stage0Project
        $warnings = Invoke-Stage0Tool @{ AppPath = $project; Action = 'Validate' } 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
        Assert-Stage0 ($warnings.Count -gt 0) 'A fresh project with missing translations produced no warnings to check.'
        Assert-Stage0 (@($warnings | Where-Object { $_.Message -match 'System\.Xml\.XmlElement' }).Count -eq 0) "Test-XliffTranslations returns raw XmlNode units for missing/need-work findings; Write-Warning must format them, not stringify them to 'System.Xml.XmlElement'."
        Assert-Stage0 (@($warnings | Where-Object { $_.Message -match "^Translation issue: unit '" }).Count -gt 0) 'Missing-translation findings from Test-XliffTranslations were not surfaced as a readable warning.'
    }
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if (@($results | Where-Object Result -eq 'FAIL').Count -gt 0) {
    exit 1
}