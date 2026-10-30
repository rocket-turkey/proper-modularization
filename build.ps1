[CmdletBinding()]
param([string[]]$Task = @('Validate'), [hashtable]$Properties = @{})
$ErrorActionPreference = 'Stop'
if (!(Get-Module -ListAvailable psake | Where-Object { $_.Version -ge [version]'5.0.4' })) {
    throw 'psake 5.0.4 or later is required. Install-Module psake -RequiredVersion 5.0.4 -Scope CurrentUser'
}
Import-Module psake -MinimumVersion 5.0.4 -ErrorAction Stop
Push-Location $PSScriptRoot
try {
    Invoke-psake -BuildFile (Join-Path $PSScriptRoot 'psakefile.ps1') -TaskList $Task -Properties $Properties -NoLogo
    if (!$psake.build_success) { throw 'psake build failed. See the task output above.' }
} finally { Pop-Location }
