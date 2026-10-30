[CmdletBinding()]
param([ValidateSet('all','processing','hiding')][string]$Design = 'all', [string]$ResultsDirectory)
$ErrorActionPreference = 'Stop'
if (!$ResultsDirectory) { $ResultsDirectory = Join-Path $PSScriptRoot '../results' }
$ResultsDirectory = [IO.Path]::GetFullPath($ResultsDirectory)
New-Item -ItemType Directory -Path $ResultsDirectory -Force | Out-Null
if ($Design -eq 'all') {
    $failed = $false
    foreach ($d in @('processing','hiding')) {
        & (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath -Design $d -ResultsDirectory $ResultsDirectory
        if ($LASTEXITCODE -ne 0) { $failed = $true }
    }
    if ($failed) { exit 1 }
    exit 0
}
# Use the classic Pester API consistently, including Windows' bundled Pester 3.4.
$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'3.4' -and $_.Version.Major -lt 5 } | Sort-Object Version -Descending | Select-Object -First 1
if (!$pester) { throw 'Pester 3.4 or 4.x is required. Install-Module Pester -RequiredVersion 4.10.1 -Scope CurrentUser' }
if ($pester.Version.Major -eq 3 -and $PSVersionTable.PSVersion.Major -ge 6) {
    $windowsPS = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    if (!(Test-Path -LiteralPath $windowsPS)) { throw 'Pester 3 requires Windows PowerShell 5.1. Use Pester 4.10.1 for PowerShell 7.' }
    Write-Host 'Using Windows PowerShell 5.1 for the installed Pester 3.4 test framework.'
    & $windowsPS -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Design $Design -ResultsDirectory $ResultsDirectory
    exit $LASTEXITCODE
}
Import-Module $pester.Path -Force
$env:DEPLOYMENT_EXPERIMENT_DESIGN = $Design
$result = Invoke-Pester -Script (Join-Path $PSScriptRoot '../tests/Contract.Tests.ps1') -PassThru
# Write portable JUnit XML without Pester 3's optional CIM environment probe.
$xml = [xml]'<testsuite/>'
$xml.DocumentElement.SetAttribute('name', $Design)
$xml.DocumentElement.SetAttribute('tests', [string]$result.TotalCount)
$xml.DocumentElement.SetAttribute('failures', [string]$result.FailedCount)
foreach ($t in $result.TestResult) {
    $test = $xml.CreateElement('testcase')
    $test.SetAttribute('name', [string]$t.Name)
    $test.SetAttribute('time', [string]$t.Time.TotalSeconds)
    if ($t.Result -eq 'Failed') { $failure = $xml.CreateElement('failure'); $failure.InnerText = [string]$t.FailureMessage; $null = $test.AppendChild($failure) }
    if ($t.Result -in @('Skipped','Pending','Inconclusive')) { $null = $test.AppendChild($xml.CreateElement('skipped')) }
    $null = $xml.DocumentElement.AppendChild($test)
}
$xml.Save((Join-Path $ResultsDirectory "$Design.xml"))
[pscustomobject]@{
    Design = $Design; PowerShell = $PSVersionTable.PSVersion.ToString(); Pester = $pester.Version.ToString()
    Passed = $result.PassedCount; Failed = $result.FailedCount; Skipped = $result.SkippedCount
    Total = $result.TotalCount; DurationSeconds = $result.Time.TotalSeconds
    RecordedUtc = [datetime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ResultsDirectory "$Design-summary.json") -Encoding UTF8
if ($result.TotalCount -eq 0 -or $result.FailedCount -gt 0) { exit 1 }
exit 0
