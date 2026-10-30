function Write-Event {
    param([string]$Root, $Record)
    $Record | Export-Csv -LiteralPath (Join-Path $Root 'journal.csv') -Append -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
}Export-ModuleMember -Function Write-Event
