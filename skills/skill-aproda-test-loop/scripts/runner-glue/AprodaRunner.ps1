<#
.SYNOPSIS
  AprodaRunner — thin wrapper exposing `Run-AlTests` over Microsoft's canonical
  PsTestFunctions.ps1 (`New-ClientContext` + `Run-Tests`).

.DESCRIPTION
  This is the Aproda-authored glue that replaces the former hand-cleaned
  `Runner.cleaned.txt`. It is intentionally tiny and version-agnostic: all the
  heavy lifting lives in the unmodified Microsoft files next to it
  (`ClientContext.ps1`, `PsTestFunctions.ps1`).

  Load order (done by the engine's run bootstrap):
    1. . PsTestFunctions.ps1 -clientDllPath <X> -newtonSoftDllPath <X> -clientContextScriptPath <ClientContext.ps1>
       (PsTestFunctions Add-Type's the 4 client DLLs and dot-sources ClientContext.ps1)
    2. . AprodaRunner.ps1            (defines Run-AlTests)
    3. Run-AlTests -ServiceUrl ... -ExtensionId ... -TestCodeunitsRange ... -ResultsFilePath ...

  Mirrors the exact call shape proven by the AL Test Runner's Invoke-RunTestsViaUrl
  (testPage 130455, testRunnerCodeunitId 130450, culture '' , connectFromHost).
.NOTES
  Aproda ALDC — skill-aproda-test-loop. Version-agnostic; ships centrally with the skill.
#>

function Run-AlTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]  $ServiceUrl,
        [string]  $AutorizationType = 'Windows',     # Windows | NavUserPassword | AAD
        [pscredential] $Credential,
        [string]  $ExtensionId = '',
        [string]  $TestCodeunitsRange = '',           # e.g. "59000..59003" (empty = all in extension)
        [string]  $TestSuite = 'DEFAULT',
        [int]     $TestRunnerCodeunitId = 130450,
        [int]     $TestPage = 130455,
        [bool]    $SaveResultFile = $true,
        [Parameter(Mandatory = $true)][string]  $ResultsFilePath,
        [bool]    $Detailed = $true
    )

    $auth = if ($AutorizationType -eq 'UserPassword') { 'NavUserPassword' } else { $AutorizationType }

    $clientContext = $null
    try {
        $clientContext = New-ClientContext `
            -serviceUrl $ServiceUrl `
            -auth $auth `
            -credential $Credential `
            -interactionTimeout ([timespan]::FromHours(24)) `
            -culture '' `
            -timezone ''

        Run-Tests `
            -clientContext $clientContext `
            -testPage $TestPage `
            -testSuite $TestSuite `
            -testCodeunit '*' `
            -testCodeunitRange $TestCodeunitsRange `
            -testFunction '*' `
            -testGroup '*' `
            -extensionId $ExtensionId `
            -testRunnerCodeunitId $TestRunnerCodeunitId `
            -XUnitResultFileName $ResultsFilePath `
            -AppendToXUnitResultFile:$false `
            -AzureDevOps 'no' `
            -GitHubActions 'no' `
            -detailed:$Detailed `
            -connectFromHost:$true `
            -CodeCoverageTrackingType 'Disabled' `
            -ProduceCodeCoverageMap 'Disabled' | Out-Null
    }
    finally {
        if ($clientContext) { Remove-ClientContext -clientContext $clientContext }
    }
}
