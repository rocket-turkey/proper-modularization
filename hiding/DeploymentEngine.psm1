$ErrorActionPreference = 'Stop'
function Get-WorkspacePath {
    param([string]$Destination)
    if ([string]::IsNullOrWhiteSpace($Destination)) { throw 'Destination is required.' }
    $full = [IO.Path]::GetFullPath($Destination)
    $volume = [IO.Path]::GetPathRoot($full)
    if ($full.TrimEnd('\', '/') -eq $volume.TrimEnd('\', '/')) { throw 'A filesystem root cannot be a destination.' }
    return $full.TrimEnd('\', '/')
}
function Assert-Workspace {
    param([string]$Root)
    if (Test-Path -LiteralPath $Root) {
        if (!(Test-Path -LiteralPath $Root -PathType Container)) { throw 'Destination must be a directory.' }
        $nodes = @((Get-Item -LiteralPath $Root -Force)) + @(Get-ChildItem -LiteralPath $Root -Force -Recurse)
        foreach ($n in $nodes) {
            if ($n.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked workspace paths are unsupported.' }
        }
        if (@(Get-ChildItem -LiteralPath $Root -Force).Count -gt 0 -and !(Test-Path -LiteralPath (Join-Path $Root '.deployment-workspace'))) { throw 'Destination is not an experiment workspace.' }
    }
    $ancestor = Split-Path $Root -Parent
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked workspace ancestors are unsupported.' }
        }
        $parent = Split-Path $ancestor -Parent
        if ($ancestor -eq $parent) { break }
        $ancestor = $parent
    }
}
function Invoke-WorkspaceTransaction {
    param([string]$Root, [scriptblock]$Action)
    Assert-Workspace $Root
    $parent = Split-Path $Root -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $token = [guid]::NewGuid().ToString('N')
    $stage = Join-Path $parent ('.deploy-stage-' + $token)
    $backup = Join-Path $parent ('.deploy-backup-' + $token)
    $moved = $false
    try {
        New-Item -ItemType Directory -Path $stage | Out-Null
        if (Test-Path -LiteralPath $Root) {
            Get-ChildItem -LiteralPath $Root -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stage -Recurse -Force -ErrorAction Stop }
        }
        Set-Content -LiteralPath (Join-Path $stage '.deployment-workspace') -Value 'Parnas deployment experiment v1' -Encoding UTF8
        & $Action $stage
        if (Test-Path -LiteralPath $Root) { Move-Item -LiteralPath $Root -Destination $backup -ErrorAction Stop; $moved = $true }
        try { Move-Item -LiteralPath $stage -Destination $Root -ErrorAction Stop }
        catch {
            if ($moved) { Move-Item -LiteralPath $backup -Destination $Root -ErrorAction Stop; $moved = $false }
            throw
        }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        # A backup is preserved if restoration failed. Never delete the sole surviving old workspace.
        if ((Test-Path -LiteralPath $backup) -and (Test-Path -LiteralPath $Root)) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
function New-Result {
    param([string]$Operation, [string]$Id, [string]$Application, [string]$PreviousId)
    [pscustomobject][ordered]@{
        Operation = $Operation; ReleaseId = $Id; Application = $Application
        Timestamp = [datetime]::UtcNow.ToString('o'); PreviousReleaseId = $PreviousId
    }
}
Import-Module (Join-Path $PSScriptRoot 'ReleaseManifest.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'ArtifactStore.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'DeploymentJournal.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'DeploymentPolicy.psm1') -Scope Local
function Test-Release {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ManifestPath)
    $d = Get-ReleaseDefinition $ManifestPath
    Test-DeploymentPolicy $d
    [pscustomobject]@{ Valid = $true; ReleaseId = $d.Id; Application = $d.Application; ArtifactCount = @($d.Files).Count }
}
function Install-Release {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ManifestPath, [Parameter(Mandatory)][string]$Destination)
    $d = Get-ReleaseDefinition $ManifestPath
    Test-DeploymentPolicy $d
    $root = Get-WorkspacePath $Destination
    Assert-Workspace $root
    $state = Get-DeploymentState $root
    if ($d.Id -in $state.UsedIds) { throw 'Release ID already deployed.' }
    if ($state.Current -and $state.Current.Application -ne $d.Application) { throw 'Application mismatch.' }
    $previous = if ($state.Current) { $state.Current.ReleaseId } else { '' }
    $record = New-Result 'Install' $d.Id $d.Application $previous
    Invoke-WorkspaceTransaction $root {
        param($stage)
        Save-ReleaseArtifact $stage $d
        Set-ActiveRelease $stage $d.Id
        Add-DeploymentRecord $stage $record
    }
    [pscustomobject]@{ Status = 'Succeeded'; ReleaseId = $d.Id; Application = $d.Application; Operation = 'Install' }
}
function Get-ReleaseHistory {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Destination)
    $root = Get-WorkspacePath $Destination
    Assert-Workspace $root
    Get-DeploymentRecord $root
}
function Get-ReleaseStatus {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Destination)
    $root = Get-WorkspacePath $Destination
    Assert-Workspace $root
    $state = Get-DeploymentState $root
    [pscustomobject]@{ Status = $(if ($state.Current) { 'Deployed' } else { 'Empty' }); ReleaseId = $(if ($state.Current) { $state.Current.ReleaseId } else { $null }); Application = $(if ($state.Current) { $state.Current.Application } else { $null }) }
}
function Undo-Release {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Destination)
    $root = Get-WorkspacePath $Destination
    Assert-Workspace $root
    $state = Get-DeploymentState $root
    if (!$state.Previous) { throw 'No previous release.' }
    $record = New-Result 'Rollback' $state.Previous.ReleaseId $state.Previous.Application $state.Current.ReleaseId
    Invoke-WorkspaceTransaction $root {
        param($stage)
        Set-ActiveRelease $stage $state.Previous.ReleaseId
        Add-DeploymentRecord $stage $record
    }
    [pscustomobject]@{ Status = 'Succeeded'; ReleaseId = $state.Previous.ReleaseId; Application = $state.Previous.Application; Operation = 'Rollback' }
}
Export-ModuleMember -Function Test-Release, Install-Release, Get-ReleaseHistory, Get-ReleaseStatus, Undo-Release
