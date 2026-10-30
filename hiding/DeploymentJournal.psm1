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
function Write-Event {
    param([string]$Root, $Record)
    $Record | Export-Csv -LiteralPath (Join-Path $Root 'journal.csv') -Append -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
}function Get-DeploymentRecord { param([string]$Root) Read-Events $Root }
function Add-DeploymentRecord { param([string]$Root, $Record) Write-Event $Root $Record }
function Get-DeploymentState {
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
Export-ModuleMember -Function Get-DeploymentRecord, Add-DeploymentRecord, Get-DeploymentState
