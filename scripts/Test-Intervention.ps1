[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('processing','hiding')][string]$Design,
    [Parameter(Mandatory)][ValidateSet('journal','layout','schema','policy')][string]$Intervention
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root "$Design/DeploymentEngine.psd1") -Force
$case = Join-Path $root ('work/interventions/' + [guid]::NewGuid().ToString('N'))
$fx = Join-Path $case 'fixtures'; $dest = Join-Path $case 'destination'
& (Join-Path $PSScriptRoot 'New-Fixtures.ps1') -Path $fx | Out-Null
function Assert($Condition, $Message) { if (!$Condition) { throw $Message } }
function Write-Json($Path, $Value) { $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Assert-Rejected([scriptblock]$Action) {
    $caught = $false
    try { & $Action | Out-Null } catch { $caught = $true }
    Assert $caught 'Expected policy rejection.'
}
if ($Intervention -eq 'schema') {
    $path = Join-Path $fx 'v1/release.json'
    $m = Get-Content $path -Raw | ConvertFrom-Json
    $v2 = [ordered]@{ schemaVersion = 2; releaseId = $m.releaseId; application = $m.application; metadata = $m.metadata; components = @(@{ name = 'app'; files = @($m.artifacts[0]) }, @{ name = 'config'; files = @($m.artifacts[1]) }) }
    Write-Json $path $v2
    Assert (Test-Release $path).Valid 'Schema v2 must validate.'
    Install-Release $path $dest | Out-Null
    Assert ((Get-Content (Join-Path $dest 'active/app.txt') -Raw) -match 'version 1') 'Schema v2 payload missing.'
    $v2.components[1].files[0].target = 'APP.TXT'; Write-Json $path $v2
    $caught = $false; try { Test-Release $path | Out-Null } catch { $caught = $true }
    Assert $caught 'Duplicate targets across components must fail.'
} elseif ($Intervention -eq 'policy') {
    $path = Join-Path $fx 'v1/release.json'
    $m = Get-Content $path -Raw | ConvertFrom-Json
    $m.metadata = [pscustomobject]@{ environment = 'production'; approvedBy = ''; approvalTicket = '' }
    Write-Json $path $m
    Assert-Rejected { Test-Release $path }
    Assert-Rejected { Install-Release $path $dest }
    Assert (!(Test-Path $dest)) 'Policy rejection must not write.'
    $m.metadata.approvedBy = 'reviewer'; $m.metadata.approvalTicket = 'CHG-42'; Write-Json $path $m
    Assert (Test-Release $path).Valid 'Approved production manifest must validate.'
    Install-Release $path $dest | Out-Null
    $m.artifacts[0].sha256 = '0' * 64; Write-Json $path $m
    Assert-Rejected { Test-Release $path }
} else {
    Install-Release (Join-Path $fx 'v1/release.json') $dest | Out-Null
    Install-Release (Join-Path $fx 'v2/release.json') $dest | Out-Null
    Undo-Release $dest | Out-Null
    Assert ((Get-ReleaseStatus $dest).ReleaseId -eq 'release-1') 'Rollback status wrong.'
    Assert (@(Get-ReleaseHistory $dest).Count -eq 3) 'History count wrong.'
    Assert ((Get-FileHash (Join-Path $dest 'active/app.txt')).Hash -eq (Get-FileHash (Join-Path $fx 'v1/payload/app.txt')).Hash) 'Rollback bytes wrong.'
    if ($Intervention -eq 'journal') {
        Assert (!(Test-Path (Join-Path $dest 'journal.csv'))) 'CSV must not be used by fresh workspaces.'
        $jsonl = Join-Path $dest 'journal.jsonl'
        Assert (Test-Path $jsonl) 'JSON Lines journal missing.'
        $rows = @(Get-Content $jsonl | ForEach-Object { $_ | ConvertFrom-Json -ErrorAction Stop })
        Assert ($rows.Count -eq 3) 'Expected one JSON object per event line.'
    } else {
        Assert (!(Test-Path (Join-Path $dest 'releases'))) 'Old release directory layout must be removed.'
        $index = Get-Content (Join-Path $dest 'release-index/release-1.json') -Raw | ConvertFrom-Json
        foreach ($entry in $index.files) {
            $blob = Join-Path $dest ('blobs/' + $entry.sha256.ToLowerInvariant())
            Assert (Test-Path $blob -PathType Leaf) 'Content addressed blob missing.'
            Assert ((Get-FileHash $blob -Algorithm SHA256).Hash -eq $entry.sha256) 'Blob hash mismatch.'
        }
        Assert (@($index.files).Count -eq 2) 'Release index must contain both paths.'
    }
}
Write-Host "PASS: $Design / $Intervention acceptance checks"
