[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselinePath,
    [Parameter(Mandatory)][ValidateSet('processing','hiding')][string]$Design,
    [Parameter(Mandatory)][ValidateSet('journal','layout','schema','policy')][string]$Intervention,
    [Parameter(Mandatory)][double]$Minutes,
    [Parameter(Mandatory)][int]$PublicApiChanges,
    [Parameter(Mandatory)][string]$TestSummaryPath,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
if ($Minutes -lt 0 -or $PublicApiChanges -lt 0) { throw 'Metrics must be nonnegative.' }
$root = Split-Path $PSScriptRoot -Parent
$boundaries = Get-Content (Join-Path $root 'interventions/boundaries.json') -Raw | ConvertFrom-Json
$owner = $boundaries.$Intervention.$Design
$baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
if ($baseline.Version -ne 1) { throw 'Unsupported snapshot version.' }
$before = @{}
foreach ($f in $baseline.Files | Where-Object { $_.Path.StartsWith($Design + '/') }) { $before[$f.Path] = $f.Text }
if ($before.Count -eq 0) { throw 'No baseline files for selected design.' }
$after = @{}
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $root $Design) -Recurse -File) {
    $after[$f.FullName.Substring($root.Length + 1).Replace('\','/')] = [IO.File]::ReadAllText($f.FullName).Replace("`r`n","`n")
}
function Get-Lines([string]$Text) {
    if ($Text.Length -eq 0) { return }
    $lines = $Text -split "`n"
    if ($lines[-1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    $lines
}
function Get-LineDelta([string]$Old, [string]$New) {
    # Longest common subsequence: minimal added/deleted lines, independent of Git and whitespace heuristics.
    $a = @(Get-Lines $Old); $b = @(Get-Lines $New)
    $row = New-Object 'int[]' ($b.Count + 1)
    foreach ($line in $a) {
        $next = New-Object 'int[]' ($b.Count + 1)
        for ($j = 1; $j -le $b.Count; $j++) {
            if ($line -ceq $b[$j - 1]) { $next[$j] = $row[$j - 1] + 1 }
            else { $next[$j] = [math]::Max($row[$j], $next[$j - 1]) }
        }
        $row = $next
    }
    [pscustomobject]@{ Added = $b.Count - $row[$b.Count]; Deleted = $a.Count - $row[$b.Count] }
}
$changes = @()
foreach ($path in @(@($before.Keys) + @($after.Keys) | Sort-Object -Unique)) {
    if (!$before.ContainsKey($path) -or !$after.ContainsKey($path) -or $before[$path] -cne $after[$path]) {
        $delta = Get-LineDelta ([string]$before[$path]) ([string]$after[$path])
        $changes += [pscustomobject]@{ Path = $path; Added = $delta.Added; Deleted = $delta.Deleted }
    }
}
$baselineModules = @($before.Keys | Where-Object { $_ -like '*.psm1' })
$modifiedModules = @($changes | Where-Object Path -like '*.psm1')
$outside = @($modifiedModules | Where-Object Path -ne $owner)
$tests = Get-Content -LiteralPath $TestSummaryPath -Raw | ConvertFrom-Json
if ($tests.Design -ne $Design -or $tests.Total -le 0) { throw 'Invalid test summary for selected design.' }
$added = ($changes | Measure-Object Added -Sum).Sum
$deleted = ($changes | Measure-Object Deleted -Sum).Sum
$denominator = @($baselineModules | Where-Object { $_ -ne $owner }).Count
if ($denominator -eq 0) { throw 'No modules outside owner.' }
$result = [ordered]@{
    Design = $Design; Intervention = $Intervention; Owner = $owner
    ChangedFiles = $changes.Count; ChangedModules = $modifiedModules.Count
    ModulesOutsideOwner = $outside.Count; OtherBaselineModules = $denominator
    ChangePropagation = $outside.Count / [double]$denominator
    AddedLines = [int]$added; DeletedLines = [int]$deleted
    BaselineLines = [int](($before.Values | ForEach-Object { @(Get-Lines $_).Count } | Measure-Object -Sum).Sum)
    Minutes = $Minutes; PublicApiChanges = $PublicApiChanges
    PassedTests = $tests.Passed; FailedTests = $tests.Failed; SkippedTests = $tests.Skipped
    TestSummaryUtc = $tests.RecordedUtc; MeasuredUtc = [datetime]::UtcNow.ToString('o')
    Changes = $changes
}
$out = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Path (Split-Path $out -Parent) -Force | Out-Null
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $out -Encoding UTF8
[pscustomobject]$result
