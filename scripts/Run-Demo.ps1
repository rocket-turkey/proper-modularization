[CmdletBinding()]
param([ValidateSet('processing','hiding')][string]$Design = 'hiding', [string]$Destination)
$ErrorActionPreference = 'Stop'
if (!$Destination) { $Destination = Join-Path $PSScriptRoot '../work/demo' }
Import-Module (Join-Path $PSScriptRoot "../$Design/DeploymentEngine.psd1") -Force
$fixtures = Join-Path $PSScriptRoot '../fixtures'
Test-Release (Join-Path $fixtures 'v1/release.json')
Install-Release (Join-Path $fixtures 'v1/release.json') $Destination
Install-Release (Join-Path $fixtures 'v2/release.json') $Destination
Get-ReleaseStatus $Destination
Undo-Release $Destination
Get-ReleaseHistory $Destination | Format-Table
