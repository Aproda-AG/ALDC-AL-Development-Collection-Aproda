[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testDirectory = if ($PSCommandPath) { Split-Path -Path $PSCommandPath -Parent } else { $env:APRODA_XLIFFSYNC_TESTDIR }
if (-not $testDirectory) {
    throw 'Cannot locate the Stage 1 test directory. Set APRODA_XLIFFSYNC_TESTDIR when content-loading the test script.'
}
$toolDirectory = Split-Path -Path $testDirectory -Parent
$fixtureDirectory = Join-Path $testDirectory 'fixtures'
$toolPath = Join-Path $toolDirectory 'Invoke-AprodaBuildXliffSync.ps1'
$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) "aproda-xliff-stage1-$([guid]::NewGuid())"
$results = @()

function Assert-Stage1 {
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

function Invoke-Stage1Tool {
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

function New-Stage1Project {
    $projectPath = Join-Path $workRoot ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $projectPath 'app.json') -Encoding utf8 -Value '{}'
    Copy-Item -LiteralPath (Join-Path $fixtureDirectory 'Stage1.g.xlf') -Destination (Join-Path $projectPath 'Stage1.g.xlf')
    Copy-Item -LiteralPath (Join-Path $fixtureDirectory 'Stage1.de-CH.xlf') -Destination (Join-Path $projectPath 'Stage1.de-CH.xlf')
    return $projectPath
}

function New-Stage1FaultProject {
    $projectPath = Join-Path $workRoot ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $projectPath 'app.json') -Encoding utf8 -Value '{}'
        $firstContent = @"
<?xml version="1.0" encoding="utf-8"?>
<xliff version="1.2">
  <file source-language="en-US" target-language="de-CH" datatype="x-al" original="Stage1Fault">
    <body>
      <group id="body">
                <trans-unit id="inv-open" translate="yes"><source>42</source><target state="needs-translation" /><note from="Xliff Generator">Table Number Test - Field Amount - Property Caption</note></trans-unit>
      </group>
    </body>
  </file>
</xliff>
"@
        $secondContent = @"
<?xml version="1.0" encoding="utf-8"?>
<xliff version="1.2">
    <file source-language="en-US" target-language="de-CH" datatype="x-al" original="Stage1FaultSecond">
        <body>
            <group id="body">
                <trans-unit id="mem-a1" translate="yes"><source>Post the document</source><target state="translated">Buchen Sie das Dokument</target><note from="Xliff Generator">TableExtension Sales Ext - Field DocStatus - Property Caption</note></trans-unit>
                <trans-unit id="mem-a2" translate="yes"><source>Post the document</source><target state="translated">Buchen Sie das Dokument</target><note from="Xliff Generator">TableExtension Sales Ext - Field DocStatus - Property Caption</note></trans-unit>
                <trans-unit id="mem-open" translate="yes"><source>Post the document</source><target state="needs-translation" /><note from="Xliff Generator">TableExtension Sales Ext - Field DocStatus - Property Caption</note></trans-unit>
            </group>
        </body>
    </file>
</xliff>
"@
        Set-Content -LiteralPath (Join-Path $projectPath 'Stage1Fault.de-CH.xlf') -Encoding utf8 -Value $firstContent
        Set-Content -LiteralPath (Join-Path $projectPath 'Stage1FaultSecond.de-CH.xlf') -Encoding utf8 -Value $secondContent
    return $projectPath
}

function New-Stage1NoteDocument {
    param([AllowNull()] [string]$Note)

    $notePath = Join-Path $workRoot ('note-{0}.xlf' -f [guid]::NewGuid())
    $noteElement = if ($Note) { "<note from=""Xliff Generator"">$Note</note>" } else { '' }
    $content = @"
<?xml version="1.0" encoding="utf-8"?>
<xliff version="1.2">
  <file source-language="en-US" target-language="de-CH" datatype="x-al" original="Stage1Note">
    <body>
      <group id="body">
        <trans-unit id="u1" translate="yes"><source>Sample</source><target state="needs-translation" />$noteElement</trans-unit>
      </group>
    </body>
  </file>
</xliff>
"@
    Set-Content -LiteralPath $notePath -Encoding utf8 -Value $content
    return $notePath
}

function Import-Stage1ContextClassFunctions {
    # AST-extracted, not forked: the exact function bodies from the tool script, same convention as
    # Stage0's T26/T27 (dot-sourcing a single function's extent), needed here because Invoke-Stage1Tool
    # only defines functions in its own local scope, not the caller's.
    . ([scriptblock]::Create((Get-Content -LiteralPath (Join-Path $toolDirectory 'vendor\XliffSync\Model\XlfDocument.ps1') -Raw)))
    $toolSource = Get-Content -LiteralPath $toolPath -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($toolSource, [ref]$null, [ref]$null)
    foreach ($functionName in @('Get-AprodaXlfDocument', 'Get-AprodaNormalisedObjectType', 'Get-AprodaContextClass')) {
        $definition = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $functionName }, $true))[0]
        Assert-Stage1 ($null -ne $definition) "Function '$functionName' is missing from the tool script."
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}

function Get-Stage1TargetHashes {
    param([string]$ProjectPath)

    return @(Get-ChildItem -LiteralPath $ProjectPath -File -Filter '*.de-CH.xlf' |
        Sort-Object Name |
        ForEach-Object { '{0}:{1}' -f $_.Name, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
}

function Get-Stage1UnitTarget {
    param([string]$ProjectPath, [string]$FileName, [string]$UnitId)

    [xml]$xml = Get-Content -LiteralPath (Join-Path $ProjectPath $FileName)
    return $xml.SelectSingleNode("//*[local-name()='trans-unit' and @id='$UnitId']/*[local-name()='target']")
}

function Invoke-Stage1Case {
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
. Import-Stage1ContextClassFunctions
try {
    Invoke-Stage1Case 'T1' {
        $project = New-Stage1Project
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' }
        foreach ($case in @(
                @{ Id = 'inv1'; Expected = '123-45' },
                @{ Id = 'inv2'; Expected = '%1' },
                # The spec's "PDF" example was replaced because it contains Unicode letters and cannot satisfy the \p{L}-based invariant test.
                @{ Id = 'inv3'; Expected = '42' }
            )) {
            $target = Get-Stage1UnitTarget -ProjectPath $project -FileName 'Stage1.de-CH.xlf' -UnitId $case.Id
            Assert-Stage1 ($target.InnerText -eq $case.Expected) "Invariant unit '$($case.Id)' target was '$($target.InnerText)', expected '$($case.Expected)'."
            Assert-Stage1 ($target.GetAttribute('state') -eq 'translated') "Invariant unit '$($case.Id)' state was '$($target.GetAttribute('state'))', expected 'translated'."
        }
    }
    Invoke-Stage1Case 'T2' {
        $project = New-Stage1Project
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' }
        $target = Get-Stage1UnitTarget -ProjectPath $project -FileName 'Stage1.de-CH.xlf' -UnitId 'mixed1'
        Assert-Stage1 ([string]::IsNullOrEmpty($target.InnerText)) 'A source with letters and symbols mixed was incorrectly resolved by tier 1.'
        Assert-Stage1 ($target.GetAttribute('state') -eq 'needs-translation') 'A source with letters and symbols mixed did not stay open.'
    }
    Invoke-Stage1Case 'T3' {
        $project = New-Stage1Project
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' }
        $target = Get-Stage1UnitTarget -ProjectPath $project -FileName 'Stage1.de-CH.xlf' -UnitId 'mem-open'
        Assert-Stage1 ($target.InnerText -eq 'Buchen Sie das Dokument') "Memory-tier unit was not resolved to the single consistent approved target; got '$($target.InnerText)'."
        Assert-Stage1 ($target.GetAttribute('state') -eq 'translated') 'Memory-tier resolved unit was not marked translated.'
    }
    Invoke-Stage1Case 'T4' {
        $project = New-Stage1Project
        $reportPath = Join-Path $project 'resolve-report.json'
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve'; ReportPath = $reportPath }
        $target = Get-Stage1UnitTarget -ProjectPath $project -FileName 'Stage1.de-CH.xlf' -UnitId 'amb-open'
        Assert-Stage1 ([string]::IsNullOrEmpty($target.InnerText)) 'An ambiguous memory match was incorrectly auto-resolved.'
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 12
        $entry = @($report.ambiguous | Where-Object { $_.unitId -eq 'amb-open' })[0]
        Assert-Stage1 ($null -ne $entry -and $entry.candidateCount -eq 2) "'amb-open' was not recorded in ambiguous[] with candidateCount 2."
    }
    Invoke-Stage1Case 'T5' {
        $project = New-Stage1Project
        $reportPath = Join-Path $project 'resolve-report.json'
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve'; ReportPath = $reportPath }
        $target = Get-Stage1UnitTarget -ProjectPath $project -FileName 'Stage1.de-CH.xlf' -UnitId 'mw-open'
        Assert-Stage1 ([string]::IsNullOrEmpty($target.InnerText)) 'A candidate exceeding maxwidth was incorrectly resolved.'
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 12
        Assert-Stage1 (@($report.ambiguous | Where-Object { $_.unitId -eq 'mw-open' }).Count -eq 0) 'A single candidate failing maxwidth was incorrectly reported as ambiguous.'
    }
    Invoke-Stage1Case 'T6' {
        $project = New-Stage1Project
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' }
        $target = Get-Stage1UnitTarget -ProjectPath $project -FileName 'Stage1.de-CH.xlf' -UnitId 'ctx-open'
        Assert-Stage1 ([string]::IsNullOrEmpty($target.InnerText)) 'Tier 2 cross-matched across different context classes.'
    }
    Invoke-Stage1Case 'T7' {
        $project = New-Stage1Project
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' }
        $target = Get-Stage1UnitTarget -ProjectPath $project -FileName 'Stage1.de-CH.xlf' -UnitId 'ph-open'
        Assert-Stage1 ([string]::IsNullOrEmpty($target.InnerText)) 'Tier 2 matched across differing placeholder signatures.'
    }
    Invoke-Stage1Case 'T8' {
        $project = New-Stage1Project
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' }
        $target = Get-Stage1UnitTarget -ProjectPath $project -FileName 'Stage1.de-CH.xlf' -UnitId 'noparse-open'
        Assert-Stage1 ([string]::IsNullOrEmpty($target.InnerText)) 'A unit with an unparseable Xliff Generator note was incorrectly resolved.'
        Assert-Stage1 ($target.GetAttribute('state') -eq 'needs-translation') 'A unit with an unparseable Xliff Generator note did not remain available to ExportOpen.'
    }
    Invoke-Stage1Case 'T9' {
        $project = New-Stage1Project
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' }
        $afterFirst = Get-Stage1TargetHashes -ProjectPath $project
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' }
        $afterSecond = Get-Stage1TargetHashes -ProjectPath $project
        Assert-Stage1 (($afterFirst -join '|') -eq ($afterSecond -join '|')) 'A second consecutive Resolve run was not a no-op.'
    }
    Invoke-Stage1Case 'T10' {
        $project = New-Stage1FaultProject
        $before = Get-Stage1TargetHashes -ProjectPath $project
        $previousFailureAtCommit = $env:APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT
        $env:APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT = '2'
        $failureMessage = $null
        try {
            try { Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve' } } catch { $failureMessage = $_.Exception.Message }
        }
        finally {
            $env:APRODA_XLIFFSYNC_TEST_FAIL_COMMIT_AT = $previousFailureAtCommit
        }
        Assert-Stage1 ($failureMessage -match 'Injected XLIFF commit failure at replacement 2') 'The injected multi-file commit failure was not reported.'
        $after = Get-Stage1TargetHashes -ProjectPath $project
        Assert-Stage1 ($before.Count -eq 2 -and $after.Count -eq 2) "Fault-injection fixture did not produce two target hashes: before=$($before.Count), after=$($after.Count)."
        Assert-Stage1 (($before -join '|') -eq ($after -join '|')) "A failed multi-file commit during Resolve did not restore both XLIFF files byte-for-byte: before=$($before -join '|'); after=$($after -join '|')."
    }
    Invoke-Stage1Case 'T11' {
        $project = New-Stage1Project
        $reportPath = Join-Path $project 'resolve-report.json'
        Invoke-Stage1Tool @{ AppPath = $project; Action = 'Resolve'; ReportPath = $reportPath }
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -Depth 12
        Assert-Stage1 ($report.totals.translatable -eq 18) "totals.translatable was $($report.totals.translatable), expected 18."
        Assert-Stage1 ($report.totals.invariant -eq 3) "totals.invariant was $($report.totals.invariant), expected 3."
        Assert-Stage1 ($report.totals.memoryExact -eq 1) "totals.memoryExact was $($report.totals.memoryExact), expected 1."
        Assert-Stage1 ($report.totals.open -eq 6) "totals.open was $($report.totals.open), expected 6."
        Assert-Stage1 (@($report.ambiguous).Count -eq 1) "ambiguous[] had $(@($report.ambiguous).Count) entries, expected 1."
    }
    Invoke-Stage1Case 'T12' {
        $cases = @(
            @{ Note = 'TableExtension Item Translation Test - Field Region Responsible - Property Caption'; Expected = 'Table|Field|Caption' },
            @{ Note = 'PageExtension Item Card Transl. Test - Action ReleaseAction - Property ToolTip'; Expected = 'Page|Action|ToolTip' },
            @{ Note = 'Codeunit Translation Test Mgt - NamedType CustomerNotFoundAltErr'; Expected = 'Codeunit|NamedType|Label' },
            @{ Note = 'Report Item List Test - Label TotalCaption - Property Caption'; Expected = 'Report|Label|Caption' }
        )
        foreach ($case in $cases) {
            $path = New-Stage1NoteDocument -Note $case.Note
            $document = Get-AprodaXlfDocument -Path $path
            $unit = $document.FindTranslationUnit('u1')
            $actual = Get-AprodaContextClass -Document $document -Unit $unit
            Assert-Stage1 ($actual -eq $case.Expected) "Context class for note '$($case.Note)' was '$actual', expected '$($case.Expected)'."
        }
    }
    Invoke-Stage1Case 'T13' {
        foreach ($note in @($null, '', 'JustOneSegment', 'Foo - Bar', 'Foo - Bar - Baz - Qux', 'Table Foo - Field Bar - NotProperty Caption')) {
            $path = New-Stage1NoteDocument -Note $note
            $document = Get-AprodaXlfDocument -Path $path
            $unit = $document.FindTranslationUnit('u1')
            $actual = Get-AprodaContextClass -Document $document -Unit $unit
            Assert-Stage1 ($null -eq $actual) "Context class for note '$note' should be `$null but was '$actual'."
        }
    }
    Invoke-Stage1Case 'T14' {
        # Base vs. extension is a compilation technicality, not a translation difference: any
        # "...Extension" object type must normalise to its base type, generically (not a
        # hardcoded Table/Page pair) - a Field/Action/NamedType distinction must still stay separate.
        $cases = @(
            @{ Note = 'Table Item - Field Description - Property Caption'; Expected = 'Table|Field|Caption' },
            @{ Note = 'TableExtension Item Translation Test - Field Second Description - Property Caption'; Expected = 'Table|Field|Caption' },
            @{ Note = 'ReportExtension Sales Invoice Ext - Label FooterTxt - Property Caption'; Expected = 'Report|Label|Caption' },
            @{ Note = 'EnumExtension Item Type Ext - EnumValue Service - Property Caption'; Expected = 'Enum|EnumValue|Caption' },
            @{ Note = 'PermissionSetExtension Base Ext - NamedType Foo'; Expected = 'PermissionSet|NamedType|Label' }
        )
        foreach ($case in $cases) {
            $path = New-Stage1NoteDocument -Note $case.Note
            $document = Get-AprodaXlfDocument -Path $path
            $unit = $document.FindTranslationUnit('u1')
            $actual = Get-AprodaContextClass -Document $document -Unit $unit
            Assert-Stage1 ($actual -eq $case.Expected) "Context class for note '$($case.Note)' was '$actual', expected '$($case.Expected)'."
        }
        Assert-Stage1 ($cases[0].Expected -eq $cases[1].Expected) 'Table and TableExtension must normalise to the identical context class so tier 2 can match across them.'
    }
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if (@($results | Where-Object Result -eq 'FAIL').Count -gt 0) {
    exit 1
}
