$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$case = Join-Path $project ('work/metrics-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $case | Out-Null
foreach ($dir in @('processing','hiding','scripts','interventions')) { Copy-Item -LiteralPath (Join-Path $project $dir) -Destination $case -Recurse }
$baseline = Join-Path $case 'baseline.json'
& (Join-Path $case 'scripts/Save-Baseline.ps1') -OutputPath $baseline
$summary = Join-Path $project 'results/processing-summary.json'
$r = & (Join-Path $case 'scripts/Measure-Change.ps1') -BaselinePath $baseline -Design processing -Intervention journal -Minutes 0 -PublicApiChanges 0 -TestSummaryPath $summary -OutputPath (Join-Path $case 'unchanged.json')
if ($r.ChangedFiles -ne 0 -or $r.AddedLines -ne 0 -or $r.DeletedLines -ne 0) { throw 'Identity metrics failed.' }
Add-Content -LiteralPath (Join-Path $case 'processing/WriteReleaseLog.psm1') -Value '# owner change'
$engine = Join-Path $case 'processing/DeploymentEngine.psm1'
$s = [IO.File]::ReadAllText($engine).Replace("`$ErrorActionPreference = 'Stop'", "`$ErrorActionPreference = 'Stop' # outside change")
[IO.File]::WriteAllText($engine, $s)
Set-Content -LiteralPath (Join-Path $case 'processing/NewModule.psm1') -Value '# new module'
$deletePath = [IO.Path]::GetFullPath((Join-Path $case 'processing/ValidateRelease.psm1'))
if (!$deletePath.StartsWith($case + [IO.Path]::DirectorySeparatorChar)) { throw 'Bad test path.' }
Remove-Item -LiteralPath $deletePath
$r = & (Join-Path $case 'scripts/Measure-Change.ps1') -BaselinePath $baseline -Design processing -Intervention journal -Minutes 7 -PublicApiChanges 0 -TestSummaryPath $summary -OutputPath (Join-Path $case 'changed.json')
if ($r.ChangedFiles -ne 4 -or $r.ChangedModules -ne 4 -or $r.ModulesOutsideOwner -ne 3 -or $r.ChangePropagation -ne 0.75 -or $r.AddedLines -ne 3 -or $r.DeletedLines -le 1) { throw "Change metrics failed: $($r | ConvertTo-Json -Depth 8)" }
[ordered]@{
    Purpose = 'Metrics tooling verification only; these are not experiment intervention outcomes.'
    IdentityDiffPassed = $true; AddedModifiedDeletedDiffPassed = $true
    ExpectedChangedModules = 4; ExpectedOutsideOwner = 3; ExpectedCP = 0.75; ActualCP = $r.ChangePropagation
    RecordedUtc = [datetime]::UtcNow.ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $project 'results/metrics-validation.json') -Encoding UTF8
