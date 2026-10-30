[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('processing','hiding')][string]$Design, [string]$OutputPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root "$Design/DeploymentEngine.psd1") -Force
$case = Join-Path $root ('work/smoke/' + [guid]::NewGuid().ToString('N'))
$fx = Join-Path $case 'fixtures'; $dest = Join-Path $case 'destination'
& (Join-Path $PSScriptRoot 'New-Fixtures.ps1') -Path $fx | Out-Null
$checks = 0
function Assert($Condition, $Message) { if (!$Condition) { throw $Message }; $script:checks++ }
function Assert-Rejected([scriptblock]$Action) {
    $caught = $false
    try { & $Action | Out-Null } catch { $caught = $true }
    Assert $caught 'Expected a terminating rejection.'
}
Assert ((Get-ReleaseStatus $dest).Status -eq 'Empty') 'Expected empty status.'
$m1 = Join-Path $fx 'v1/release.json'; $m2 = Join-Path $fx 'v2/release.json'
Assert (Test-Release $m1).Valid 'Valid fixture rejected.'
Install-Release $m1 $dest | Out-Null
Install-Release $m2 $dest | Out-Null
Assert ((Get-ReleaseStatus $dest).ReleaseId -eq 'release-2') 'Install status wrong.'
Assert-Rejected { Install-Release $m2 $dest }
Undo-Release $dest | Out-Null
Assert ((Get-ReleaseStatus $dest).ReleaseId -eq 'release-1') 'Rollback status wrong.'
Assert ((Get-FileHash (Join-Path $dest 'active/app.txt')).Hash -eq (Get-FileHash (Join-Path $fx 'v1/payload/app.txt')).Hash) 'Rollback bytes wrong.'
Assert (@(Get-ReleaseHistory $dest).Count -eq 3) 'History wrong.'
Assert-Rejected { Undo-Release $dest }
Set-Content (Join-Path $fx 'v1/payload/app.txt') 'tampered'
Assert-Rejected { Test-Release $m1 }
Assert-Rejected { Install-Release $m1 (Join-Path $case 'invalid') }
Assert (!(Test-Path (Join-Path $case 'invalid'))) 'Rejected install wrote state.'
$result = [pscustomobject]@{ Design = $Design; PowerShell = $PSVersionTable.PSVersion.ToString(); Checks = $checks; Passed = $true; RecordedUtc = [datetime]::UtcNow.ToString('o') }
if ($OutputPath) { $result | ConvertTo-Json | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
$result
