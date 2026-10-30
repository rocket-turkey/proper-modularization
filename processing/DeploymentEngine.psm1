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
function Read-Events {
    param([string]$Root)
    $path = Join-Path $Root 'journal.csv'
    if (!(Test-Path -LiteralPath $path)) { return }
    $header = Get-Content -LiteralPath $path -TotalCount 1 -ErrorAction Stop
    if ($header -ne '"Operation","ReleaseId","Application","Timestamp","PreviousReleaseId"') { throw 'Invalid journal header.' }
    $records = @(Import-Csv -LiteralPath $path -ErrorAction Stop)
    $stack = @()
    $seen = @()
    $app = $null
    foreach ($r in $records) {
        $previous = if ($stack.Count) { $stack[-1].ReleaseId } else { '' }
        if ($r.ReleaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or !$r.Application -or !$r.Timestamp -or $r.PreviousReleaseId -ne $previous) { throw 'Invalid journal record.' }
        $null = [datetime]::Parse($r.Timestamp, [Globalization.CultureInfo]::InvariantCulture)
        if ($app -and $app -ne $r.Application) { throw 'Journal application mismatch.' }
        $app = $r.Application
        if ($r.Operation -eq 'Install') {
            if ($r.ReleaseId -in $seen) { throw 'Duplicate journal release.' }
            $seen += $r.ReleaseId
            $stack += $r
        } elseif ($r.Operation -eq 'Rollback') {
            if ($stack.Count -lt 2 -or $r.ReleaseId -ne $stack[-2].ReleaseId) { throw 'Invalid rollback journal.' }
            $stack = @($stack | Select-Object -First ($stack.Count - 1))
        } else { throw 'Unknown journal operation.' }
        $r
    }
}
Import-Module (Join-Path $PSScriptRoot 'ReadRelease.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'ValidateRelease.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'CopyRelease.psm1') -Scope Local
Import-Module (Join-Path $PSScriptRoot 'WriteReleaseLog.psm1') -Scope Local
function Read-StepState {
    param([string]$Root)
    $events = @(Read-Events $Root)
    $stack = @()
    foreach ($e in $events) {
        if ($e.Operation -eq 'Install') { $stack += $e }
        else { $stack = @($stack | Select-Object -First ($stack.Count - 1)) }
    }
    [pscustomobject]@{
        Current = $(if ($stack.Count) { $stack[-1] } else { $null })
        Previous = $(if ($stack.Count -gt 1) { $stack[-2] } else { $null })
        UsedIds = @($events | Where-Object Operation -eq 'Install' | ForEach-Object ReleaseId)
    }
}
function Test-Release {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ManifestPath)
    $m = Read-Release $ManifestPath
    Confirm-Release $m $ManifestPath
    [pscustomobject]@{ Valid = $true; ReleaseId = $m.releaseId; Application = $m.application; ArtifactCount = @($m.artifacts).Count }
}
function Install-Release {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ManifestPath, [Parameter(Mandatory)][string]$Destination)
    $m = Read-Release $ManifestPath
    Confirm-Release $m $ManifestPath
    $root = Get-WorkspacePath $Destination
    Assert-Workspace $root
    $state = Read-StepState $root
    if ($m.releaseId -in $state.UsedIds) { throw 'Release ID already deployed.' }
    if ($state.Current -and $state.Current.Application -ne $m.application) { throw 'Application mismatch.' }
    $previous = if ($state.Current) { $state.Current.ReleaseId } else { '' }
    $record = New-Result 'Install' $m.releaseId $m.application $previous
    Invoke-WorkspaceTransaction $root {
        param($stage)
        Copy-Release $m $ManifestPath $stage
        Write-Event $stage $record
    }
    [pscustomobject]@{ Status = 'Succeeded'; ReleaseId = $m.releaseId; Application = $m.application; Operation = 'Install' }
}
function Get-ReleaseHistory {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Destination)
    $root = Get-WorkspacePath $Destination
    Assert-Workspace $root
    Read-Events $root
}
function Get-ReleaseStatus {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Destination)
    $root = Get-WorkspacePath $Destination
    Assert-Workspace $root
    $state = Read-StepState $root
    [pscustomobject]@{ Status = $(if ($state.Current) { 'Deployed' } else { 'Empty' }); ReleaseId = $(if ($state.Current) { $state.Current.ReleaseId } else { $null }); Application = $(if ($state.Current) { $state.Current.Application } else { $null }) }
}
function Undo-Release {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Destination)
    $root = Get-WorkspacePath $Destination
    Assert-Workspace $root
    $state = Read-StepState $root
    if (!$state.Previous) { throw 'No previous release.' }
    $record = New-Result 'Rollback' $state.Previous.ReleaseId $state.Previous.Application $state.Current.ReleaseId
    Invoke-WorkspaceTransaction $root {
        param($stage)
        $release = Join-Path $stage ('releases/' + $state.Previous.ReleaseId)
        if (!(Test-Path -LiteralPath $release -PathType Container)) { throw 'Stored release is missing.' }
        $active = Join-Path $stage 'active'
        if (Test-Path -LiteralPath $active) { Remove-Item -LiteralPath $active -Recurse -Force }
        Copy-Item -LiteralPath $release -Destination $active -Recurse -ErrorAction Stop
        Write-Event $stage $record
    }
    [pscustomobject]@{ Status = 'Succeeded'; ReleaseId = $state.Previous.ReleaseId; Application = $state.Previous.Application; Operation = 'Rollback' }
}
Export-ModuleMember -Function Test-Release, Install-Release, Get-ReleaseHistory, Get-ReleaseStatus, Undo-Release
