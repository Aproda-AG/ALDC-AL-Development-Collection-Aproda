param([Parameter(Mandatory)][string]$EnginePath, [Parameter(Mandatory)][string]$CaptureDir)
$ErrorActionPreference = 'Stop'
$mod = New-Module -Name DrvClassify -ScriptBlock ([ScriptBlock]::Create((Get-Content -LiteralPath $EnginePath -Raw)))
foreach ($file in Get-ChildItem -LiteralPath $CaptureDir -Filter '*.txt' | Where-Object Name -match '^(publish|runtests)-') {
    $raw = Get-Content -LiteralPath $file.FullName -Raw
    $exit = [int]([regex]::Match($raw, 'exit code:\s*(\d+)').Groups[1].Value)
    $body = ($raw -replace '(?m)^# exit code:.*$', '') -replace '(?m)^--- (stdout|stderr) ---$', ''
    if ($file.Name -like 'publish-*') {
        $r = & $mod { param($e, $o) Get-DeployRunVerifyPublishOutcome -ExitCode $e -Output $o } $exit $body
        '{0,-34} exit={1} -> {2}' -f $file.Name, $exit, $r.Outcome
    } else {
        $r = & $mod { param($e, $o) $t = Get-DeployRunVerifyTestOutcome -ExitCode $e -Output $o; $s = if ($t.Json -and $t.Json.succeeded -or $t.Outcome -eq 'Red') { ConvertTo-DeployRunVerifyTestSummary -Json $t.Json } else { $null }; [pscustomobject]@{ O = $t.Outcome; R = $t.Reason; S = $s } } $exit $body
        $counts = if ($r.S) { "total=$($r.S.Total) passed=$($r.S.Passed) failed=$($r.S.Failed) skipped=$($r.S.Skipped)" } else { '' }
        '{0,-34} exit={1} -> {2} {3} {4}' -f $file.Name, $exit, $r.O, $r.R, $counts
    }
}
