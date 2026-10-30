function Confirm-Release {
    param($Manifest, [string]$ManifestPath)
    $base = Split-Path ([IO.Path]::GetFullPath($ManifestPath)) -Parent
    foreach ($a in $Manifest.artifacts) {
        $source = Join-Path $base $a.source.Replace('\', '/')
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash -ne $a.sha256) { throw "Hash mismatch: $($a.source)" }
    }
}
Export-ModuleMember -Function Confirm-Release
