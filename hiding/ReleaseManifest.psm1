function Read-CheckedManifest {
    param([string]$ManifestPath)
    $path = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).ProviderPath
    $m = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($m.releaseId -isnot [string] -or $m.application -isnot [string] -or $m.artifacts -isnot [array]) { throw 'Invalid manifest field types.' }
    if ($m.releaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' -or $m.releaseId -in @('.', '..')) { throw 'Invalid releaseId.' }
    if ([string]::IsNullOrWhiteSpace($m.application)) { throw 'application is required.' }
    if (@($m.artifacts).Count -eq 0) { throw 'At least one artifact is required.' }
    $base = Split-Path $path -Parent
    $targets = @()
    foreach ($a in $m.artifacts) {
        if ($a.source -isnot [string] -or $a.target -isnot [string] -or $a.sha256 -isnot [string]) { throw 'Invalid artifact field types.' }
        foreach ($p in @([string]$a.source, [string]$a.target)) {
            # Deliberately portable subset; reject traversal, drive paths, ADS, wildcards and device names.
            if ([string]::IsNullOrWhiteSpace($p) -or $p -match '(^[/\\]|[:*?"<>|]|(^|[/\\])\.\.?([/\\]|$))') { throw 'Unsafe relative artifact path.' }
            foreach ($part in ($p -split '[/\\]')) {
                if (!$part -or $part -match '[. ]$' -or $part -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)') { throw 'Unsafe path component.' }
            }
        }
        $target = $a.target.Replace('\', '/').ToLowerInvariant()
        foreach ($prior in $targets) {
            if ($target -eq $prior -or $target.StartsWith($prior + '/') -or $prior.StartsWith($target + '/')) { throw 'Conflicting artifact targets.' }
        }
        $targets += $target
        if ($a.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid SHA-256.' }
        $source = Join-Path $base $a.source.Replace('\', '/')
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing artifact: $($a.source)" }
        $nodePath = $source
        while ($nodePath) {
            $node = Get-Item -LiteralPath $nodePath -Force -ErrorAction Stop
            if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked artifact paths are unsupported.' }
            $parent = Split-Path $nodePath -Parent
            if ($parent -eq $nodePath) { break }
            $nodePath = $parent
        }
    }
    return $m
}
function Get-ReleaseDefinition {
    param([string]$ManifestPath)
    $m = Read-CheckedManifest $ManifestPath
    $base = Split-Path ([IO.Path]::GetFullPath($ManifestPath)) -Parent
    [pscustomobject]@{
        Id = [string]$m.releaseId
        Application = [string]$m.application
        Metadata = $m.metadata
        Files = @($m.artifacts | ForEach-Object {
            [pscustomobject]@{ SourcePath = (Join-Path $base $_.source.Replace('\', '/')); RelativePath = $_.target.Replace('\', '/'); Digest = $_.sha256 }
        })
    }
}
Export-ModuleMember -Function Get-ReleaseDefinition
